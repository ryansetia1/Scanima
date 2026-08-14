class_name UiBottomSheet
extends Control

signal opened
signal dismissed

const DISMISS_PX := 80.0

@export var panel_path: NodePath = ^"Bottom/Panel"
@export var dismiss_button_path: NodePath = ^"DismissButton"

@onready var _panel: Control = get_node(panel_path) as Control
@onready var _dismiss_button: Button = get_node(dismiss_button_path) as Button

var _dragging := false
var _drag_start_y := 0.0
var _panel_rest_y := 0.0


func _ready() -> void:
	_dismiss_button.pressed.connect(close)
	UiJuice.install_button(_dismiss_button)
	for name in ["HandleCenter", "Header"]:
		var node := _panel.find_child(name, true, false) as Control
		if node == null:
			continue
		if name == "HandleCenter":
			node.custom_minimum_size.y = maxf(node.custom_minimum_size.y, 96.0)
		node.mouse_filter = Control.MOUSE_FILTER_STOP
		node.gui_input.connect(_on_drag_input)


func open() -> void:
	fit_to_content()
	UiJuice.show_bottom_sheet(self, _panel)
	opened.emit()


func close() -> void:
	if not visible:
		return
	_dragging = false
	UiJuice.hide_bottom_sheet(self, _panel)
	dismissed.emit()


func fit_to_content() -> void:
	if not is_instance_valid(_panel):
		return
	var height := _panel.get_combined_minimum_size().y
	_panel.offset_top = -height
	_panel.offset_bottom = 0.0
	_panel.set_meta(UiJuice.META_SHEET_POSITION, _panel.position)


func panel() -> Control:
	return _panel


func _on_drag_input(event: InputEvent) -> void:
	if UiMotion.reduced_motion:
		if _is_press(event):
			close()
			accept_event()
		return
	var y := _event_y(event)
	if _is_press(event):
		_begin_drag(y)
		accept_event()
	elif _dragging and _is_drag(event):
		_move_drag(y)
		accept_event()
	elif _dragging and _is_release(event):
		_end_drag(y)
		accept_event()


func _begin_drag(y: float) -> void:
	_dragging = true
	_drag_start_y = y
	_panel_rest_y = float(_panel.get_meta(UiJuice.META_SHEET_POSITION, _panel.position).y)
	if has_meta(UiJuice.META_TWEEN):
		var tween: Variant = get_meta(UiJuice.META_TWEEN)
		if tween is Tween and is_instance_valid(tween):
			(tween as Tween).kill()


func _move_drag(y: float) -> void:
	_panel.position.y = _panel_rest_y + maxf(0.0, y - _drag_start_y)


func _end_drag(y: float) -> void:
	_dragging = false
	if y - _drag_start_y >= DISMISS_PX:
		close()
		return
	var tween := create_tween()
	tween.tween_property(_panel, "position:y", _panel_rest_y, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _event_y(event: InputEvent) -> float:
	if event is InputEventMouse:
		return (event as InputEventMouse).global_position.y
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position.y
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position.y
	return 0.0


func _is_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
	)


func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	return (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and not (event as InputEventMouseButton).pressed
	)


func _is_drag(event: InputEvent) -> bool:
	return event is InputEventScreenDrag or (
		event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	)
