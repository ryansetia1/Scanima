extends SceneTree

## Read-only production query on 2026-09-06. These three account-owned Anima
## reproduce the reported cross-arena scale mismatch.
const PADRONIC_HEIGHT_CM := 55.0
const STRIDARC_HEIGHT_CM := 55.0
const DRAKABYSS_HEIGHT_CM := 203.0

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if "--background-calibration-only" in OS.get_cmdline_user_args():
		_test_background_calibration_contract()
		_finish_calibration_only()
		return
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
	var tall_player_seeker_loaded: Dictionary = seeker_roster.sheet("automaton")
	_test_background_calibration_contract()
	_test_grounded_background_math()
	_test_fresh_intro_wiring()
	await _test_duel_intro(host, loaded, seeker_loaded)
	await _test_team_intro(host, loaded, seeker_loaded)
	await _test_team_switch_reframe(host, measured_loaded, seeker_loaded)
	await _test_expedition_intro(host, loaded, seeker_loaded)
	await _test_boss_intro(host, loaded, seeker_loaded, tall_player_seeker_loaded)
	await _test_boss_replay_and_cancellation(host, loaded, seeker_loaded)
	host.queue_free()
	if _failures == 0:
		print("test_battle_intro: OK (Duel/Team/Expedition + Boss opening/cancellation)")
		quit()
		return
	print("test_battle_intro: FAILED %d check(s)" % _failures)
	quit(1)


func _test_background_calibration_contract() -> void:
	var calibration_script := load("res://scripts/battle_background_calibration.gd") as GDScript
	_check(calibration_script != null, "Battle background calibration has one public production seam")
	if calibration_script == null:
		return
	var profiles: Dictionary = calibration_script.canonical_profiles()
	_check(
		profiles.keys() == [
			"duel_landscape", "duel_portrait", "team_landscape", "team_portrait",
		],
		"canonical calibration owns exactly four mode-orientation profiles"
	)
	for case: Dictionary in [
		{"mode": &"duel", "size": Vector2(720.0, 1602.0)},
		{"mode": &"duel", "size": Vector2(1602.0, 720.0)},
		{"mode": &"team", "size": Vector2(720.0, 1602.0)},
		{"mode": &"team", "size": Vector2(1602.0, 720.0)},
	]:
		var case_size: Vector2 = case["size"]
		var profile: Dictionary = calibration_script.profile_for(
			case["mode"], case_size, profiles
		)
		var portrait := case_size.y > case_size.x
		var expected_background_y := 100.0 if portrait else 5.0
		var offset_ratio: Vector2 = profile.get("offset_ratio")
		_check(
			is_zero_approx(offset_ratio.x)
			and is_equal_approx(offset_ratio.y * case_size.y, expected_background_y),
			"canonical background Y matches the approved orientation value"
		)
		_check(is_equal_approx(float(profile.get("zoom_multiplier")), 1.0), "canonical zoom stays neutral")
		_check(
			is_equal_approx(float(profile.get("pivot_y")), BattleScale.GROUND_Y_RATIO),
			"canonical pivot preserves today's shared ground line"
		)
		_check(
			is_equal_approx(float(profile.get("source_foot_y")), BattleScale.GROUND_Y_RATIO),
			"canonical source foot row preserves today's backdrop alignment"
		)
		var expected_fighter_y := -117.0 if portrait else -113.0
		_check(
			is_equal_approx(
				float(profile.get("fighter_offset_ratio_y", 999.0)) * case_size.y,
				expected_fighter_y
			),
			"canonical character Y matches the approved orientation value"
		)
	var stage_size := Vector2(720.0, 1602.0)
	var draw_size := Vector2(900.0, 1800.0)
	var canonical: Dictionary = calibration_script.profile_for(&"duel", stage_size, profiles)
	var canonical_position: Vector2 = calibration_script.background_position(
		stage_size, draw_size, 0.5, canonical
	)
	_check(
		canonical_position.is_equal_approx(Vector2(
			(stage_size.x - draw_size.x) * 0.5,
			BattleScale.grounded_background_y(stage_size.y, draw_size.y) + 100.0,
		)),
		"canonical portrait background applies the approved 100 px vertical offset"
	)
	_check(
		is_equal_approx(calibration_script.camera_offset(0.02, 1.08, canonical), 0.02),
		"canonical profile preserves the live shader offset"
	)
	_check(
		calibration_script.has_method("fighter_offset_y"),
		"calibration exposes one shared character vertical offset"
	)
	if calibration_script.has_method("fighter_offset_y"):
		var shifted_fighters := canonical.duplicate(true)
		shifted_fighters["fighter_offset_ratio_y"] = 0.1
		_check(
			is_equal_approx(calibration_script.fighter_offset_y(stage_size, shifted_fighters), 160.2),
			"character offset remains normalized across orientations"
		)
	var tuned := {
		"offset_ratio": Vector2(0.1, -0.05),
		"zoom_multiplier": 1.05,
		"pivot_y": 0.8,
		"source_foot_y": 0.85,
	}
	var tuned_position: Vector2 = calibration_script.background_position(
		stage_size, draw_size, 0.5, tuned
	)
	_check(
		is_equal_approx(tuned_position.x, -18.0)
		and is_equal_approx(
			tuned_position.y + draw_size.y * float(tuned["source_foot_y"]),
			stage_size.y * BattleScale.GROUND_Y_RATIO + stage_size.y * -0.05,
		),
		"tuned offsets stay normalized while source-foot calibration remains explicit"
	)
	var tuned_zoom: float = calibration_script.camera_zoom(1.04, tuned)
	_check(is_equal_approx(tuned_zoom, 1.092), "profile zoom multiplies Team's live camera response")
	_check(
		is_equal_approx(
			calibration_script.camera_offset(0.02, tuned_zoom, tuned),
			0.02 + 0.05 * (1.0 - 1.0 / tuned_zoom),
		),
		"source foot and vertical pivot compose without replacing the live camera offset"
	)
	_check(
		calibration_script.has_method("profile_is_safe"),
		"calibration exposes the save-safety gate"
	)
	if not calibration_script.has_method("profile_is_safe"):
		return
	var impact_script := load("res://scripts/battle_impact.gd") as GDScript
	var guard := float(impact_script.background_overscan_px(stage_size.x))
	_check(
		calibration_script.profile_is_safe(
			stage_size, Vector2(720.0, 1602.0), guard, [1.0, 1.04, 1.08], canonical
		),
		"canonical profile covers the full opening/gameplay and fighter-size matrix"
	)
	var unsafe := canonical.duplicate(true)
	unsafe["offset_ratio"] = Vector2(0.5, 0.5)
	_check(
		not calibration_script.profile_is_safe(
			stage_size, Vector2(720.0, 1602.0), guard, [1.0, 1.04, 1.08], unsafe
		),
		"free exploration may leave coverage, but unsafe profiles cannot be saved"
	)
	var safe_pan := canonical.duplicate(true)
	safe_pan["zoom_multiplier"] = 1.1
	safe_pan["offset_ratio"] = Vector2(0.01, 0.0)
	_check(
		calibration_script.profile_is_safe(
			stage_size, Vector2(720.0, 1602.0), guard, [1.0, 1.04, 1.08], safe_pan
		),
		"profile zoom creates enough cover crop to save a precise non-zero pan"
	)
	_check(
		calibration_script.has_method("profiles_to_json")
		and calibration_script.has_method("profiles_from_json")
		and calibration_script.has_method("gdscript_snippet"),
		"calibration exposes local persistence and deliberate production export"
	)
	if not calibration_script.has_method("profiles_to_json"):
		return
	var edited_profiles := profiles.duplicate(true)
	edited_profiles["duel_portrait"]["offset_ratio"] = Vector2(0.125, -0.25)
	var preset_json: String = calibration_script.profiles_to_json(edited_profiles)
	var restored: Dictionary = calibration_script.profiles_from_json(preset_json)
	_check(
		restored["duel_portrait"]["offset_ratio"] == Vector2(0.125, -0.25)
		and restored.size() == 4,
		"user preset JSON round-trips normalized vectors and all four profiles"
	)
	_check(
		calibration_script.profiles_from_json("not json") == profiles,
		"a corrupt local preset falls back to canonical production values"
	)
	var wrong_types: Dictionary = calibration_script.profiles_from_json(
		'{"duel_portrait":{"offset_ratio":["bad",null],"zoom_multiplier":"bad"}}'
	)
	_check(
		wrong_types["duel_portrait"] == profiles["duel_portrait"],
		"valid JSON with wrong field types is normalized without debugger errors"
	)
	var snippet: String = calibration_script.gdscript_snippet(edited_profiles)
	_check(
		snippet.begins_with("const PROFILES := {")
		and snippet.contains("\"duel_portrait\"")
		and snippet.contains("\"team_landscape\"")
		and snippet.contains("Vector2(0.125")
		and snippet.contains("-0.25"),
		"export emits one complete human-reviewable GDScript dictionary"
	)
	var tuner_script := load("res://scripts/battle_background_tuner.gd") as GDScript
	_check(tuner_script != null, "Battle background tuner has a developer-only UI seam")
	if tuner_script == null:
		return
	_check(
		tuner_script.should_start(["--battle-background-tuner"], true)
		and tuner_script.should_start(["--battle-background-tuner=team-landscape"], true),
		"the explicit flag and profile suffix start the tuner in a debug build"
	)
	_check(
		not tuner_script.should_start([], true)
		and not tuner_script.should_start(["--battle-background-tuner"], false),
		"the tuner cannot appear without its flag or in a release build"
	)
	var tuner_scene := load("res://scenes/components/battle_background_tuner.tscn") as PackedScene
	_check(tuner_scene != null, "Background tuner has a reusable overlay scene")
	if tuner_scene != null:
		var tuner := tuner_scene.instantiate()
		for control_name: String in [
			"DragSurface", "Mode", "Orientation", "Lighting", "Framing", "FighterPreset",
			"OffsetX", "OffsetY", "Zoom", "PivotY", "SourceFootY",
			"FighterOffsetYSlider", "FighterOffsetY", "Replay", "Save", "Copy",
		]:
			_check(
				tuner.find_child(control_name, true, false) != null,
				"Background tuner exposes %s" % control_name
			)
		var preview_modes: Array[StringName] = []
		var emitted_profiles: Array[Dictionary] = []
		tuner.preview_requested.connect(
			func(mode: StringName, _framing: StringName, _fighter: StringName, _light: float) -> void:
				preview_modes.append(mode)
		)
		tuner.profiles_changed.connect(
			func(value: Dictionary) -> void: emitted_profiles.append(value)
		)
		root.add_child(tuner)
		tuner.start()
		_check(preview_modes == [&"duel"], "Background tuner starts on a local Duel fixture")
		var zoom_field := tuner.find_child("Zoom", true, false) as SpinBox
		var offset_field := tuner.find_child("OffsetX", true, false) as SpinBox
		var offset_y_field := tuner.find_child("OffsetY", true, false) as SpinBox
		var fighter_offset_field := tuner.find_child("FighterOffsetY", true, false) as SpinBox
		zoom_field.value = 1.1
		offset_field.value = 7.2
		fighter_offset_field.value = 160.2
		_check(
			is_equal_approx(
				float(emitted_profiles[-1]["duel_portrait"]["fighter_offset_ratio_y"]), 0.1
			),
			"Character slider updates the active normalized profile"
		)
		var mode_picker := tuner.find_child("Mode", true, false) as OptionButton
		mode_picker.select(1)
		mode_picker.item_selected.emit(1)
		_check(preview_modes[-1] == &"team", "Background tuner switches to a local Team fixture")
		_check(is_zero_approx(offset_field.value), "Profile switches refresh their own X value")
		_check(
			is_equal_approx(offset_y_field.value, 100.0),
			"Profile switches refresh their own background Y value"
		)
		_check(
			is_equal_approx(fighter_offset_field.value, -117.0),
			"Character slider refreshes for the selected profile"
		)
		var status := tuner.find_child("Status", true, false) as Label
		_check(
			status.text.begins_with("BACKGROUND SAFE"),
			"Canonical tuner profiles pass the background safety matrix"
		)
		tuner.free()
	var scan_flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var tuner_entry_index := scan_flow_source.find("if _try_start_battle_background_tuner():")
	var auth_recovery_index := scan_flow_source.find("await AuthFlow.ensure_recovered()")
	_check(
		tuner_entry_index >= 0 and tuner_entry_index < auth_recovery_index,
		"Background tuner bypasses account recovery and backend boot"
	)


func _finish_calibration_only() -> void:
	if _failures == 0:
		print("test_battle_intro: background calibration OK")
		quit()
		return
	print("test_battle_intro: background calibration FAILED %d check(s)" % _failures)
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
		and present.find("str(_encounter.get(\"kind\", \"\")) in [\"battle\", \"elite\", \"boss\"]") >= 0
		and present.find("_set_busy(false)") < present.find("await _view.play_combat_intro()"),
		"only a freshly entered Expedition encounter plays its opening after Loading is released"
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
		"player_snapshot": {
			"id": "player", "name": "Drakabyss", "element": "spark",
			"body_height_cm": DRAKABYSS_HEIGHT_CM,
		},
		"bot_snapshot": {
			"id": "opponent", "name": "Padronic", "element": "flow",
			"body_height_cm": PADRONIC_HEIGHT_CM,
		},
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
	var fighter_hud_plate := view.find_child("FighterHudPlate", true, false) as Control
	var strike := view.find_child("BattleStrikeButton", true, false) as Button
	var arena := view.find_child("BattleArena", true, false) as Control
	var player_anchor := view.find_child("BattlePlayerAnchor", true, false) as Node2D
	var background := view.find_child("BattleArenaBackground", true, false) as TextureRect
	var background_material := background.material as ShaderMaterial
	var zoom_value: Variant = background_material.get_shader_parameter("camera_zoom")
	var arena_rect := arena.get_global_rect()
	var safe_rect: Rect2 = view.get_global_rect()
	_check_shared_character_offset(
		view, arena, player_anchor, opponent.get_parent(), seeker, "duel_portrait", "Duel"
	)
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
		and opponent.visible
		and not player_shadow.visible
		and opponent_shadow.visible
		and not (view.find_child("StatusOverlay", true, false) as Control).visible
		and not (view.find_child("FighterHudPlate", true, false) as Control).visible
		and is_zero_approx(footer.modulate.a)
		and footer.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and strike.disabled
		and strike.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and strike.focus_mode == Control.FOCUS_NONE,
		"fresh Duel starts on the player Seeker facing the waiting opponent Anima with hidden Chrome"
	)
	var reveal_order: Array[String] = []
	var opponent_waited_without_portal := [true]
	var player_revealed_in_stable_frame := [false]
	var opponent_portal := opponent.get_parent().find_child(
		"SummonPortal", false, false
	) as IncubatorEffect
	var cinematic_layer := player_anchor.get_parent() as Node2D
	var cinematic_layer_position := cinematic_layer.position
	var cinematic_layer_scale := cinematic_layer.scale
	opponent.visibility_changed.connect(func() -> void:
		if not opponent.visible:
			opponent_waited_without_portal[0] = false
	)
	player.visibility_changed.connect(func() -> void:
		if player.visible:
			reveal_order.append("player")
			opponent_waited_without_portal[0] = (
				opponent_waited_without_portal[0]
				and opponent.visible
				and not opponent_portal.is_active()
			)
			player_revealed_in_stable_frame[0] = (
				seeker.animation == "switch_command"
				and cinematic_layer.position.is_equal_approx(cinematic_layer_position)
				and cinematic_layer.scale.is_equal_approx(cinematic_layer_scale)
			)
	)
	view.play_opening_intro()
	var transition_started_at := -1
	var saw_joint_transition := false
	var transition_deadline := Time.get_ticks_msec() + 10000
	while strike.disabled and Time.get_ticks_msec() < transition_deadline:
		if not opponent.visible or opponent_portal.is_active():
			opponent_waited_without_portal[0] = false
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
		reveal_order == ["player"]
		and opponent_waited_without_portal[0]
		and player_revealed_in_stable_frame[0]
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
	_check(
		player_anchor.global_position.y < fighter_hud_plate.get_global_rect().position.y,
		"Duel gameplay keeps fighter ground above status and command Chrome "
		+ "(ground=%.1f hud_top=%.1f footer_top=%.1f)" % [
			player_anchor.global_position.y,
			fighter_hud_plate.get_global_rect().position.y,
			footer.get_global_rect().position.y,
		]
	)
	var gameplay_arena_rect := arena.get_global_rect()
	var gameplay_player_position := player_anchor.global_position
	var portrait_seeker_gap := _seeker_to_player_gap_ratio(arena, seeker, player)
	_check_regular_drakabyss_ratio(
		player_anchor, loaded, seeker, seeker_loaded, "Duel"
	)
	var duel_seeker_screen_scale := seeker.global_scale.x
	var duel_camera_scale := cinematic_layer.scale.x
	var giant_duel: Dictionary = session.duplicate(true)
	giant_duel["player_snapshot"]["body_height_cm"] = 2000
	view.set_session(giant_duel, loaded, loaded)
	await process_frame
	_check(
		is_equal_approx(
			seeker.global_scale.x / duel_seeker_screen_scale,
			cinematic_layer.scale.x / duel_camera_scale
		)
		and is_equal_approx(
			float(background_material.get_shader_parameter("camera_zoom")), 1.0
		),
		"Duel keeps its background at cover 1.0 while the player Seeker follows world camera scale"
	)
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
	var duel_landscape_gap := _seeker_to_player_gap_ratio(arena, seeker, player)
	_check(
		duel_landscape_gap <= portrait_seeker_gap + 0.04,
		"Duel landscape keeps the player Seeker attached to their Anima "
		+ "(portrait=%.3f landscape=%.3f)" % [portrait_seeker_gap, duel_landscape_gap]
	)
	host.size = Vector2i(720, 1602)
	await process_frame
	var missing_avatar_session: Dictionary = session.duplicate(true)
	missing_avatar_session["id"] = "intro-duel-missing-avatar"
	view.set_player_avatar({})
	view.set_session(missing_avatar_session, loaded, loaded, {}, true)
	var player_portal := player.get_parent().find_child(
		"SummonPortal", false, false
	) as IncubatorEffect
	var saw_player_portal := false
	view.play_opening_intro()
	var missing_avatar_deadline := Time.get_ticks_msec() + 10000
	while strike.disabled and Time.get_ticks_msec() < missing_avatar_deadline:
		saw_player_portal = saw_player_portal or player_portal.is_active()
		await process_frame
	_check(
		saw_player_portal and player.visible and opponent.visible and not strike.disabled,
		"Duel opening still Summons the player Anima and unlocks input without Seeker art"
	)
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
		"anima_id": player_id, "name": "Drakabyss", "level": 2,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": DRAKABYSS_HEIGHT_CM,
	}
	var opponent_member := {
		"anima_id": opponent_id, "name": "Stridarc", "level": 2,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": STRIDARC_HEIGHT_CM,
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
	_check_shared_character_offset(
		view, stage, player_anchor, opponent.get_parent(), seeker, "team_portrait", "Team"
	)
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
		and opponent.visible
		and not player_shadow.visible
		and opponent_shadow.visible
		and is_zero_approx(chrome.modulate.a)
		and dock.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and attack.disabled
		and attack.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and attack.focus_mode == Control.FOCUS_NONE,
		"fresh Team Battle starts on the player Seeker facing the waiting opponent Anima with hidden Chrome"
	)
	var reveal_order: Array[String] = []
	var opponent_waited_without_portal := [true]
	var player_revealed_in_stable_frame := [false]
	var opponent_portal := opponent.get_parent().find_child(
		"SummonPortal", false, false
	) as IncubatorEffect
	var cinematic_layer := player_anchor.get_parent() as Node2D
	var cinematic_layer_position := cinematic_layer.position
	var cinematic_layer_scale := cinematic_layer.scale
	opponent.visibility_changed.connect(func() -> void:
		if not opponent.visible:
			opponent_waited_without_portal[0] = false
	)
	player.visibility_changed.connect(func() -> void:
		if player.visible:
			reveal_order.append("player")
			opponent_waited_without_portal[0] = (
				opponent_waited_without_portal[0]
				and opponent.visible
				and not opponent_portal.is_active()
			)
			player_revealed_in_stable_frame[0] = (
				seeker.animation == "switch_command"
				and cinematic_layer.position.is_equal_approx(cinematic_layer_position)
				and cinematic_layer.scale.is_equal_approx(cinematic_layer_scale)
			)
	)
	view.play_opening_intro()
	var transition_started_at := -1
	var saw_joint_transition := false
	var transition_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < transition_deadline:
		if not opponent.visible or opponent_portal.is_active():
			opponent_waited_without_portal[0] = false
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
		reveal_order == ["player"]
		and opponent_waited_without_portal[0]
		and player_revealed_in_stable_frame[0]
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
	var portrait_seeker_gap := _seeker_to_player_gap_ratio(stage, seeker, player)
	_check_regular_drakabyss_ratio(
		player_anchor, loaded, seeker, seeker_loaded, "Team Battle"
	)
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
	var team_landscape_gap := _seeker_to_player_gap_ratio(stage, seeker, player)
	_check(
		team_landscape_gap <= portrait_seeker_gap + 0.04,
		"Team landscape keeps the player Seeker attached to their Anima "
		+ "(portrait=%.3f landscape=%.3f)" % [portrait_seeker_gap, team_landscape_gap]
	)
	host.size = Vector2i(720, 1602)
	await process_frame
	var missing_avatar_session: Dictionary = session.duplicate(true)
	missing_avatar_session["id"] = "intro-team-missing-avatar"
	view.set_player_avatar({})
	view.set_session(missing_avatar_session, art_cache, true)
	var player_portal := player.get_parent().find_child(
		"SummonPortal", false, false
	) as IncubatorEffect
	var saw_player_portal := false
	view.play_opening_intro()
	var missing_avatar_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < missing_avatar_deadline:
		saw_player_portal = saw_player_portal or player_portal.is_active()
		await process_frame
	_check(
		saw_player_portal and player.visible and opponent.visible and not attack.disabled,
		"Team opening still Summons the player Anima and unlocks input without Seeker art"
	)
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
	var player_seeker := view.find_child("PlayerSeeker", true, false) as Node2D
	var seeker_screen_scale_before := player_seeker.global_scale
	var seeker_local_scale := player_seeker.scale.x
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
	var seeker_scale_followed_camera := true
	view.play_events(
		[{"type": "switch", "actor": "player", "from_slot": 0, "to_slot": 1}],
		switched,
		art_cache
	)
	var deadline := Time.get_ticks_msec() + 8000
	while bool(view.get("_busy")) and Time.get_ticks_msec() < deadline:
		var refit := view.get("_layout_tween") as Tween
		seeker_scale_followed_camera = (
			seeker_scale_followed_camera
			and is_equal_approx(
				player_seeker.global_scale.x,
				seeker_local_scale * layer.scale.x
			)
		)
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
	_check(
		seeker_scale_followed_camera
		and is_equal_approx(
			player_seeker.global_scale.x / seeker_screen_scale_before.x,
			camera_zoom_after / camera_zoom_before
		),
		"the player Seeker follows the same camera scale as Anima throughout a size-changing Switch"
	)
	var switched_layout: Dictionary = view.call("_fighter_layout")
	var hit_only: Dictionary = switched.duplicate(true)
	hit_only["state"]["player"]["roster"][1]["hp"] = 41
	view.set_session(hit_only, art_cache)
	await process_frame
	var hit_layout: Dictionary = view.call("_fighter_layout")
	_check(
		(hit_layout["layer_position"] as Vector2).is_equal_approx(switched_layout["layer_position"])
		and (hit_layout["layer_scale"] as Vector2).is_equal_approx(switched_layout["layer_scale"])
		and is_equal_approx(
			float(hit_layout["background_camera_zoom"]),
			float(switched_layout["background_camera_zoom"])
		)
		and (hit_layout["background_position"] as Vector2).is_equal_approx(
			switched_layout["background_position"]
		)
		and (hit_layout["background_size"] as Vector2).is_equal_approx(
			switched_layout["background_size"]
		),
		"an HP-only authoritative repaint preserves the settled fighter/background framing"
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
	var frames := loaded.get("frames") as SpriteFrames
	var custom_art := art_cache.duplicate()
	custom_art["arena_background"] = frames.get_frame_texture("idle", 0)
	view.set_session(session, custom_art)
	await process_frame
	var custom_camera_before := layer.scale.x
	var custom_background_before := float(
		background_material.get_shader_parameter("camera_zoom")
	)
	var custom_seeker_scale_before := player_seeker.global_scale
	var custom_seeker_local_scale := player_seeker.scale.x
	var custom_previous_layout: Dictionary = view.call("_fighter_layout")
	view.call("_apply_side", switched, "player", true, false)
	var custom_refit := view.call(
		"_reframe_for_switch", switched, custom_previous_layout, true
	) as Tween
	var custom_background_moved := false
	var custom_seeker_scale_followed_camera := true
	while custom_refit != null and custom_refit.is_running():
		custom_seeker_scale_followed_camera = (
			custom_seeker_scale_followed_camera
			and is_equal_approx(
				player_seeker.global_scale.x,
				custom_seeker_local_scale * layer.scale.x
			)
		)
		custom_background_moved = (
			custom_background_moved
			or not is_equal_approx(
				float(background_material.get_shader_parameter("camera_zoom")),
				custom_background_before
			)
		)
		await process_frame
	var custom_camera_after := layer.scale.x
	var custom_background_after := float(
		background_material.get_shader_parameter("camera_zoom")
	)
	_check(
		custom_background_moved
		and custom_background_after < custom_background_before
		and custom_background_after / custom_background_before
			> custom_camera_after / custom_camera_before,
		"a custom Team background animates gentler parallax with the fighter Switch"
	)
	_check(
		custom_seeker_scale_followed_camera
		and is_equal_approx(
			player_seeker.global_scale.x / custom_seeker_scale_before.x,
			custom_camera_after / custom_camera_before
		),
		"custom-background Switch keeps player Seeker and Anima on one camera scale"
	)
	view.set_session(session, art_cache)
	await process_frame
	var art_camera_before := layer.scale.x
	var resized_loaded: Dictionary = loaded.duplicate(true)
	var resized_metrics: Dictionary = (
		resized_loaded.get("render_metrics", {}) as Dictionary
	).duplicate(true)
	resized_metrics["reference_height_px"] = (
		float(resized_metrics.get("reference_height_px", 200.0)) * 0.5
	)
	resized_loaded["render_metrics"] = resized_metrics
	var resized_art := art_cache.duplicate()
	resized_art[small_id] = resized_loaded
	view.set_session(session, resized_art)
	await process_frame
	_check(
		not is_equal_approx(layer.scale.x, art_camera_before),
		"new active-fighter art metrics invalidate preserved Team framing"
	)
	view.queue_free()
	await process_frame


func _check_shared_character_offset(
	view: Control,
	stage: Control,
	player_anchor: Node2D,
	opponent_anchor: Node2D,
	seeker: Node2D,
	profile_key: String,
	label: String
) -> void:
	var actors: Array[Node2D] = [player_anchor, opponent_anchor, seeker]
	var baseline := PackedFloat32Array()
	for actor: Node2D in actors:
		baseline.append(actor.global_position.y)
	var profiles := BattleBackgroundCalibration.canonical_profiles()
	profiles[profile_key]["fighter_offset_ratio_y"] = (
		float(profiles[profile_key]["fighter_offset_ratio_y"]) + 0.05
	)
	view.call("set_debug_background_profiles", profiles)
	var expected_shift := stage.size.y * 0.05
	var shifted_together := true
	for index: int in actors.size():
		shifted_together = shifted_together and absf(
			actors[index].global_position.y - baseline[index] - expected_shift
		) < 0.1
	_check(shifted_together, "%s character offset moves both Anima and Seeker together" % label)
	view.call("set_debug_background_profiles", BattleBackgroundCalibration.canonical_profiles())


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
	var profile: Dictionary = BattleBackgroundCalibration.DEFAULT_PROFILE
	if label.begins_with("Duel"):
		profile = BattleBackgroundCalibration.profile_for(&"duel", stage_rect.size)
	elif label.begins_with("Team"):
		profile = BattleBackgroundCalibration.profile_for(&"team", stage_rect.size)
	var profile_offset: Vector2 = profile["offset_ratio"]
	var expected_floor_delta := stage_rect.size.y * (
		profile_offset.y - float(profile["fighter_offset_ratio_y"])
	)
	_check(
		absf(source_ground_y - fighter_ground_y - expected_floor_delta) <= 1.0,
		(
			"%s preserves the calibrated painted-floor/character separation "
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


func _seeker_to_player_gap_ratio(
	stage: Control,
	seeker: AnimatedSprite2D,
	player: AnimatedSprite2D
) -> float:
	var body_value: Variant = player.call("body_viewport_rect")
	if typeof(body_value) != TYPE_RECT2:
		return INF
	var stage_width := maxf(1.0, stage.get_global_rect().size.x)
	return maxf(0.0, (body_value as Rect2).position.x - seeker.global_position.x) / stage_width


func _reference_screen_height(node: Node2D, loaded: Dictionary) -> float:
	var metrics_value: Variant = loaded.get("render_metrics", {})
	var metrics: Dictionary = (
		metrics_value if typeof(metrics_value) == TYPE_DICTIONARY else {}
	)
	return (
		maxf(1.0, float(metrics.get("reference_height_px", 300.0)))
		* absf(node.global_scale.y)
	)


func _check_regular_drakabyss_ratio(
	anima_anchor: Node2D,
	anima_loaded: Dictionary,
	seeker: Node2D,
	seeker_loaded: Dictionary,
	arena_name: String
) -> void:
	var seeker_cm := maxf(1.0, float(seeker_loaded.get("body_height_cm", 165.0)))
	var expected := pow(DRAKABYSS_HEIGHT_CM / seeker_cm, BattleScale.BODY_HEIGHT_CURVE)
	var actual := (
		_reference_screen_height(anima_anchor, anima_loaded)
		/ _reference_screen_height(seeker, seeker_loaded)
	)
	_check(
		absf(actual - expected) < 0.03,
		(
			"%s keeps the 203 cm Drakabyss ratio against the %.0f cm player Seeker "
			+ "after camera fit (actual=%.3f expected=%.3f)"
		) % [arena_name, seeker_cm, actual, expected]
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
		"anima_id": player_id, "name": "Drakabyss", "level": 16,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": DRAKABYSS_HEIGHT_CM,
	}
	var opponent_member := {
		"anima_id": opponent_id, "name": "Padronic", "level": 8,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": PADRONIC_HEIGHT_CM,
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
	var expedition_reveal_order: Array[String] = []
	opponent.visibility_changed.connect(func() -> void:
		if opponent.visible:
			expedition_reveal_order.append("opponent")
	)
	player.visibility_changed.connect(func() -> void:
		if player.visible:
			expedition_reveal_order.append("player")
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
		expedition_reveal_order == ["opponent", "player"]
		and player.visible
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
	var expedition_seeker := view.find_child("PlayerSeeker", true, false) as Node2D
	_check_regular_drakabyss_ratio(
		player_anchor, loaded, expedition_seeker, seeker_loaded, "Expedition"
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


func _test_boss_intro(
	host: SubViewport,
	loaded: Dictionary,
	seeker_loaded: Dictionary,
	player_seeker_loaded: Dictionary
) -> void:
	var packed := load("res://scenes/ui/expedition_view.tscn") as PackedScene
	var view := packed.instantiate()
	host.add_child(view)
	view.visible = true
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.position = Vector2.ZERO
	view.size = Vector2(host.size)
	await process_frame
	view.open_mode()
	var combat: Node = view.find_child("ExpeditionCombat", true, false)
	var legacy_player_seeker_loaded := player_seeker_loaded.duplicate(true)
	legacy_player_seeker_loaded.erase("body_height_cm")
	view.set_player_avatar(legacy_player_seeker_loaded)
	var player_id := "00000000-0000-4000-8000-000000000031"
	var opponent_id := "10000000-0000-4000-8000-000000000031"
	var player_member := {
		"anima_id": player_id, "name": "Drakabyss", "level": 16,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": DRAKABYSS_HEIGHT_CM,
	}
	var opponent_member := {
		"anima_id": opponent_id, "name": "Stridarc", "level": 16,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": STRIDARC_HEIGHT_CM,
	}
	var boss_seeker := {
		"display_name": "The Confectioner",
		"body_height_cm": 165,
		"portrait_pose": "profile",
		"dialogue": {
			"boss_intro": "You made it. Show me what your team has learned.",
			"rematch": "Again, then. Show me what changed.",
		},
	}
	var encounter := {
		"id": "boss-opening-first-attempt",
		"kind": "boss",
		"status": "active",
		"practice": true,
		"turn_number": 1,
		"version": 1,
		"zone_attempt": 1,
		"boss_seeker": boss_seeker,
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
		"id": "boss-opening-run",
		"status": "active",
		"practice": true,
		"zone": 3,
		"chapter_version_id": "future-chapter-version",
		"team_id": "",
		"available_node_ids": [],
		"pending_node": null,
		"boss_seeker": boss_seeker,
	}
	var background_image := Image.create(1024, 576, false, Image.FORMAT_RGBA8)
	background_image.fill(Color(0.15, 0.08, 0.22, 1.0))
	var art_cache := {
		player_id: loaded,
		opponent_id: loaded,
		"boss_seeker": seeker_loaded,
		"arena_background": ImageTexture.create_from_image(background_image),
	}
	LoadingScreen.show_screen("EXPEDITION_RESUMING", true)
	view.set_run(run_data, encounter, art_cache, true)
	await process_frame
	var player := view.find_child("TeamPlayerSprite", true, false) as AnimatedSprite2D
	var opponent := view.find_child("TeamOpponentSprite", true, false) as AnimatedSprite2D
	var player_seeker := view.find_child("PlayerSeeker", true, false) as AnimatedSprite2D
	var boss := view.find_child("BossSeeker", true, false) as AnimatedSprite2D
	var dialog := view.find_child("BossSeekerDialog", true, false) as BossSeekerDialog
	var chrome := view.find_child("TeamChrome", true, false) as Control
	var external_continue := view.find_child("BossSeekerContinue", true, false) as Button
	var attack := view.find_child("TeamAttackButton", true, false) as Button
	var switch_panel := view.find_child("TeamSwitchPanel", true, false) as Control
	var switch_overlay := view.find_child("SwitchOverlay", true, false) as Control
	var effectiveness := view.find_child("TeamEffectiveness", true, false) as Control
	var layer := view.find_child("FighterLayer", true, false) as Node2D
	var player_seeker_shadow := view.find_child("PlayerSeekerShadow", true, false) as Sprite2D
	var boss_shadow := layer.find_child("GroundShadow", false, false) as Sprite2D
	var loading_root := root.find_child("LoadingScreenRoot", true, false) as Control
	var legacy_player_seeker_px := (
		BattleScale.seeker_reference_height(legacy_player_seeker_loaded)
		* absf(player_seeker.global_scale.y)
	)
	var boss_seeker_px := (
		BattleScale.seeker_reference_height(seeker_loaded)
		* absf(boss.global_scale.y)
	)
	_check(
		absf(legacy_player_seeker_px / boss_seeker_px - 1.0) < 0.02,
		"Boss opening keeps the 165 cm fallback for legacy avatar sheets without height metadata"
	)
	view.set_player_avatar(player_seeker_loaded)
	await process_frame
	var player_seeker_px := (
		BattleScale.seeker_reference_height(player_seeker_loaded)
		* absf(player_seeker.global_scale.y)
	)
	boss_seeker_px = (
		BattleScale.seeker_reference_height(seeker_loaded)
		* absf(boss.global_scale.y)
	)
	_check(
		absf(player_seeker_px / boss_seeker_px - 180.0 / 165.0) < 0.02,
		"Boss opening scales the selected 180 cm Automaton proportionally against the 165 cm Boss"
	)
	var drakabyss_rect: Rect2 = player.call("body_viewport_rect")
	var drakabyss_px := drakabyss_rect.size.y
	_check(
		absf(drakabyss_px / player_seeker_px - DRAKABYSS_HEIGHT_CM / 180.0) < 0.03,
		(
			"Final Battle preserves Drakabyss 203:180 against the player Seeker "
			+ "after fitting both Seeker columns (actual=%.3f expected=%.3f)"
		) % [drakabyss_px / player_seeker_px, DRAKABYSS_HEIGHT_CM / 180.0]
	)
	_check(
		loading_root != null and loading_root.visible
		and player_seeker.visible and boss.visible
		and player_seeker_shadow.visible and boss_shadow.visible
		and not player.visible and not opponent.visible
		and not dialog.is_open()
		and is_zero_approx(chrome.modulate.a)
		and attack.disabled
		and attack.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and attack.focus_mode == Control.FOCUS_NONE,
		"fresh Boss encounter waits behind Loading on two grounded Seekers with no Anima or Chrome"
	)
	view.play_combat_intro()
	await create_timer(0.78).timeout
	view.handle_back()
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	host.push_input(accept, true)
	await process_frame
	_check(
		loading_root.visible and not dialog.is_open()
		and not player.visible and not opponent.visible and attack.disabled,
		"Boss opening and every dismiss input stay inert until Loading is fully hidden"
	)
	LoadingScreen.hide_screen()
	var hidden_deadline := Time.get_ticks_msec() + 3000
	while loading_root.visible and Time.get_ticks_msec() < hidden_deadline:
		await process_frame
	var loading_hidden_at := Time.get_ticks_msec()
	await create_timer(0.18).timeout
	view.handle_back()
	host.push_input(accept, true)
	var beat_tap := InputEventMouseButton.new()
	beat_tap.button_index = MOUSE_BUTTON_LEFT
	beat_tap.pressed = true
	beat_tap.position = Vector2(host.size) * 0.5
	host.push_input(beat_tap, true)
	attack.pressed.emit()
	await process_frame
	_check(
		not dialog.is_open() and not player.visible and not opponent.visible
		and attack.disabled,
		"tap, confirm, Back, and Battle commands stay inert during the clear-arena beat"
	)
	var dialog_deadline := loading_hidden_at + 2500
	while not dialog.is_open() and Time.get_ticks_msec() < dialog_deadline:
		await process_frame
	var dialog_opened_at := Time.get_ticks_msec()
	var dim := dialog.find_child("SeekerDim", true, false) as ColorRect
	var portrait := dialog.find_child("SeekerPortrait", true, false) as TextureRect
	if portrait == null:
		portrait = dialog.find_child("@TextureRect@*", true, false) as TextureRect
	var name_label := dialog.find_child("SeekerName", true, false) as Label
	var internal_continue := dialog.find_child("SeekerContinue", true, false) as Button
	var dialog_panel := dialog.find_child("SeekerPanel", true, false) as PanelContainer
	_check(
		not loading_root.visible and dialog.is_open()
		and dialog_opened_at - loading_hidden_at >= 600
		and not player.visible and not opponent.visible
		and not chrome.visible
		and dim != null and (not dim.visible or is_zero_approx(dim.color.a))
		and name_label != null and name_label.text == "The Confectioner"
		and internal_continue != null and not internal_continue.visible
		and external_continue != null and external_continue.visible
		and external_continue.text == tr("BATTLE_SEEKER_CONTINUE")
		and external_continue.focus_mode == Control.FOCUS_NONE
		and external_continue.get_global_rect().position.x <= 0.0
		and external_continue.get_global_rect().end.x >= host.size.x
		and external_continue.get_global_rect().end.y >= host.size.y
		and external_continue.custom_minimum_size.y >= 192.0
		and external_continue.get_global_rect().size.y
		>= external_continue.custom_minimum_size.y
		and portrait != null and portrait.visible
		and dialog_panel != null and effectiveness != null
		and is_equal_approx(dialog_panel.anchor_top, effectiveness.anchor_top)
		and is_equal_approx(dialog_panel.anchor_bottom, effectiveness.anchor_bottom)
		and is_equal_approx(dialog_panel.anchor_right, effectiveness.anchor_right)
		and absf(
			dialog_panel.get_global_rect().get_center().y
			- effectiveness.get_global_rect().get_center().y
		) < 1.0
		and dialog_panel.size.y <= 320.0,
		(
			"Boss dialogue replaces Chrome with one localized Continue action "
			+ "at the arena event-banner anchor"
		)
	)
	var reveal_order: Array[String] = []
	var boss_pose_at_reveal := [false]
	var player_pose_at_reveal := [false]
	var stable_reveals := [true]
	var cinematic_position := layer.position
	var cinematic_scale := layer.scale
	opponent.visibility_changed.connect(func() -> void:
		if opponent.visible:
			reveal_order.append("opponent")
			boss_pose_at_reveal[0] = boss.animation == "switch_command"
			stable_reveals[0] = stable_reveals[0] and layer.position.is_equal_approx(cinematic_position) and layer.scale.is_equal_approx(cinematic_scale)
	)
	player.visibility_changed.connect(func() -> void:
		if player.visible:
			reveal_order.append("player")
			player_pose_at_reveal[0] = player_seeker.animation == "switch_command"
			stable_reveals[0] = stable_reveals[0] and layer.position.is_equal_approx(cinematic_position) and layer.scale.is_equal_approx(cinematic_scale)
	)
	var dialog_tap := InputEventMouseButton.new()
	dialog_tap.button_index = MOUSE_BUTTON_LEFT
	dialog_tap.pressed = true
	dialog.call("_gui_input", dialog_tap)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	dialog.call("_gui_input", cancel)
	var accept_dialog := InputEventAction.new()
	accept_dialog.action = &"ui_accept"
	accept_dialog.pressed = true
	dialog.call("_gui_input", accept_dialog)
	_check(
		view.handle_back() and dialog.is_open() and not chrome.visible
		and external_continue.visible,
		"Boss dialogue ignores backdrop, ui_accept, ui_cancel, and Back until external Continue"
	)
	var continue_at := external_continue.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var continue_tap := InputEventMouseButton.new()
		continue_tap.button_index = MOUSE_BUTTON_LEFT
		continue_tap.pressed = pressed
		continue_tap.position = continue_at
		continue_tap.global_position = continue_at
		host.push_input(continue_tap, true)
		await process_frame
	await process_frame
	_check(
		chrome.visible and not dialog.is_open() and not external_continue.visible,
		"real practice Boss Continue tap dismisses the dialog and restores Chrome"
	)
	var saw_transition := false
	var transition_started_at := -1
	var settle_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < settle_deadline:
		if chrome.modulate.a > 0.01 and chrome.modulate.a < 0.99:
			if transition_started_at < 0:
				transition_started_at = Time.get_ticks_msec()
			saw_transition = true
		await process_frame
	var transition_elapsed := (
		Time.get_ticks_msec() - transition_started_at if transition_started_at >= 0 else 0
	)
	_check(
		reveal_order == ["opponent", "player"]
		and boss_pose_at_reveal[0] and player_pose_at_reveal[0]
		and stable_reveals[0] and saw_transition
		and transition_elapsed >= 220 and transition_elapsed <= 520
		and player.visible and opponent.visible
		and boss.animation == "intro_idle" and player_seeker.animation == "intro_idle"
		and is_equal_approx(chrome.modulate.a, 1.0)
		and not attack.disabled
		and attack.mouse_filter == Control.MOUSE_FILTER_STOP
		and attack.focus_mode == Control.FOCUS_ALL,
		"Boss then player Summon without camera snap before the 0.32-second Chrome transition unlocks input"
	)
	dialog.present("The Confectioner", "A mid-battle line.", portrait.texture)
	await process_frame
	_check(
		dialog.is_open() and not chrome.visible
		and not internal_continue.visible and external_continue.visible
		and not switch_overlay.visible,
		"mid-battle Boss dialogue hides HP, actions, and Switch behind one external action"
	)
	external_continue.pressed.emit()
	await process_frame
	_check(
		not dialog.is_open() and chrome.visible and not attack.disabled
		and attack.mouse_filter == Control.MOUSE_FILTER_STOP,
		"dismissing a mid-battle Boss line restores canonical action availability"
	)
	switch_panel.visible = true
	switch_overlay.visible = true
	dialog.present("The Confectioner", "Keep the current Switch choice.", portrait.texture)
	await process_frame
	_check(
		switch_panel.visible and not switch_overlay.visible,
		"Boss dialogue hides an open Switch picker without mutating its content state"
	)
	external_continue.pressed.emit()
	await process_frame
	_check(
		switch_panel.visible and switch_overlay.visible,
		"dismissing Boss dialogue restores the previously open Switch picker"
	)
	chrome.visible = false
	dialog.present("The Confectioner", "Keep hidden Chrome hidden.", portrait.texture)
	await process_frame
	external_continue.pressed.emit()
	await process_frame
	_check(
		not dialog.is_open() and not chrome.visible,
		"dismissing Boss dialogue restores a previously hidden Chrome state"
	)
	chrome.visible = true
	combat.call("_hide_switch_overlay")
	combat.call("_update_arena_actions")
	var settled_layer_position := layer.position
	var settled_layer_scale := layer.scale
	var settled_boss_position := boss.position
	var settled_player_seeker_position := player_seeker.position
	var settled_boss_scale := boss.global_scale.x
	var settled_player_seeker_scale := player_seeker.global_scale.x
	var hp_refresh: Dictionary = encounter.duplicate(true)
	hp_refresh["state"]["player"]["roster"][0]["hp"] = 37
	view.set_run(run_data, hp_refresh, art_cache)
	await process_frame
	_check(
		layer.position.is_equal_approx(settled_layer_position)
		and layer.scale.is_equal_approx(settled_layer_scale)
		and boss.position.is_equal_approx(settled_boss_position)
		and player_seeker.position.is_equal_approx(settled_player_seeker_position)
		and is_equal_approx(boss.global_scale.x, settled_boss_scale)
		and is_equal_approx(player_seeker.global_scale.x, settled_player_seeker_scale),
		"Boss HP-only refresh preserves framing and both Seeker screen sizes"
	)
	LoadingScreen.hide_screen()
	view.queue_free()
	await process_frame


func _test_boss_replay_and_cancellation(
	host: SubViewport,
	loaded: Dictionary,
	seeker_loaded: Dictionary
) -> void:
	var packed := load("res://scenes/ui/expedition_view.tscn") as PackedScene
	var view := packed.instantiate()
	host.add_child(view)
	view.visible = true
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.position = Vector2.ZERO
	view.size = Vector2(host.size)
	await process_frame
	view.open_mode()
	view.set_player_avatar(seeker_loaded)
	var player_id := "00000000-0000-4000-8000-000000000041"
	var opponent_id := "10000000-0000-4000-8000-000000000041"
	var boss_seeker := {
		"display_name": "Future Boss",
		"body_height_cm": 165,
		"portrait_pose": "profile",
		"dialogue": {
			"boss_intro": "A first meeting.",
			"rematch": "A rematch line.",
		},
	}
	var member := {
		"name": "Fighter", "level": 8,
		"hp": 50, "max_hp": 50, "momentum": 3, "momentum_max": 3,
		"body_height_cm": 90,
	}
	var player_member: Dictionary = member.duplicate(true)
	player_member["anima_id"] = player_id
	var opponent_member: Dictionary = member.duplicate(true)
	opponent_member["anima_id"] = opponent_id
	var encounter := {
		"id": "boss-resume",
		"kind": "boss",
		"status": "active",
		"turn_number": 1,
		"version": 1,
		"zone_attempt": 1,
		"boss_seeker": boss_seeker,
		"player_snapshot": [{"anima_id": player_id}],
		"opponent_snapshot": [{"anima_id": opponent_id}],
		"state": {
			"status": "active", "turn": 1,
			"player": {"active_slot": 0, "forced_switch": false, "roster": [player_member]},
			"opponent": {"active_slot": 0, "forced_switch": false, "roster": [opponent_member]},
		},
	}
	var run_data := {
		"id": "boss-replay-run",
		"status": "active",
		"zone": 3,
		"chapter_version_id": "another-future-chapter",
		"boss_seeker": boss_seeker,
	}
	var art_cache := {
		player_id: loaded,
		opponent_id: loaded,
		"boss_seeker": seeker_loaded,
	}
	view.set_run(run_data, encounter, art_cache)
	await process_frame
	var player := view.find_child("TeamPlayerSprite", true, false) as AnimatedSprite2D
	var opponent := view.find_child("TeamOpponentSprite", true, false) as AnimatedSprite2D
	var dialog := view.find_child("BossSeekerDialog", true, false) as BossSeekerDialog
	var external_continue := view.find_child("BossSeekerContinue", true, false) as Button
	var line := dialog.find_child("SeekerLine", true, false) as Label
	var chrome := view.find_child("TeamChrome", true, false) as Control
	var attack := view.find_child("TeamAttackButton", true, false) as Button
	var player_portal := player.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect
	var opponent_portal := opponent.get_parent().find_child("SummonPortal", false, false) as IncubatorEffect
	var boss_actor := view.find_child("BossSeeker", true, false) as SeekerPresenter
	var player_actor := view.find_child("PlayerSeeker", true, false) as SeekerPresenter
	var layer := view.find_child("FighterLayer", true, false) as Node2D
	var boss_shadow := layer.find_child("GroundShadow", false, false) as Sprite2D
	var player_seeker_shadow := view.find_child("PlayerSeekerShadow", true, false) as Sprite2D
	var loading := view.find_child("ExpeditionLoading", true, false) as Control
	var global_loading := root.find_child("LoadingScreenRoot", true, false) as Control
	var portrait := dialog.find_child("SeekerPortrait", true, false) as TextureRect
	if portrait == null:
		portrait = dialog.find_child("@TextureRect@*", true, false) as TextureRect
	await create_timer(0.78).timeout
	_check(
		player.visible and opponent.visible and not dialog.is_open()
		and is_equal_approx(chrome.modulate.a, 1.0) and not attack.disabled
		and not player_portal.is_active() and not opponent_portal.is_active(),
		"Continue and authoritative resume converge directly on the ready Boss arena without replay"
	)
	var rematch: Dictionary = encounter.duplicate(true)
	rematch["id"] = "boss-rematch"
	rematch["zone_attempt"] = 2
	view.set_run(run_data, rematch, art_cache, true)
	view.play_combat_intro()
	var rematch_deadline := Time.get_ticks_msec() + 2500
	while not dialog.is_open() and Time.get_ticks_msec() < rematch_deadline:
		await process_frame
	_check(
		dialog.is_open() and line.text == "A rematch line."
		and not player.visible and not opponent.visible and attack.disabled,
		"a retry starts the full choreography with rematch copy instead of replaying boss_intro"
	)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(host.size) * 0.5
	host.push_input(tap, true)
	await process_frame
	_check(
		dialog.is_open() and external_continue.visible,
		"the in-combat rematch dialog also ignores arena backdrop taps"
	)
	var normal_continue_at := external_continue.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var normal_continue_tap := InputEventMouseButton.new()
		normal_continue_tap.button_index = MOUSE_BUTTON_LEFT
		normal_continue_tap.pressed = pressed
		normal_continue_tap.position = normal_continue_at
		normal_continue_tap.global_position = normal_continue_at
		host.push_input(normal_continue_tap, true)
		await process_frame
	var rematch_settle_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < rematch_settle_deadline:
		await process_frame
	_check(
		player.visible and opponent.visible and not dialog.is_open() and not attack.disabled,
		"tap dismissal lets the unskippable rematch Summons finish and unlock the arena"
	)
	var cancelled: Dictionary = encounter.duplicate(true)
	cancelled["id"] = "boss-cancelled-by-view"
	view.set_run(run_data, cancelled, art_cache, true)
	view.play_combat_intro()
	await create_timer(0.18).timeout
	view.close_mode(true)
	await create_timer(0.72).timeout
	_check(
		not view.visible and not dialog.is_open()
		and not player_portal.is_active() and not opponent_portal.is_active(),
		"leaving the Expedition view cancels the Boss beat before hidden dialogue or portals can start"
	)
	view.open_mode()
	var refreshed: Dictionary = encounter.duplicate(true)
	refreshed["id"] = "boss-authoritative-refresh"
	view.set_run(run_data, refreshed, art_cache, true)
	view.play_combat_intro()
	var refresh_dialog_deadline := Time.get_ticks_msec() + 2500
	while not dialog.is_open() and Time.get_ticks_msec() < refresh_dialog_deadline:
		await process_frame
	view.set_run(run_data, refreshed, art_cache)
	await create_timer(1.0).timeout
	_check(
		not dialog.is_open() and player.visible and opponent.visible
		and is_equal_approx(chrome.modulate.a, 1.0) and not attack.disabled
		and not player_portal.is_active() and not opponent_portal.is_active(),
		"same-session authoritative refresh cancels the cinematic and stale callbacks cannot re-hide or unlock it"
	)
	var backgrounded: Dictionary = encounter.duplicate(true)
	backgrounded["id"] = "boss-background-continuity"
	view.set_run(run_data, backgrounded, art_cache, true)
	view.play_combat_intro()
	await create_timer(0.18).timeout
	view.propagate_notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	await create_timer(0.24).timeout
	view.propagate_notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	var resumed_dialog_deadline := Time.get_ticks_msec() + 2500
	while not dialog.is_open() and Time.get_ticks_msec() < resumed_dialog_deadline:
		await process_frame
	_check(
		dialog.is_open() and line.text == "A first meeting."
		and not player.visible and not opponent.visible and attack.disabled,
		"background then foreground on the same view resumes the active Boss opening phase"
	)
	external_continue.pressed.emit()
	var resumed_settle_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < resumed_settle_deadline:
		await process_frame
	var text_only: Dictionary = encounter.duplicate(true)
	text_only["id"] = "boss-text-only-fallback"
	var text_only_seeker: Dictionary = boss_seeker.duplicate(true)
	text_only_seeker["dialogue"] = {"boss_intro": "Text survives missing art."}
	text_only["boss_seeker"] = text_only_seeker
	view.set_player_avatar({})
	view.set_run(
		run_data, text_only,
		{player_id: loaded, opponent_id: loaded, "boss_seeker": {}}, true
	)
	view.play_combat_intro()
	var text_deadline := Time.get_ticks_msec() + 2500
	while not dialog.is_open() and Time.get_ticks_msec() < text_deadline:
		await process_frame
	_check(
		dialog.is_open() and line.text == "Text survives missing art."
		and portrait != null and not portrait.visible
		and not boss_actor.has_sheet() and not player_actor.has_sheet()
		and not boss_shadow.visible and not player_seeker_shadow.visible,
		"missing Seeker sheets omit both cosmetics and portrait while Boss dialogue remains usable"
	)
	external_continue.pressed.emit()
	var text_settle_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < text_settle_deadline:
		await process_frame
	var no_line: Dictionary = text_only.duplicate(true)
	no_line["id"] = "boss-missing-line-fallback"
	var silent_seeker: Dictionary = text_only_seeker.duplicate(true)
	silent_seeker["dialogue"] = {}
	no_line["boss_seeker"] = silent_seeker
	view.set_run(
		run_data, no_line,
		{player_id: loaded, opponent_id: loaded, "boss_seeker": {}}, true
	)
	view.play_combat_intro()
	var silent_deadline := Time.get_ticks_msec() + 10000
	while attack.disabled and Time.get_ticks_msec() < silent_deadline:
		await process_frame
	_check(
		not dialog.is_open() and player.visible and opponent.visible and not attack.disabled,
		"a missing Boss opening line skips dialogue without blocking Summons or Battle input"
	)
	var account_change: Dictionary = text_only.duplicate(true)
	account_change["id"] = "boss-cancelled-by-account-context"
	view.set_run(
		run_data, account_change,
		{player_id: loaded, opponent_id: loaded, "boss_seeker": {}}, true
	)
	view.play_combat_intro()
	var account_dialog_deadline := Time.get_ticks_msec() + 2500
	while not dialog.is_open() and Time.get_ticks_msec() < account_dialog_deadline:
		await process_frame
	view.set_loading()
	await create_timer(0.6).timeout
	_check(
		loading.visible and not dialog.is_open()
		and not player_portal.is_active() and not opponent_portal.is_active(),
		"account-context loading cancels Boss dialogue and portal choreography before replacing the arena"
	)
	LoadingScreen.show_screen("EXPEDITION_RESUMING", true)
	var waiting: Dictionary = encounter.duplicate(true)
	waiting["id"] = "boss-waiting-behind-loading"
	view.set_run(run_data, waiting, art_cache, true)
	view.play_combat_intro()
	await create_timer(0.1).timeout
	var replacement: Dictionary = encounter.duplicate(true)
	replacement["id"] = "boss-replaced-behind-loading"
	view.set_run(run_data, replacement, art_cache, true)
	LoadingScreen.hide_screen()
	var replacement_hidden_deadline := Time.get_ticks_msec() + 3000
	while global_loading.visible and Time.get_ticks_msec() < replacement_hidden_deadline:
		await process_frame
	await create_timer(0.85).timeout
	_check(
		not dialog.is_open() and not player.visible and not opponent.visible and attack.disabled,
		"a stale Loading waiter cannot consume the replacement session's pending Boss opening"
	)
	view.set_loading()
	LoadingScreen.hide_screen()
	view.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
