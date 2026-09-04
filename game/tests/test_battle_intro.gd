extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var host := SubViewport.new()
	host.size = Vector2i(720, 1602)
	root.add_child(host)
	var placeholder_sheet := load("res://scripts/placeholder_sheet.gd") as GDScript
	var placeholder: Dictionary = placeholder_sheet.build()
	var texture := ImageTexture.create_from_image(placeholder["image"])
	var anima_loader := load("res://scripts/anima_loader.gd") as GDScript
	var loaded: Dictionary = anima_loader.build(texture, placeholder["manifest"])
	var measured_manifest: Dictionary = placeholder["manifest"].duplicate(true)
	measured_manifest["render_metrics"] = {
		"reference_height_px": 200.0,
		"reference_width_px": 120.0,
	}
	var measured_loaded: Dictionary = anima_loader.build(texture, measured_manifest)
	var wide_image: Image = placeholder["image"].duplicate()
	wide_image.fill_rect(Rect2i(8, 50, 240, 200), Color("6fa8dc"))
	var wide_manifest: Dictionary = measured_manifest.duplicate(true)
	wide_manifest["render_metrics"]["reference_width_px"] = 240.0
	var wide_loaded: Dictionary = anima_loader.build(
		ImageTexture.create_from_image(wide_image), wide_manifest
	)
	var seeker_roster := load("res://scripts/seeker_roster.gd") as GDScript
	var seeker_loaded: Dictionary = seeker_roster.sheet(null)
	_test_fresh_intro_wiring()
	await _test_duel_intro(host, loaded, seeker_loaded)
	await _test_team_intro(host, loaded, seeker_loaded)
	await _test_team_switch_reframe(host, measured_loaded, wide_loaded, seeker_loaded)
	await _test_expedition_intro(host, loaded, seeker_loaded)
	host.queue_free()
	if _failures == 0:
		print("test_battle_intro: OK (3 modes + switch framing)")
		quit()
		return
	print("test_battle_intro: FAILED %d check(s)" % _failures)
	quit(1)


func _test_fresh_intro_wiring() -> void:
	var flow := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var duel_start := _source_function(flow, "func _start_battle(")
	var duel_resume := _source_function(flow, "func _resume_battle(")
	var team_start := _source_function(flow, "func _start_team_battle(")
	var team_resume := _source_function(flow, "func _resume_team_battle(")
	_check(
		duel_start.find("_show_battle_session(session, true)") >= 0
		and duel_start.find("_set_busy(false)")
		< duel_start.find("await _battle_view.play_opening_intro()")
		and duel_resume.find("play_opening_intro") < 0,
		"only a fresh Duel start plays its opening after LoadingScreen is released"
	)
	_check(
		team_start.find("_show_team_battle_session(session, true)") >= 0
		and team_start.find("_set_busy(false)")
		< team_start.find("await _team_battle_view.play_opening_intro()")
		and team_resume.find("play_opening_intro") < 0,
		"only a fresh Team Battle start plays its opening after LoadingScreen is released"
	)
	var controller := FileAccess.get_file_as_string(
		"res://scripts/expedition_controller.gd"
	)
	var submit := _source_function(controller, "func _submit_pending(")
	var present := _source_function(controller, "func _present(")
	_check(
		submit.find("_present(operation == \"enter_node\")") >= 0
		and present.find("str(_encounter.get(\"kind\", \"\")) in [\"battle\", \"elite\"]") >= 0
		and present.find("_set_busy(false)") < present.find("await _view.play_combat_intro()"),
		"only a freshly entered non-Boss Expedition battle plays the shared opening"
	)


func _source_function(source: String, declaration: String) -> String:
	var start := source.find(declaration)
	var end := source.find("\n\nfunc ", start + declaration.length())
	return source.substr(start, end - start) if start >= 0 and end > start else ""


func _test_duel_intro(host: SubViewport, loaded: Dictionary, seeker_loaded: Dictionary) -> void:
	var packed := load("res://scenes/ui/battle_view.tscn") as PackedScene
	var view := packed.instantiate()
	host.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	view.set_player_avatar(seeker_loaded)
	var session := {
		"id": "intro-duel",
		"status": "active",
		"turn_number": 1,
		"version": 1,
		"player_snapshot": {"id": "player", "name": "Player", "element": "spark"},
		"bot_snapshot": {"id": "opponent", "name": "Opponent", "element": "flow"},
		"state": {
			"player": {"hp": 50, "max_hp": 50, "momentum": 3, "spd": 20},
			"bot": {"hp": 50, "max_hp": 50, "momentum": 3, "spd": 10},
		},
	}
	view.set_session(session, loaded, loaded, {}, true)
	var player := view.find_child("BattlePlayerSprite", true, false) as AnimatedSprite2D
	var opponent := view.find_child("BattleBotSprite", true, false) as AnimatedSprite2D
	var seeker := view.find_child("PlayerSeeker", true, false) as AnimatedSprite2D
	var player_shadow := player.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	var opponent_shadow := opponent.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	var footer := view.find_child("BattleFooter", true, false) as Control
	var strike := view.find_child("BattleStrikeButton", true, false) as Button
	_check(
		seeker.visible
		and player.sprite_frames != null
		and opponent.sprite_frames != null
		and not player.visible
		and not opponent.visible
		and not player_shadow.visible
		and not opponent_shadow.visible
		and not (view.find_child("StatusOverlay", true, false) as Control).visible
		and not (view.find_child("FighterHudPlate", true, false) as Control).visible
		and is_zero_approx(footer.modulate.a)
		and strike.disabled,
		"fresh Duel starts on the player Seeker alone with combat chrome locked"
	)
	var reveal_order: Array[String] = []
	var opponent_settled := [false]
	opponent.visibility_changed.connect(func() -> void:
		if opponent.visible:
			reveal_order.append("opponent")
			_check(
				not player.visible and seeker.animation == "intro_idle",
				"Duel reveals the opponent before the player summon"
			)
	)
	player.visibility_changed.connect(func() -> void:
		if player.visible:
			reveal_order.append("player")
			var portal := opponent.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect
			opponent_settled[0] = not portal.is_active() and seeker.animation == "switch_command"
	)
	await view.play_opening_intro()
	_check(
		reveal_order == ["opponent", "player"]
		and opponent_settled[0]
		and player_shadow.visible
		and opponent_shadow.visible
		and (view.find_child("StatusOverlay", true, false) as Control).visible
		and (view.find_child("FighterHudPlate", true, false) as Control).visible
		and is_equal_approx(footer.modulate.a, 1.0)
		and not strike.disabled
		and seeker.animation == "intro_idle",
		"Duel intro settles both summons before restoring combat UI"
	)
	view.set_session(session, loaded, loaded)
	await view.play_opening_intro()
	_check(
		player.visible and opponent.visible
		and not (player.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect).is_active()
		and not (opponent.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect).is_active(),
		"ordinary Duel session refresh does not replay the opening intro"
	)
	view.queue_free()
	await process_frame


func _test_team_intro(host: SubViewport, loaded: Dictionary, seeker_loaded: Dictionary) -> void:
	var packed := load("res://scenes/ui/team_battle_view.tscn") as PackedScene
	var view := packed.instantiate()
	host.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	view.set_player_avatar(seeker_loaded)
	var player_id := "00000000-0000-4000-8000-000000000001"
	var opponent_id := "10000000-0000-4000-8000-000000000001"
	var player_member := {
		"anima_id": player_id, "name": "Player", "level": 2,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
	}
	var opponent_member := {
		"anima_id": opponent_id, "name": "Opponent", "level": 2,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
	}
	var session := {
		"id": "intro-team",
		"kind": "team_battle",
		"status": "active",
		"turn_number": 1,
		"version": 1,
		"player_snapshot": [{"anima_id": player_id}],
		"opponent_snapshot": [{"anima_id": opponent_id}],
		"state": {
			"status": "active",
			"turn": 1,
			"player": {"active_slot": 0, "forced_switch": false, "roster": [player_member]},
			"opponent": {"active_slot": 0, "forced_switch": false, "roster": [opponent_member]},
		},
	}
	var art_cache := {player_id: loaded, opponent_id: loaded}
	view.set_session(session, art_cache, true)
	var player := view.find_child("TeamPlayerSprite", true, false) as AnimatedSprite2D
	var opponent := view.find_child("TeamOpponentSprite", true, false) as AnimatedSprite2D
	var seeker := view.find_child("PlayerSeeker", true, false) as AnimatedSprite2D
	var player_shadow := player.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	var opponent_shadow := opponent.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	var dock := view.find_child("TeamDock", true, false) as Control
	var attack := view.find_child("TeamAttackButton", true, false) as Button
	_check(
		seeker.visible
		and not player.visible
		and not opponent.visible
		and not player_shadow.visible
		and not opponent_shadow.visible
		and not (view.find_child("ArenaHud", true, false) as Control).visible
		and is_zero_approx(dock.modulate.a)
		and attack.disabled,
		"fresh Team Battle starts on the player Seeker alone with combat chrome locked"
	)
	var reveal_order: Array[String] = []
	var opponent_settled := [false]
	opponent.visibility_changed.connect(func() -> void:
		if opponent.visible:
			reveal_order.append("opponent")
			_check(
				not player.visible and seeker.animation == "intro_idle",
				"Team Battle reveals the opponent before the player summon"
			)
	)
	player.visibility_changed.connect(func() -> void:
		if player.visible:
			reveal_order.append("player")
			var portal := opponent.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect
			opponent_settled[0] = not portal.is_active() and seeker.animation == "switch_command"
	)
	await view.play_opening_intro()
	_check(
		reveal_order == ["opponent", "player"]
		and opponent_settled[0]
		and player_shadow.visible
		and opponent_shadow.visible
		and (view.find_child("ArenaHud", true, false) as Control).visible
		and is_equal_approx(dock.modulate.a, 1.0)
		and not attack.disabled
		and seeker.animation == "intro_idle",
		"Team Battle intro settles both summons before restoring combat UI"
	)
	view.set_session(session, art_cache)
	await view.play_opening_intro()
	_check(
		player.visible and opponent.visible
		and not (player.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect).is_active()
		and not (opponent.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect).is_active(),
		"ordinary Team Battle session refresh does not replay the opening intro"
	)
	view.queue_free()
	await process_frame


## Repro pemain: Switch dari Anima kecil ke Anima raksasa ketika rival aktif
## sudah raksasa. Perubahan bingkai memang diperlukan untuk lebar dua tubuh,
## tetapi tubuh incoming harus muncul selama kamera bergerak dan background
## statis harus ikut parallax; kalau tidak, semua figur menyusut di dunia beku.
func _test_team_switch_reframe(
	host: SubViewport,
	loaded: Dictionary,
	wide_loaded: Dictionary,
	seeker_loaded: Dictionary
) -> void:
	var packed := load("res://scenes/ui/team_battle_view.tscn") as PackedScene
	var view := packed.instantiate()
	host.add_child(view)
	view.visible = true
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.position = Vector2.ZERO
	view.size = Vector2(host.size)
	await process_frame
	view.set_player_avatar(seeker_loaded)
	var small_id := "00000000-0000-4000-8000-000000000021"
	var giant_id := "00000000-0000-4000-8000-000000000022"
	var rival_id := "10000000-0000-4000-8000-000000000021"
	var small := {
		"anima_id": small_id, "name": "Small", "level": 2,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": 50,
	}
	var giant: Dictionary = small.duplicate(true)
	giant["anima_id"] = giant_id
	giant["name"] = "Giant"
	giant["body_height_cm"] = 2000
	var rival: Dictionary = giant.duplicate(true)
	rival["anima_id"] = rival_id
	rival["name"] = "Rival Giant"
	var session := {
		"id": "switch-framing-team",
		"kind": "team_battle",
		"status": "active",
		"turn_number": 1,
		"version": 1,
		"player_snapshot": [{"anima_id": small_id}, {"anima_id": giant_id}],
		"opponent_snapshot": [{"anima_id": rival_id}],
		"state": {
			"status": "active",
			"turn": 1,
			"player": {
				"active_slot": 0,
				"forced_switch": false,
				"roster": [small, giant],
			},
			"opponent": {
				"active_slot": 0,
				"forced_switch": false,
				"roster": [rival],
			},
		},
	}
	var art_cache := {
		small_id: loaded,
		giant_id: wide_loaded,
		rival_id: loaded,
	}
	view.set_session(session, art_cache)
	await process_frame
	var layer := view.find_child("FighterLayer", true, false) as Node2D
	var player := view.find_child("TeamPlayerSprite", true, false) as AnimatedSprite2D
	var background := view.find_child("TeamArenaBackground", true, false) as TextureRect
	var background_material := background.material as ShaderMaterial
	_check(
		background_material.shader.code.contains("uniform float camera_zoom"),
		"Team background camera zoom is rendered through shader UVs, not only Control size"
	)
	var camera_zoom_before := layer.scale.x
	var background_zoom_before := float(
		background_material.get_shader_parameter("camera_zoom")
	)
	var switched: Dictionary = session.duplicate(true)
	switched["state"]["player"]["active_slot"] = 1
	var saw_player_hidden := false
	var reveal_during_refit := false
	view.play_events(
		[{"type": "switch", "actor": "player", "from_slot": 0, "to_slot": 1}],
		switched,
		art_cache
	)
	var deadline := Time.get_ticks_msec() + 8000
	while bool(view.get("_busy")) and Time.get_ticks_msec() < deadline:
		var refit := view.get("_layout_tween") as Tween
		if not player.visible:
			saw_player_hidden = true
		if saw_player_hidden and player.visible and refit != null and refit.is_running():
			reveal_during_refit = true
		await process_frame
	var camera_zoom_after := layer.scale.x
	var background_zoom_after := float(
		background_material.get_shader_parameter("camera_zoom")
	)
	var camera_ratio := camera_zoom_after / camera_zoom_before
	var background_ratio := background_zoom_after / background_zoom_before
	_check(not bool(view.get("_busy")), "the giant Switch completes inside the regression deadline")
	_check(
		camera_ratio < 0.99,
		"the wide incoming Anima forces the fixture camera to zoom out"
	)
	_check(
		background_ratio <= 0.95 and background_ratio > camera_ratio,
		"the static arena shows clear zoom-out with gentler background parallax"
	)
	_check(
		reveal_during_refit,
		"the giant incoming Anima reveals while camera and arena framing continue moving"
	)
	view.play_events(
		[{"type": "switch", "actor": "player", "from_slot": 1, "to_slot": 0}],
		session,
		art_cache
	)
	var return_deadline := Time.get_ticks_msec() + 8000
	while bool(view.get("_busy")) and Time.get_ticks_msec() < return_deadline:
		await process_frame
	_check(
		not bool(view.get("_busy"))
		and is_equal_approx(layer.scale.x, camera_zoom_before)
		and is_equal_approx(
			float(background_material.get_shader_parameter("camera_zoom")),
			background_zoom_before
		),
		"the reverse giant-to-small Switch restores fighter and background camera zoom together"
	)
	view.queue_free()
	await process_frame


func _test_expedition_intro(
	host: SubViewport,
	loaded: Dictionary,
	seeker_loaded: Dictionary
) -> void:
	var packed := load("res://scenes/ui/expedition_view.tscn") as PackedScene
	var view := packed.instantiate()
	host.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	if not view.has_method("play_combat_intro"):
		_check(false, "Expedition exposes the awaited fresh-encounter intro seam")
		view.queue_free()
		await process_frame
		return
	view.open_mode()
	view.set_player_avatar(seeker_loaded)
	var player_id := "00000000-0000-4000-8000-000000000011"
	var opponent_id := "10000000-0000-4000-8000-000000000011"
	var player_member := {
		"anima_id": player_id, "name": "Trail Player", "level": 2,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
	}
	var opponent_member := {
		"anima_id": opponent_id, "name": "Trail Rival", "level": 2,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
	}
	var encounter := {
		"id": "intro-expedition",
		"kind": "elite",
		"status": "active",
		"turn_number": 1,
		"version": 1,
		"player_snapshot": [{"anima_id": player_id}],
		"opponent_snapshot": [{"anima_id": opponent_id}],
		"state": {
			"status": "active",
			"turn": 1,
			"player": {"active_slot": 0, "forced_switch": false, "roster": [player_member]},
			"opponent": {"active_slot": 0, "forced_switch": false, "roster": [opponent_member]},
		},
	}
	var run_data := {
		"id": "intro-run",
		"status": "active",
		"zone": 1,
		"chapter_version_id": "chapter-intro",
	}
	var art_cache := {player_id: loaded, opponent_id: loaded}
	view.set_run(run_data, encounter, art_cache, true)
	var player := view.find_child("TeamPlayerSprite", true, false) as AnimatedSprite2D
	var opponent := view.find_child("TeamOpponentSprite", true, false) as AnimatedSprite2D
	var location := view.find_child("TeamTurn", true, false) as Label
	_check(
		view.is_combat_open()
		and not player.visible
		and not opponent.visible
		and not location.visible,
		"a fresh non-Boss Expedition encounter opens on the player Seeker alone"
	)
	await view.play_combat_intro()
	_check(
		player.visible
		and opponent.visible
		and (view.find_child("ArenaHud", true, false) as Control).visible
		and is_equal_approx(
			(view.find_child("TeamDock", true, false) as Control).modulate.a,
			1.0
		),
		"non-Boss Expedition restores the shared combat arena after both summons"
	)
	view.set_run(run_data, encounter, art_cache)
	await view.play_combat_intro()
	_check(
		player.visible and opponent.visible,
		"resuming the same Expedition encounter does not replay the opening intro"
	)
	view.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
