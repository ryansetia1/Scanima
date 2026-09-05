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
	var seeker_roster := load("res://scripts/seeker_roster.gd") as GDScript
	var seeker_loaded: Dictionary = seeker_roster.sheet(null)
	_test_grounded_background_math()
	_test_fresh_intro_wiring()
	await _test_duel_intro(host, loaded, seeker_loaded)
	await _test_team_intro(host, loaded, seeker_loaded)
	await _test_team_switch_reframe(host, measured_loaded, seeker_loaded)
	await _test_expedition_intro(host, loaded, seeker_loaded)
	host.queue_free()
	if _failures == 0:
		print("test_battle_intro: OK (3 modes + size/aspect grounding + switch framing)")
		quit()
		return
	print("test_battle_intro: FAILED %d check(s)" % _failures)
	quit(1)


func _test_grounded_background_math() -> void:
	var impact_script := load("res://scripts/battle_impact.gd") as GDScript
	var guard := float(impact_script.background_overscan_px(720.0))
	for stage_size: Vector2 in [Vector2(720.0, 1378.0), Vector2(1378.0, 720.0)]:
		for texture_size: Vector2 in [Vector2(1024.0, 576.0), Vector2(576.0, 1024.0)]:
			for geometry_zoom: float in [1.0, 1.55]:
				var draw_size := BattleScale.background_draw_size(
					texture_size, stage_size, guard, geometry_zoom
				)
				var background_y := BattleScale.grounded_background_y(
					stage_size.y, draw_size.y
				)
				var painted_floor_y := (
					background_y + draw_size.y * BattleScale.GROUND_Y_RATIO
				)
				var fighter_floor_y := stage_size.y * BattleScale.GROUND_Y_RATIO
				_check(
					is_equal_approx(painted_floor_y, fighter_floor_y),
					"grounded background math preserves the shared floor line"
				)
				_check(
					background_y <= -guard + 0.01
					and background_y + draw_size.y >= stage_size.y + guard - 0.01,
					"grounded background math preserves vertical impact overscan"
				)


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
	var safe_host := MarginContainer.new()
	safe_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_host.add_theme_constant_override("margin_left", 24)
	safe_host.add_theme_constant_override("margin_top", 60)
	safe_host.add_theme_constant_override("margin_right", 32)
	safe_host.add_theme_constant_override("margin_bottom", 80)
	host.add_child(safe_host)
	var view := packed.instantiate()
	safe_host.add_child(view)
	view.visible = true
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
	await process_frame
	var player := view.find_child("BattlePlayerSprite", true, false) as AnimatedSprite2D
	var opponent := view.find_child("BattleBotSprite", true, false) as AnimatedSprite2D
	var seeker := view.find_child("PlayerSeeker", true, false) as AnimatedSprite2D
	var player_shadow := player.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	var opponent_shadow := opponent.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	var footer := view.find_child("BattleFooter", true, false) as Control
	var strike := view.find_child("BattleStrikeButton", true, false) as Button
	var arena := view.find_child("BattleArena", true, false) as Control
	var player_anchor := view.find_child("BattlePlayerAnchor", true, false) as Node2D
	var background := view.find_child("BattleArenaBackground", true, false) as TextureRect
	var background_material := background.material as ShaderMaterial
	var zoom_value: Variant = background_material.get_shader_parameter("camera_zoom")
	var arena_rect := arena.get_global_rect()
	var safe_rect: Rect2 = view.get_global_rect()
	var cinematic_ground_y := player_anchor.global_position.y
	_check(
		arena_rect.is_equal_approx(Rect2(Vector2.ZERO, Vector2(host.size)))
		and arena_rect.encloses(footer.get_global_rect())
		and safe_rect.encloses(footer.get_global_rect()),
		"Duel arena fills behind device insets while command chrome stays in the safe area"
	)
	_check_background_grounding(
		arena,
		background,
		float(zoom_value) if zoom_value != null else 1.0,
		"Duel arena"
	)
	_check_fighter_bounds(arena, player, "Duel player")
	_check_fighter_bounds(arena, opponent, "Duel opponent")
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
		and footer.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and strike.disabled
		and strike.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and strike.focus_mode == Control.FOCUS_NONE,
		"fresh Duel starts on the player Seeker alone with hidden chrome unable to receive input"
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
	view.play_opening_intro()
	var transition_started_at := -1
	var saw_joint_transition := false
	var transition_deadline := Time.get_ticks_msec() + 10000
	while strike.disabled and Time.get_ticks_msec() < transition_deadline:
		if footer.modulate.a > 0.01 and footer.modulate.a < 0.99:
			if transition_started_at < 0:
				transition_started_at = Time.get_ticks_msec()
			saw_joint_transition = (
				player_anchor.global_position.y < cinematic_ground_y - 1.0
				and arena.get_global_rect().is_equal_approx(arena_rect)
				and strike.disabled
				and strike.mouse_filter == Control.MOUSE_FILTER_IGNORE
				and strike.focus_mode == Control.FOCUS_NONE
			)
		await process_frame
	var transition_elapsed := (
		Time.get_ticks_msec() - transition_started_at if transition_started_at >= 0 else 0
	)
	_check(
		reveal_order == ["opponent", "player"]
		and opponent_settled[0]
		and saw_joint_transition
		and transition_elapsed >= 220
		and transition_elapsed <= 520
		and player_shadow.visible
		and opponent_shadow.visible
		and (view.find_child("StatusOverlay", true, false) as Control).visible
		and (view.find_child("FighterHudPlate", true, false) as Control).visible
		and is_equal_approx(footer.modulate.a, 1.0)
		and player_anchor.global_position.y < cinematic_ground_y - 1.0
		and arena.get_global_rect().is_equal_approx(arena_rect)
		and not strike.disabled
		and seeker.animation == "intro_idle",
		"Duel intro reframes the whole world with Chrome for 0.32 seconds before input unlocks"
	)
	var gameplay_arena_rect := arena.get_global_rect()
	var gameplay_player_position := player_anchor.global_position
	view.set_session(session, loaded, loaded)
	await view.play_opening_intro()
	_check(
		player.visible and opponent.visible
		and not (player.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect).is_active()
		and not (opponent.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect).is_active(),
		"ordinary Duel session refresh does not replay the opening intro"
	)
	var result_session := session.duplicate(true)
	result_session["status"] = "won"
	var result_state := (result_session["state"] as Dictionary).duplicate(true)
	result_state["status"] = "won"
	result_session["state"] = result_state
	view.set_session(result_session, loaded, loaded)
	await process_frame
	var result_panel := view.find_child("BattleResultPanel", true, false) as Control
	var overlay := view.find_child("BattleOverlay", true, false) as Control
	var actions := view.find_child("Actions", true, false) as Control
	_check(
		result_panel.visible
		and result_panel.get_parent() == overlay
		and not actions.visible
		and arena.get_global_rect().is_equal_approx(gameplay_arena_rect)
		and player_anchor.global_position.is_equal_approx(gameplay_player_position),
		"Duel result overlays the final pose without resizing or reframing the arena"
	)
	host.size = Vector2i(1602, 720)
	await process_frame
	await process_frame
	_check(
		arena.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, Vector2(host.size)))
		and view.get_global_rect().encloses(footer.get_global_rect()),
		"Duel arena remains full-bleed and Chrome remains safe in landscape"
	)
	host.size = Vector2i(720, 1602)
	await process_frame
	safe_host.queue_free()
	await process_frame


func _test_team_intro(host: SubViewport, loaded: Dictionary, seeker_loaded: Dictionary) -> void:
	var packed := load("res://scenes/ui/team_battle_view.tscn") as PackedScene
	var safe_host := MarginContainer.new()
	safe_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_host.add_theme_constant_override("margin_left", 24)
	safe_host.add_theme_constant_override("margin_top", 60)
	safe_host.add_theme_constant_override("margin_right", 32)
	safe_host.add_theme_constant_override("margin_bottom", 80)
	host.add_child(safe_host)
	var view := packed.instantiate()
	safe_host.add_child(view)
	view.visible = true
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
	await process_frame
	var player := view.find_child("TeamPlayerSprite", true, false) as AnimatedSprite2D
	var opponent := view.find_child("TeamOpponentSprite", true, false) as AnimatedSprite2D
	var seeker := view.find_child("PlayerSeeker", true, false) as AnimatedSprite2D
	var player_shadow := player.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	var opponent_shadow := opponent.get_parent().find_child("GroundShadow", false, false) as Sprite2D
	var dock := view.find_child("TeamDock", true, false) as Control
	var attack := view.find_child("TeamAttackButton", true, false) as Button
	var stage := view.find_child("TeamBattleStage", true, false) as Control
	var chrome := view.find_child("TeamChrome", true, false) as Control
	var overlay := view.find_child("TeamOverlay", true, false) as Control
	var arena_rect := stage.get_global_rect()
	var safe_rect: Rect2 = view.get_global_rect()
	var arena_layers := stage.get_parent()
	var player_anchor := view.find_child("TeamPlayerAnchor", true, false) as Node2D
	var cinematic_ground_y := player_anchor.global_position.y
	_check(
		arena_rect.is_equal_approx(Rect2(Vector2.ZERO, Vector2(host.size)))
		and arena_rect.encloses(dock.get_global_rect())
		and safe_rect.encloses(dock.get_global_rect())
		and chrome != null
		and overlay != null
		and arena_layers.get_parent() == view.find_child("TeamArena", true, false)
		and (chrome == null or chrome.get_parent() == arena_layers),
		"Team arena fills behind device insets while Chrome stays in the safe area "
		+ "(arena=%s host=%s safe=%s dock=%s chrome=%s)" % [
			arena_rect, Rect2(Vector2.ZERO, Vector2(host.size)), safe_rect,
			dock.get_global_rect(), chrome.get_global_rect() if chrome != null else Rect2(),
		]
	)
	if chrome == null or overlay == null:
		safe_host.queue_free()
		await process_frame
		return
	_check(
		seeker.visible
		and not player.visible
		and not opponent.visible
		and not player_shadow.visible
		and not opponent_shadow.visible
		and is_zero_approx(chrome.modulate.a)
		and dock.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and attack.disabled
		and attack.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and attack.focus_mode == Control.FOCUS_NONE,
		"fresh Team Battle starts on the player Seeker alone with hidden Chrome unable to receive input"
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
	view.play_opening_intro()
	var transition_started_at := -1
	var saw_joint_transition := false
	var transition_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < transition_deadline:
		if chrome.modulate.a > 0.01 and chrome.modulate.a < 0.99:
			if transition_started_at < 0:
				transition_started_at = Time.get_ticks_msec()
			saw_joint_transition = (
				player_anchor.global_position.y < cinematic_ground_y - 1.0
				and stage.get_global_rect().is_equal_approx(arena_rect)
				and attack.disabled
				and attack.mouse_filter == Control.MOUSE_FILTER_IGNORE
				and attack.focus_mode == Control.FOCUS_NONE
			)
		await process_frame
	var transition_elapsed := (
		Time.get_ticks_msec() - transition_started_at if transition_started_at >= 0 else 0
	)
	_check(
		reveal_order == ["opponent", "player"]
		and opponent_settled[0]
		and saw_joint_transition
		and transition_elapsed >= 220
		and transition_elapsed <= 520
		and player_shadow.visible
		and opponent_shadow.visible
		and is_equal_approx(chrome.modulate.a, 1.0)
		and player_anchor.global_position.y < cinematic_ground_y - 1.0
		and stage.get_global_rect().is_equal_approx(arena_rect)
		and not attack.disabled
		and seeker.animation == "intro_idle",
		"Team Battle reframes the world with Chrome for 0.32 seconds before input unlocks"
	)
	view.set_session(session, art_cache)
	await view.play_opening_intro()
	_check(
		player.visible and opponent.visible
		and not (player.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect).is_active()
		and not (opponent.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect).is_active(),
		"ordinary Team Battle session refresh does not replay the opening intro"
	)
	var gameplay_arena_rect := stage.get_global_rect()
	var gameplay_player_position := player_anchor.global_position
	var result_session := session.duplicate(true)
	result_session["status"] = "won"
	var result_state := (result_session["state"] as Dictionary).duplicate(true)
	result_state["status"] = "won"
	result_session["state"] = result_state
	view.set_session(result_session, art_cache)
	await process_frame
	var result := view.find_child("TeamResult", true, false) as Control
	var actions := view.find_child("TeamActions", true, false) as Control
	_check(
		result.visible
		and result.get_parent().get_parent() == overlay
		and not actions.visible
		and stage.get_global_rect().is_equal_approx(gameplay_arena_rect)
		and player_anchor.global_position.is_equal_approx(gameplay_player_position),
		"Team result overlays the final pose without resizing or reframing the arena"
	)
	host.size = Vector2i(1602, 720)
	await process_frame
	await process_frame
	_check(
		stage.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, Vector2(host.size)))
		and view.get_global_rect().encloses(dock.get_global_rect()),
		"Team arena remains full-bleed and Chrome remains safe in landscape "
		+ "(arena=%s host=%s safe=%s dock=%s)" % [
			stage.get_global_rect(), Rect2(Vector2.ZERO, Vector2(host.size)),
			view.get_global_rect(), dock.get_global_rect(),
		]
	)
	host.size = Vector2i(720, 1602)
	await process_frame
	safe_host.queue_free()
	await process_frame


## Repro pemain: Switch dari Anima pendek ke Anima tinggi dengan lebar art sama.
## Kamera tetap wajib bergerak bersama background; kalau mapping parallax punya
## plateau, Seeker menyusut di dunia beku walau shader menerima nilai valid.
func _test_team_switch_reframe(
	host: SubViewport,
	loaded: Dictionary,
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
		"body_height_cm": 20,
	}
	var giant: Dictionary = small.duplicate(true)
	giant["anima_id"] = giant_id
	giant["name"] = "Giant"
	giant["body_height_cm"] = 2000
	var rival: Dictionary = small.duplicate(true)
	rival["anima_id"] = rival_id
	rival["name"] = "Rival"
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
		giant_id: loaded,
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
	var team_script := view.get_script() as GDScript
	var width_background_zoom := float(team_script.background_zoom_for_switch(0.72, 0.54, 1.08))
	_check(
		width_background_zoom < 1.08
		and width_background_zoom > 1.08 * (0.54 / 0.72)
		and is_equal_approx(
			float(team_script.background_zoom_for_switch(0.54, 0.72, width_background_zoom)),
			1.08
		),
		"width-driven Switch keeps gentler bidirectional background parallax"
	)
	var camera_zoom_before := layer.scale.x
	var background_zoom_before := float(
		background_material.get_shader_parameter("camera_zoom")
	)
	var stage := view.find_child("TeamBattleStage", true, false) as Control
	_check_fighter_bounds(stage, player, "20 cm Team player")
	_check_background_grounding(
		stage,
		background,
		background_zoom_before,
		"Team arena before a size-changing Switch"
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
	_check_background_grounding(
		stage,
		background,
		background_zoom_after,
		"Team arena after a size-changing Switch"
	)
	_check_fighter_bounds(stage, player, "2000 cm Team player")
	_check(not bool(view.get("_busy")), "the giant Switch completes inside the regression deadline")
	_check(
		camera_ratio < 0.99,
		"the wide incoming Anima forces the fixture camera to zoom out"
	)
	_check(
		background_ratio <= 0.95 and background_ratio > camera_ratio,
		"the static arena shows clear zoom-out with gentler background parallax "
		+ "(camera=%.3f, background=%.3f)" % [camera_ratio, background_ratio]
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


func _check_background_grounding(
	stage: Control,
	background: TextureRect,
	camera_zoom: float,
	label: String
) -> void:
	var stage_rect := stage.get_global_rect()
	var background_rect := background.get_global_rect()
	if stage_rect.size.x <= 0.0 or stage_rect.size.y <= 0.0:
		_check(false, "%s has a settled, non-zero arena layout" % label)
		return
	var fighter_ground_y := stage_rect.position.y + stage_rect.size.y * BattleScale.GROUND_Y_RATIO
	var player_anchor := stage.find_child("TeamPlayerAnchor", true, false) as Node2D
	if player_anchor == null:
		player_anchor = stage.find_child("BattlePlayerAnchor", true, false) as Node2D
	if player_anchor != null:
		fighter_ground_y = player_anchor.global_position.y
	var material := background.material as ShaderMaterial
	var pivot_value: Variant = material.get_shader_parameter("camera_pivot_y")
	var camera_pivot_y := float(pivot_value) if pivot_value != null else 0.5
	var offset_value: Variant = material.get_shader_parameter("camera_offset_y")
	var camera_offset_y := float(offset_value) if offset_value != null else 0.0
	var painted_ground_uv := (
		camera_pivot_y
		+ (BattleScale.GROUND_Y_RATIO - camera_pivot_y - camera_offset_y) * camera_zoom
	)
	var source_ground_y := (
		background_rect.position.y + background_rect.size.y * painted_ground_uv
	)
	var dock := stage.get_parent().find_child("TeamDock", true, false) as Control
	var dock_top := dock.get_global_rect().position.y if dock != null else -1.0
	var layer := player_anchor.get_parent() as Node2D if player_anchor != null else null
	var impact_script := load("res://scripts/battle_impact.gd") as GDScript
	var guard := float(impact_script.background_overscan_px(stage_rect.size.x))
	_check(
		is_equal_approx(camera_pivot_y, BattleScale.GROUND_Y_RATIO),
		"%s zoom pivots around the shared fighter ground line" % label
	)
	_check(
		background_rect.position.y <= stage_rect.position.y - guard
		and background_rect.end.y >= stage_rect.end.y + guard,
		"%s keeps vertical impact overscan after ground anchoring" % label
	)
	_check(
		absf(source_ground_y - fighter_ground_y) <= 1.0,
		(
			"%s keeps the painted floor under fighter feet "
			+ "(floor %.1f, feet %.1f, dock %.1f, zoom %.3f, offset %.4f, "
			+ "layer_pos=%s, layer_scale=%s, background=%s)"
		) % [
			label, source_ground_y, fighter_ground_y, dock_top, camera_zoom,
			camera_offset_y, layer.position if layer != null else Vector2.ZERO,
			layer.scale if layer != null else Vector2.ZERO, background_rect,
		]
	)


func _check_fighter_bounds(stage: Control, fighter: AnimatedSprite2D, label: String) -> void:
	var body_value: Variant = fighter.call("body_viewport_rect")
	if typeof(body_value) != TYPE_RECT2:
		_check(false, "%s exposes its visible-body bounds" % label)
		return
	var body: Rect2 = body_value
	var stage_rect := stage.get_global_rect()
	_check(
		stage_rect.encloses(body),
		"%s visible body stays inside the battle arena" % label
	)


func _test_expedition_intro(
	host: SubViewport,
	loaded: Dictionary,
	seeker_loaded: Dictionary
) -> void:
	var packed := load("res://scenes/ui/expedition_view.tscn") as PackedScene
	var safe_host := MarginContainer.new()
	safe_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_host.add_theme_constant_override("margin_left", 24)
	safe_host.add_theme_constant_override("margin_top", 60)
	safe_host.add_theme_constant_override("margin_right", 32)
	safe_host.add_theme_constant_override("margin_bottom", 80)
	host.add_child(safe_host)
	var view := packed.instantiate()
	safe_host.add_child(view)
	view.visible = true
	await process_frame
	if not view.has_method("play_combat_intro"):
		_check(false, "Expedition exposes the awaited fresh-encounter intro seam")
		view.queue_free()
		await process_frame
		return
	view.open_mode()
	await process_frame
	view.set_player_avatar(seeker_loaded)
	var player_id := "00000000-0000-4000-8000-000000000011"
	var opponent_id := "10000000-0000-4000-8000-000000000011"
	var player_member := {
		"anima_id": player_id, "name": "Sunhound", "level": 16,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": 75,
	}
	var opponent_member := {
		"anima_id": opponent_id, "name": "Rimespin", "level": 8,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": 105,
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
	var background_image := Image.create(1024, 576, false, Image.FORMAT_RGBA8)
	background_image.fill(Color(0.2, 0.4, 0.6, 1.0))
	var background_texture := ImageTexture.create_from_image(background_image)
	var art_cache := {
		player_id: loaded,
		opponent_id: loaded,
		"arena_background": background_texture,
	}
	view.set_run(run_data, encounter, art_cache, true)
	await process_frame
	var stage := view.find_child("TeamBattleStage", true, false) as Control
	var dock := view.find_child("TeamDock", true, false) as Control
	var chrome := view.find_child("TeamChrome", true, false) as Control
	var overlay := view.find_child("TeamOverlay", true, false) as Control
	var arena_rect := stage.get_global_rect()
	_check(
		arena_rect.is_equal_approx(Rect2(Vector2.ZERO, Vector2(host.size)))
		and view.get_global_rect().encloses(dock.get_global_rect())
		and chrome != null
		and overlay != null,
		"Expedition Battle and Elite use the shared full-screen arena under safe Chrome "
		+ "(arena=%s host=%s safe=%s dock=%s)" % [
			arena_rect, Rect2(Vector2.ZERO, Vector2(host.size)),
			view.get_global_rect(), dock.get_global_rect(),
		]
	)
	var background := view.find_child("TeamArenaBackground", true, false) as TextureRect
	var background_material := background.material as ShaderMaterial
	_check_background_grounding(
		stage,
		background,
		float(background_material.get_shader_parameter("camera_zoom")),
		"Sugarworks Zone 2 Sunhound versus Rimespin Expedition arena"
	)
	var player := view.find_child("TeamPlayerSprite", true, false) as AnimatedSprite2D
	var opponent := view.find_child("TeamOpponentSprite", true, false) as AnimatedSprite2D
	_check_fighter_bounds(stage, player, "Sunhound")
	_check_fighter_bounds(stage, opponent, "Rimespin")
	var location := view.find_child("TeamTurn", true, false) as Label
	var attack := view.find_child("TeamAttackButton", true, false) as Button
	var player_anchor := view.find_child("TeamPlayerAnchor", true, false) as Node2D
	var cinematic_ground_y := player_anchor.global_position.y
	_check(
		view.is_combat_open()
		and not player.visible
		and not opponent.visible
		and not location.visible
		and is_zero_approx(chrome.modulate.a)
		and attack.disabled
		and attack.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and attack.focus_mode == Control.FOCUS_NONE,
		"a fresh non-Boss Expedition encounter opens on the player Seeker alone"
	)
	view.play_combat_intro()
	var transition_started_at := -1
	var saw_joint_transition := false
	var transition_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < transition_deadline:
		if chrome.modulate.a > 0.01 and chrome.modulate.a < 0.99:
			if transition_started_at < 0:
				transition_started_at = Time.get_ticks_msec()
			saw_joint_transition = (
				player_anchor.global_position.y < cinematic_ground_y - 1.0
				and stage.get_global_rect().is_equal_approx(arena_rect)
				and attack.disabled
				and attack.mouse_filter == Control.MOUSE_FILTER_IGNORE
				and attack.focus_mode == Control.FOCUS_NONE
			)
		await process_frame
	var transition_elapsed := (
		Time.get_ticks_msec() - transition_started_at if transition_started_at >= 0 else 0
	)
	_check(
		player.visible
		and opponent.visible
		and saw_joint_transition
		and transition_elapsed >= 220
		and transition_elapsed <= 520
		and (view.find_child("ArenaHud", true, false) as Control).visible
		and is_equal_approx(chrome.modulate.a, 1.0)
		and player_anchor.global_position.y < cinematic_ground_y - 1.0
		and not attack.disabled,
		"non-Boss Expedition completes the shared 0.32-second reframe before input unlocks"
	)
	view.set_run(run_data, encounter, art_cache)
	await view.play_combat_intro()
	_check(
		player.visible and opponent.visible,
		"resuming the same Expedition encounter does not replay the opening intro"
	)
	var battle_encounter: Dictionary = encounter.duplicate(true)
	battle_encounter["id"] = "intro-expedition-battle"
	battle_encounter["kind"] = "battle"
	view.set_run(run_data, battle_encounter, art_cache)
	await process_frame
	_check(
		stage.get_global_rect().is_equal_approx(arena_rect),
		"regular Expedition Battle keeps the same full-screen arena rectangle as Elite"
	)
	var boss_encounter: Dictionary = encounter.duplicate(true)
	boss_encounter["id"] = "intro-expedition-boss-foundation"
	boss_encounter["kind"] = "boss"
	view.set_run(run_data, boss_encounter, art_cache)
	await process_frame
	_check(
		stage.get_global_rect().is_equal_approx(arena_rect)
		and chrome.get_parent() == stage.get_parent()
		and overlay.get_parent() == stage.get_parent(),
		"the Expedition Boss foundation shares the Arena, Chrome, and Overlay layer contract"
	)
	host.size = Vector2i(1602, 720)
	await process_frame
	await process_frame
	_check(
		stage.get_global_rect().is_equal_approx(Rect2(Vector2.ZERO, Vector2(host.size)))
		and view.get_global_rect().encloses(dock.get_global_rect()),
		"Expedition and its Boss foundation keep full-bleed Arena and safe Chrome in landscape"
	)
	host.size = Vector2i(720, 1602)
	await process_frame
	safe_host.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
