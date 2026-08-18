class_name UiJuice
extends RefCounted

## Shared micro-interactions for every screen. Controls keep their own tween in
## metadata, so rapid taps replace the previous motion instead of stacking scale
## writers and leaving a button permanently squashed.

const META_INSTALLED := &"_scanima_juice_installed"
const META_TWEEN := &"_scanima_juice_tween"
const META_METER_TWEEN := &"_scanima_meter_tween"
const META_SHEET_POSITION := &"_scanima_sheet_position"
const PLAYER_NAME := &"UiClickPlayer"
const CUE_TAP := &"tap"
const CUE_CARE := &"care"
const CUE_CONFIRM := &"confirm"
const CUE_BACK := &"back"
const VOLUME_DB := -18.0

const _STREAM_PATHS := {
	"tap": "res://assets/audio/ui/ui_tap.ogg",
	"care": "res://assets/audio/ui/ui_care.ogg",
	"confirm": "res://assets/audio/ui/ui_confirm.ogg",
	"back": "res://assets/audio/ui/ui_back.ogg",
}

## `ui_confirm` measures -11,3 dB RMS against -21,2 dB on `ui_back`, so without
## a trim confirming anything is nearly ten times the energy of dismissing it.
const CUE_TRIM_DB := {
	"tap": -1.1,
	"care": 0.0,
	"confirm": -8.7,
	"back": 0.0,
}

static var _streams: Dictionary = {}


static func install_buttons(root: Node) -> void:
	_install_recursive(root)


static func install_button(button: Button) -> void:
	if button.has_meta(META_INSTALLED):
		return
	button.set_meta(META_INSTALLED, true)
	button.resized.connect(_center_pivot.bind(button))
	button.button_down.connect(_button_down.bind(button))
	button.button_up.connect(_button_up.bind(button))
	button.mouse_entered.connect(_button_hover.bind(button, true))
	button.mouse_exited.connect(_button_hover.bind(button, false))
	button.focus_entered.connect(_button_hover.bind(button, true))
	button.focus_exited.connect(_button_hover.bind(button, false))
	_center_pivot(button)


static func play_button(button: Button) -> void:
	_play_click(button)


static func button_cue(button: Button) -> StringName:
	var variation := button.theme_type_variation
	if variation == &"PrimaryButton":
		return CUE_CONFIRM
	if variation.begins_with("Care"):
		return CUE_CARE
	var node_name := String(button.name)
	if (
		variation == &"DangerButton"
		or node_name.contains("Cancel")
		or node_name.contains("Back")
		or node_name.contains("Dismiss")
		or node_name.contains("Leave")
	):
		return CUE_BACK
	return CUE_TAP


static func reveal(control: Control, delay: float = 0.0) -> void:
	_kill_tween(control)
	control.visible = true
	control.pivot_offset = control.size * 0.5
	control.modulate = Color(1.0, 1.0, 1.0, 0.0)
	control.scale = Vector2(0.94, 0.94)
	var tween := control.create_tween().set_parallel(true)
	tween.set_meta("owner_control", control)
	tween.tween_property(control, "modulate", Color.WHITE, 0.24) \
		.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "scale", Vector2.ONE, 0.38) \
		.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	control.set_meta(META_TWEEN, tween)


static func pop(control: Control, strength: float = 1.045) -> void:
	if not is_instance_valid(control) or not control.visible:
		return
	_kill_tween(control)
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.96, 0.96)
	control.modulate = Color(1.1, 1.1, 1.1, 1.0)
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "scale", Vector2(strength, strength), 0.10) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "modulate", Color.WHITE, 0.22)
	tween.chain().tween_property(control, "scale", Vector2.ONE, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	control.set_meta(META_TWEEN, tween)


static func show_overlay(overlay: Control, panel: Control) -> void:
	if overlay.visible and overlay.modulate.a >= 0.99:
		return
	_kill_tween(overlay)
	overlay.visible = true
	overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel.pivot_offset = panel.size * Vector2(0.5, 0.72)
	panel.scale = Vector2(0.88, 0.88)
	panel.modulate = Color(0.82, 0.92, 1.08, 0.0)
	var tween := overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate", Color.WHITE, 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.38) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.24) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	overlay.set_meta(META_TWEEN, tween)
	await tween.finished


static func hide_overlay(overlay: Control, panel: Control) -> void:
	if not overlay.visible:
		return
	_kill_tween(overlay)
	panel.pivot_offset = panel.size * Vector2(0.5, 0.72)
	var tween := overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.18) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "scale", Vector2(0.92, 0.92), 0.18) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate:a", 0.0, 0.14)
	overlay.set_meta(META_TWEEN, tween)
	await tween.finished
	if is_instance_valid(overlay):
		overlay.visible = false
		overlay.modulate = Color.WHITE
	if is_instance_valid(panel):
		panel.scale = Vector2.ONE
		panel.modulate = Color.WHITE


# ponytail: hidden full-rect hosts can still report size 0 before their first
# layout. Rest Y uses parent then viewport; never leave a visible 0-size overlay
# at (0,0) — that pins the sheet to the top-left on Android. Plafon: a nested
# sheet that is not full-rect still needs its host laid out.
static func sheet_host_size(overlay: Control, panel: Control) -> Vector2:
	var host := panel.get_parent() as Control
	var size := host.size if host != null else overlay.size
	if size.x < 1.0 or size.y < 1.0:
		size = overlay.size
	if (size.x < 1.0 or size.y < 1.0) and overlay.get_parent() is Control:
		size = (overlay.get_parent() as Control).size
	if (size.x < 1.0 or size.y < 1.0) and overlay.is_inside_tree():
		size = overlay.get_viewport_rect().size
	return size


static func sheet_rest_position(overlay: Control, panel: Control) -> Vector2:
	var height := maxf(panel.get_combined_minimum_size().y, 1.0)
	return Vector2(0.0, sheet_host_size(overlay, panel).y - height)


static func show_bottom_sheet(overlay: Control, panel: Control) -> void:
	_kill_tween(overlay)
	overlay.visible = true
	var height := maxf(panel.get_combined_minimum_size().y, 1.0)
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = -height
	panel.offset_bottom = 0.0
	var target := sheet_rest_position(overlay, panel)
	panel.set_meta(META_SHEET_POSITION, target)
	overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel.position = target + Vector2(0.0, height + 24.0)
	panel.modulate = Color(0.84, 0.94, 1.08, 1.0)
	var tween := overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate", Color.WHITE, 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "position", target, 0.38) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.26)
	overlay.set_meta(META_TWEEN, tween)


static func hide_bottom_sheet(overlay: Control, panel: Control) -> void:
	if not overlay.visible:
		return
	_kill_tween(overlay)
	var height := maxf(panel.get_combined_minimum_size().y, 1.0)
	var target: Vector2 = panel.get_meta(META_SHEET_POSITION, sheet_rest_position(overlay, panel))
	var tween := overlay.create_tween().set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.18) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "position", target + Vector2(0.0, height + 24.0), 0.24) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	overlay.set_meta(META_TWEEN, tween)
	await tween.finished
	if is_instance_valid(overlay):
		overlay.visible = false
		overlay.modulate = Color.WHITE
	if is_instance_valid(panel):
		panel.position = target
		panel.modulate = Color.WHITE


static func tween_meter(meter: ProgressBar, target: float) -> void:
	var previous: Variant = meter.get_meta(META_METER_TWEEN) if meter.has_meta(META_METER_TWEEN) else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	var tween := meter.create_tween()
	tween.tween_property(meter, "value", target, 0.42) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	meter.set_meta(META_METER_TWEEN, tween)


static func _install_recursive(node: Node) -> void:
	if node is Button:
		install_button(node as Button)
	for child in node.get_children():
		_install_recursive(child)


static func _center_pivot(button: Button) -> void:
	if is_instance_valid(button):
		button.pivot_offset = button.size * 0.5


static func _button_down(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	_play_click(button)
	_kill_tween(button)
	button.pivot_offset = button.size * 0.5
	var tilt := -0.012 if button.get_instance_id() % 2 == 0 else 0.012
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", Vector2(0.94, 0.94), 0.08) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(button, "rotation", tilt, 0.08)
	tween.tween_property(button, "modulate", Color(1.12, 1.12, 1.12, 1.0), 0.08)
	button.set_meta(META_TWEEN, tween)


static func _button_up(button: Button) -> void:
	if not is_instance_valid(button):
		return
	_kill_tween(button)
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE, 0.26) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "rotation", 0.0, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(button, "modulate", Color.WHITE, 0.18)
	button.set_meta(META_TWEEN, tween)


static func _button_hover(button: Button, hovered: bool) -> void:
	if not is_instance_valid(button) or button.disabled or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_kill_tween(button)
	button.pivot_offset = button.size * 0.5
	var target := Vector2(1.025, 1.025) if hovered else Vector2.ONE
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", target, 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(
		button,
		"modulate",
		Color(1.06, 1.06, 1.06, 1.0) if hovered else Color.WHITE,
		0.16
	)
	button.set_meta(META_TWEEN, tween)


# ponytail: one shared player on the tree root, no AudioManager. A second tap
# cuts the first; add a 2-voice pool + UI bus when settings exist.
static func _play_click(button: Button) -> void:
	if not button.is_inside_tree():
		return
	var tree := button.get_tree()
	if tree == null:
		return
	var cue := button_cue(button)
	var stream := _stream_for(cue)
	if stream == null:
		return
	var player := tree.root.get_node_or_null(NodePath(PLAYER_NAME)) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = String(PLAYER_NAME)
		tree.root.add_child(player)
	player.stream = stream
	player.volume_db = VOLUME_DB + float(CUE_TRIM_DB.get(String(cue), 0.0))
	player.pitch_scale = randf_range(0.96, 1.04)
	player.play()


static func _stream_for(cue: StringName) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue] as AudioStream
	var path := String(_STREAM_PATHS.get(String(cue), ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream != null:
		_streams[cue] = stream
	return stream


static func _kill_tween(control: Control) -> void:
	var previous: Variant = control.get_meta(META_TWEEN) if control.has_meta(META_TWEEN) else null
	if previous is Tween and previous.is_valid():
		previous.kill()
