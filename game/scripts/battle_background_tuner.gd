class_name BattleBackgroundTuner
extends Control

signal profiles_changed(profiles: Dictionary)
signal preview_requested(
	mode: StringName, framing: StringName, fighter_preset: StringName, daylight_blend: float
)
signal replay_requested(
	mode: StringName, fighter_preset: StringName, daylight_blend: float
)

const FLAG := "--battle-background-tuner"
const PRESET_PATH := "user://battle_background_tuning.json"
const PORTRAIT_SIZE := Vector2i(720, 1602)
const LANDSCAPE_SIZE := Vector2i(1602, 720)
const PORTRAIT_TEXTURE_SIZE := Vector2(720.0, 1602.0)
const LANDSCAPE_TEXTURE_SIZE := Vector2(1600.0, 900.0)
const TEAM_BASE_ZOOMS := [1.0, 1.04, 1.08]
const DUEL_BASE_ZOOMS := [1.0]
const CALIBRATION := preload("res://scripts/battle_background_calibration.gd")
const BATTLE_IMPACT := preload("res://scripts/battle_impact.gd")

@onready var _drag_surface: Control = %DragSurface
@onready var _panel: PanelContainer = %TunerPanel
@onready var _mode: OptionButton = %Mode
@onready var _orientation: OptionButton = %Orientation
@onready var _lighting: OptionButton = %Lighting
@onready var _framing: OptionButton = %Framing
@onready var _fighter: OptionButton = %FighterPreset
@onready var _offset_x: SpinBox = %OffsetX
@onready var _offset_y: SpinBox = %OffsetY
@onready var _zoom: SpinBox = %Zoom
@onready var _pivot_y: SpinBox = %PivotY
@onready var _source_foot_y: SpinBox = %SourceFootY
@onready var _fighter_offset_slider: HSlider = %FighterOffsetYSlider
@onready var _fighter_offset_y: SpinBox = %FighterOffsetY
@onready var _status: Label = %Status
@onready var _replay: Button = %Replay
@onready var _save: Button = %Save
@onready var _copy: Button = %Copy
@onready var _reset_current: Button = %ResetCurrent
@onready var _reset_all: Button = %ResetAll
@onready var _hide: Button = %Hide

var _profiles: Dictionary = {}
var _syncing_fields := false
var _dragging := false
var _guides_visible := true


static func should_start(arguments: Array, debug_build: bool) -> bool:
	if not debug_build:
		return false
	for argument: Variant in arguments:
		var value := str(argument)
		if value == FLAG or value.begins_with("%s=" % FLAG):
			return true
	return false


func _ready() -> void:
	if not (OS.has_feature("debug") or OS.is_debug_build()):
		queue_free()
		return
	_populate_options()
	_apply_startup_selection()
	_configure_fields()
	_connect_controls()
	_profiles = _load_profiles()
	set_process_unhandled_key_input(true)


func start() -> void:
	_resize_window()
	_sync_fields()
	_apply_profiles()
	_request_preview()


func _populate_options() -> void:
	_add_options(_mode, [
		{"label": "Duel", "value": &"duel"},
		{"label": "Team", "value": &"team"},
	])
	_add_options(_orientation, [
		{"label": "Portrait 720×1602", "value": &"portrait"},
		{"label": "Landscape 1602×720", "value": &"landscape"},
	])
	_add_options(_lighting, [
		{"label": "Night", "value": 0.0},
		{"label": "Blend 50%", "value": 0.5},
		{"label": "Day", "value": 1.0},
	])
	_add_options(_framing, [
		{"label": "Opening", "value": &"opening"},
		{"label": "Gameplay", "value": &"gameplay"},
	])
	_add_options(_fighter, [
		{"label": "Small", "value": &"small"},
		{"label": "Normal", "value": &"normal"},
		{"label": "Giant", "value": &"giant"},
	])
	_lighting.select(2)
	_framing.select(1)
	_fighter.select(1)


func _add_options(button: OptionButton, options: Array) -> void:
	button.clear()
	for option: Dictionary in options:
		button.add_item(str(option["label"]))
		button.set_item_metadata(button.item_count - 1, option["value"])


func _apply_startup_selection() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("%s=" % FLAG):
			continue
		var profile := argument.trim_prefix("%s=" % FLAG)
		_mode.select(1 if profile.begins_with("team-") else 0)
		_orientation.select(1 if profile.ends_with("-landscape") else 0)
		return


func _configure_fields() -> void:
	for spin: SpinBox in [_offset_x, _offset_y]:
		spin.min_value = -4000.0
		spin.max_value = 4000.0
		spin.step = 0.1
		spin.suffix = " px"
	_zoom.min_value = 0.25
	_zoom.max_value = 3.0
	_zoom.step = 0.001
	_pivot_y.min_value = 0.0
	_pivot_y.max_value = 1.0
	_pivot_y.step = 0.001
	_source_foot_y.min_value = 0.0
	_source_foot_y.max_value = 1.0
	_source_foot_y.step = 0.001
	for fighter_control: Range in [_fighter_offset_slider, _fighter_offset_y]:
		fighter_control.min_value = -400.0
		fighter_control.max_value = 400.0
	_fighter_offset_slider.step = 1.0
	_fighter_offset_y.step = 0.1
	_fighter_offset_y.suffix = " px"


func _connect_controls() -> void:
	_mode.item_selected.connect(_on_preview_option_selected)
	_orientation.item_selected.connect(_on_orientation_selected)
	_lighting.item_selected.connect(_on_preview_option_selected)
	_framing.item_selected.connect(_on_preview_option_selected)
	_fighter.item_selected.connect(_on_preview_option_selected)
	for spin: SpinBox in [_offset_x, _offset_y, _zoom, _pivot_y, _source_foot_y]:
		spin.value_changed.connect(_on_field_changed)
	_fighter_offset_slider.value_changed.connect(_on_fighter_offset_changed)
	_fighter_offset_y.value_changed.connect(_on_fighter_offset_changed)
	_drag_surface.gui_input.connect(_on_drag_surface_input)
	_replay.pressed.connect(_on_replay_pressed)
	_save.pressed.connect(_save_profiles)
	_copy.pressed.connect(_copy_profiles)
	_reset_current.pressed.connect(_reset_current_profile)
	_reset_all.pressed.connect(_reset_all_profiles)
	_hide.pressed.connect(_toggle_clean_preview)


func _on_preview_option_selected(_index: int) -> void:
	_sync_fields()
	_lighting.disabled = _mode_value() == &"team"
	_request_preview()
	queue_redraw()


func _on_orientation_selected(_index: int) -> void:
	_resize_window()
	await get_tree().process_frame
	_sync_fields()
	_apply_profiles()
	_request_preview()


func _on_field_changed(_value: float) -> void:
	if _syncing_fields:
		return
	var stage_size := _stage_size()
	var profile := _current_profile()
	profile["offset_ratio"] = Vector2(
		_offset_x.value / maxf(1.0, stage_size.x),
		_offset_y.value / maxf(1.0, stage_size.y)
	)
	profile["zoom_multiplier"] = _zoom.value
	profile["pivot_y"] = _pivot_y.value
	profile["source_foot_y"] = _source_foot_y.value
	profile["fighter_offset_ratio_y"] = _fighter_offset_y.value / maxf(1.0, stage_size.y)
	_profiles[_profile_key()] = CALIBRATION.normalize_profile(profile)
	_apply_profiles()


func _on_fighter_offset_changed(value: float) -> void:
	if _syncing_fields:
		return
	_fighter_offset_slider.set_value_no_signal(value)
	_fighter_offset_y.set_value_no_signal(value)
	_on_field_changed(value)


func _on_drag_surface_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			_drag_surface.accept_event()
		elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			var step := 0.001 if button.alt_pressed else (0.05 if button.shift_pressed else 0.01)
			_zoom.value += direction * step * maxf(1.0, button.factor)
			_drag_surface.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_nudge(motion.relative)
		_drag_surface.accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_H:
		_toggle_clean_preview()
		get_viewport().set_input_as_handled()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and _panel.is_ancestor_of(focus):
		return
	var direction := Vector2.ZERO
	match key.keycode:
		KEY_LEFT:
			direction.x = -1.0
		KEY_RIGHT:
			direction.x = 1.0
		KEY_UP:
			direction.y = -1.0
		KEY_DOWN:
			direction.y = 1.0
		_:
			return
	var step := 0.1 if key.alt_pressed else (10.0 if key.shift_pressed else 1.0)
	_nudge(direction * step)
	get_viewport().set_input_as_handled()


func _nudge(delta_pixels: Vector2) -> void:
	_offset_x.value += delta_pixels.x
	_offset_y.value += delta_pixels.y


func _on_replay_pressed() -> void:
	replay_requested.emit(_mode_value(), _fighter_value(), _daylight_value())


func _request_preview() -> void:
	preview_requested.emit(
		_mode_value(), _framing_value(), _fighter_value(), _daylight_value()
	)


func _apply_profiles() -> void:
	var safe := _all_profiles_safe()
	_save.disabled = not safe
	_copy.disabled = not safe
	_status.text = (
		"BACKGROUND SAFE · character offset needs visual review"
		if safe else "BACKGROUND UNSAFE · background does not cover the impact guard"
	)
	profiles_changed.emit(_profiles.duplicate(true))
	queue_redraw()


func _all_profiles_safe() -> bool:
	for key: String in CALIBRATION.PROFILES:
		var portrait := key.ends_with("portrait")
		var stage_size := Vector2(PORTRAIT_SIZE if portrait else LANDSCAPE_SIZE)
		var texture_size := PORTRAIT_TEXTURE_SIZE if portrait else LANDSCAPE_TEXTURE_SIZE
		var base_zooms: Array = DUEL_BASE_ZOOMS if key.begins_with("duel") else TEAM_BASE_ZOOMS
		var guard := float(BATTLE_IMPACT.background_overscan_px(stage_size.x))
		if not CALIBRATION.profile_is_safe(
			stage_size, texture_size, guard, base_zooms, _profiles[key]
		):
			return false
	return true


func _save_profiles() -> void:
	if not _all_profiles_safe():
		return
	var file := FileAccess.open(PRESET_PATH, FileAccess.WRITE)
	if file == null:
		_status.text = "Could not write %s" % PRESET_PATH
		return
	file.store_string(CALIBRATION.profiles_to_json(_profiles))
	_status.text = "Saved %s" % PRESET_PATH


func _copy_profiles() -> void:
	if not _all_profiles_safe():
		return
	var snippet := CALIBRATION.gdscript_snippet(_profiles)
	DisplayServer.clipboard_set(snippet)
	print("Battle background calibration:\n%s" % snippet)
	_status.text = "Copied complete four-profile GDScript dictionary"


func _load_profiles() -> Dictionary:
	if not FileAccess.file_exists(PRESET_PATH):
		return CALIBRATION.canonical_profiles()
	return CALIBRATION.profiles_from_json(FileAccess.get_file_as_string(PRESET_PATH))


func _reset_current_profile() -> void:
	_profiles[_profile_key()] = CALIBRATION.canonical_profiles()[_profile_key()].duplicate(true)
	_sync_fields()
	_apply_profiles()


func _reset_all_profiles() -> void:
	_profiles = CALIBRATION.canonical_profiles()
	_sync_fields()
	_apply_profiles()


func _toggle_clean_preview() -> void:
	_guides_visible = not _guides_visible
	_panel.visible = _guides_visible
	_drag_surface.visible = _guides_visible
	queue_redraw()


func _sync_fields() -> void:
	_syncing_fields = true
	var stage_size := _stage_size()
	var profile := _current_profile()
	var offset: Vector2 = profile["offset_ratio"]
	_offset_x.value = offset.x * stage_size.x
	_offset_y.value = offset.y * stage_size.y
	_zoom.value = float(profile["zoom_multiplier"])
	_pivot_y.value = float(profile["pivot_y"])
	_source_foot_y.value = float(profile["source_foot_y"])
	var fighter_offset := CALIBRATION.fighter_offset_y(stage_size, profile)
	_fighter_offset_slider.value = fighter_offset
	_fighter_offset_y.value = fighter_offset
	_syncing_fields = false
	_lighting.disabled = _mode_value() == &"team"


func _resize_window() -> void:
	# canvas_items + expand keeps the 1602-high design canvas in landscape, so
	# developer controls need a matching local scale to remain readable.
	_panel.scale = Vector2.ONE if _is_portrait() else Vector2(2.0, 2.0)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_size(PORTRAIT_SIZE if _is_portrait() else LANDSCAPE_SIZE)


func _profile_key() -> String:
	return CALIBRATION.profile_key(_mode_value(), _stage_size())


func _current_profile() -> Dictionary:
	return CALIBRATION.profile_for(_mode_value(), _stage_size(), _profiles)


func _stage_size() -> Vector2:
	return Vector2(PORTRAIT_SIZE if _is_portrait() else LANDSCAPE_SIZE)


func _is_portrait() -> bool:
	return StringName(_orientation.get_selected_metadata()) == &"portrait"


func _mode_value() -> StringName:
	return StringName(_mode.get_selected_metadata())


func _framing_value() -> StringName:
	return StringName(_framing.get_selected_metadata())


func _fighter_value() -> StringName:
	return StringName(_fighter.get_selected_metadata())


func _daylight_value() -> float:
	return float(_lighting.get_selected_metadata()) if _mode_value() == &"duel" else 0.0


func _draw() -> void:
	if not _guides_visible or _profiles.is_empty():
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var guide_scale := Vector2(
		viewport_size.x / maxf(1.0, _stage_size().x),
		viewport_size.y / maxf(1.0, _stage_size().y)
	)
	var profile := _current_profile()
	var offset: Vector2 = profile["offset_ratio"] * _stage_size() * guide_scale
	var ground_y := viewport_size.y * BattleScale.GROUND_Y_RATIO
	var fighter_y := (
		ground_y + CALIBRATION.fighter_offset_y(_stage_size(), profile) * guide_scale.y
	)
	var source_y := ground_y + offset.y
	var safe_pad := viewport_size * 0.05
	draw_rect(
		Rect2(safe_pad, viewport_size - safe_pad * 2.0),
		Color(0.2, 0.95, 0.7, 0.9),
		false,
		2.0
	)
	draw_line(Vector2(0.0, fighter_y), Vector2(viewport_size.x, fighter_y), Color.CYAN, 2.0)
	draw_line(Vector2(0.0, source_y), Vector2(viewport_size.x, source_y), Color.GOLD, 2.0)
	var offset_center_x := viewport_size.x * 0.5 + offset.x
	draw_line(
		Vector2(offset_center_x, 0.0),
		Vector2(offset_center_x, viewport_size.y),
		Color(0.75, 0.45, 1.0, 0.85),
		2.0
	)
