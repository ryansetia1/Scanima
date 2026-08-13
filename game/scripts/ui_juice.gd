class_name UiJuice
extends RefCounted

## Shared micro-interactions for every screen. Controls keep their own tween in
## metadata, so rapid taps replace the previous motion instead of stacking scale
## writers and leaving a button permanently squashed.

const META_INSTALLED := &"_scanima_juice_installed"
const META_TWEEN := &"_scanima_juice_tween"
const META_METER_TWEEN := &"_scanima_meter_tween"


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


static func reveal(control: Control, delay: float = 0.0) -> void:
	_kill_tween(control)
	control.visible = true
	control.pivot_offset = control.size * 0.5
	if UiMotion.reduced_motion:
		control.modulate = Color.WHITE
		control.scale = Vector2.ONE
		return
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
	if UiMotion.reduced_motion:
		control.modulate = Color.WHITE
		control.scale = Vector2.ONE
		return
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
	if UiMotion.reduced_motion:
		overlay.modulate = Color.WHITE
		panel.scale = Vector2.ONE
		panel.modulate = Color.WHITE
		return
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
	if UiMotion.reduced_motion:
		overlay.visible = false
		overlay.modulate = Color.WHITE
		panel.scale = Vector2.ONE
		panel.modulate = Color.WHITE
		return
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


static func tween_meter(meter: ProgressBar, target: float) -> void:
	var previous: Variant = meter.get_meta(META_METER_TWEEN) if meter.has_meta(META_METER_TWEEN) else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	if UiMotion.reduced_motion:
		meter.value = target
		return
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
	_kill_tween(button)
	button.pivot_offset = button.size * 0.5
	if UiMotion.reduced_motion:
		button.scale = Vector2.ONE
		button.rotation = 0.0
		button.modulate = Color(1.08, 1.08, 1.08, 1.0)
		return
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
	if UiMotion.reduced_motion:
		button.scale = Vector2.ONE
		button.rotation = 0.0
		button.modulate = Color.WHITE
		return
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
	if UiMotion.reduced_motion:
		button.scale = Vector2.ONE
		button.rotation = 0.0
		button.modulate = Color(1.06, 1.06, 1.06, 1.0) if hovered else Color.WHITE
		return
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


static func _kill_tween(control: Control) -> void:
	var previous: Variant = control.get_meta(META_TWEEN) if control.has_meta(META_TWEEN) else null
	if previous is Tween and previous.is_valid():
		previous.kill()
