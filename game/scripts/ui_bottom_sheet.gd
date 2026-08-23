class_name UiBottomSheet
extends Control

signal opened
signal dismissed

const DISMISS_PX := 80.0
const HANDLE_TOUCH_HEIGHT := 96.0
const SHEET_GAP := 8
const CONTENT_GAP := 16
const MIN_SCROLL_HEIGHT := 192.0

@export var panel_path: NodePath = ^"Bottom/Panel"
@export var dismiss_button_path: NodePath = ^"DismissButton"
@export var scroll_content := false
@export var respect_safe_bottom := true
@export_range(0.5, 1.0, 0.01) var max_height_ratio := 0.92

@onready var _panel: Control = get_node(panel_path) as Control
@onready var _dismiss_button: Button = get_node(dismiss_button_path) as Button

var _dragging := false
var _drag_start_y := 0.0
var _panel_rest_y := 0.0
var _open_token := 0
var _column: VBoxContainer
var _scroll: ScrollContainer
var _scroll_body: VBoxContainer
var _safe_bottom: Control
var _fill_child: Control
var _fill_child_floor := 0.0
var _measured_content: Control
var _last_fit_width := -1.0


func _ready() -> void:
	_pin_full_rect()
	_dismiss_button.pressed.connect(close)
	UiJuice.install_button(_dismiss_button)
	_column = _panel.find_child("Column", true, false) as VBoxContainer
	if _column == null:
		return
	_column.add_theme_constant_override("separation", SHEET_GAP)
	var content_slot := _column.find_child("ContentSlot", false, false) as VBoxContainer
	if content_slot != null:
		content_slot.add_theme_constant_override("separation", CONTENT_GAP)
	var handle := _column.find_child("HandleCenter", false, false) as Control
	if handle != null:
		handle.custom_minimum_size.y = maxf(handle.custom_minimum_size.y, HANDLE_TOUCH_HEIGHT)
		handle.mouse_filter = Control.MOUSE_FILTER_STOP
		handle.gui_input.connect(_on_drag_input)
	if scroll_content:
		_install_content_scroll(handle)
	# Autowrap minimum heights are computed against the control's WIDTH, so
	# every one of them is wrong until the container sort has handed the content
	# its real width -- a known Godot regression (godotengine/godot#83546),
	# whose signature symptom is exactly "reopen it and now it fits". Measured
	# here: the Collection preview's Column sat at its own 350 px minimum inside
	# a 720 px panel, so a one-line meta label reported a 312 px minimum and the
	# sheet opened far taller than its content.
	#
	# Watched on the CONTENT, not on `_panel`: the panel is anchor-stretched and
	# its width never changes, so it never reports the moment that actually
	# matters. Re-fitting when the content's width lands beats guessing how many
	# frames the sort needs.
	var measured: Control = _scroll_body if is_instance_valid(_scroll_body) else _column
	if is_instance_valid(measured):
		_measured_content = measured
		measured.resized.connect(_on_content_resized)
	_install_safe_bottom()
	if is_inside_tree():
		get_viewport().size_changed.connect(_on_viewport_size_changed)


func open() -> void:
	_open_token += 1
	var token := _open_token
	visible = true
	_pin_full_rect()
	modulate.a = 0.0
	# Dynamic rows and queue_free() settle at frame end. Starting the tween
	# sooner captures yesterday's panel height; its deferred relayout then moves
	# the anchors under the running tween, leaving the first open floating.
	# Hidden instances also report size 0 until laid out; Android can need a
	# second frame before FULL_RECT fills the host.
	if is_inside_tree():
		await get_tree().process_frame
		if token != _open_token or not is_instance_valid(self) or not visible:
			return
		_pin_full_rect()
		if size.x < 1.0 or size.y < 1.0:
			await get_tree().process_frame
			if token != _open_token or not is_instance_valid(self) or not visible:
				return
			_pin_full_rect()
	fit_to_content()
	UiJuice.show_bottom_sheet(self, _panel)
	opened.emit()


func _pin_full_rect() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func close() -> void:
	_open_token += 1
	if not visible:
		return
	_dragging = false
	UiJuice.hide_bottom_sheet(self, _panel)
	dismissed.emit()


func fit_to_content() -> void:
	if not is_instance_valid(_panel):
		return
	_refresh_safe_bottom()
	var host_size := UiJuice.sheet_host_size(self, _panel)
	var host_h := host_size.y
	if host_h < 1.0:
		return
	if is_instance_valid(_measured_content):
		_last_fit_width = _measured_content.size.x
	_fit_scroll_to_host(host_h)
	var height := _panel.get_combined_minimum_size().y
	_panel.offset_left = UiJuice.SHEET_SIDE_INSET
	_panel.offset_right = -UiJuice.SHEET_SIDE_INSET
	_panel.offset_top = -height
	_panel.offset_bottom = 0.0
	var rest := Vector2(UiJuice.SHEET_SIDE_INSET, host_h - height)
	_panel.set_meta(UiJuice.META_SHEET_POSITION, rest)
	var tween: Variant = get_meta(UiJuice.META_TWEEN) if has_meta(UiJuice.META_TWEEN) else null
	if tween is Tween and is_instance_valid(tween) and (tween as Tween).is_running():
		return
	_panel.position = rest


## Only a WIDTH change re-fits. Height changes are this sheet's own doing, so
## reacting to them would re-enter `fit_to_content()` forever.
func _on_content_resized() -> void:
	if not visible or not is_instance_valid(_measured_content):
		return
	if is_equal_approx(_measured_content.size.x, _last_fit_width):
		return
	call_deferred("fit_to_content")


func panel() -> Control:
	return _panel


static func scaled_safe_bottom(
	viewport_size: Vector2, screen_size: Vector2, safe_area: Rect2
) -> float:
	if viewport_size.y <= 0.0 or screen_size.y <= 0.0:
		return 0.0
	return maxf(0.0, (screen_size.y - safe_area.end.y) * viewport_size.y / screen_size.y)


func _install_content_scroll(handle: Control) -> void:
	_scroll = ScrollContainer.new()
	_scroll.name = "ContentScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll_body = VBoxContainer.new()
	_scroll_body.name = "SheetContent"
	_scroll_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_body.add_theme_constant_override("separation", CONTENT_GAP)
	_column.add_child(_scroll)
	_scroll.add_child(_scroll_body)
	for child in _column.get_children():
		if child == handle or child == _scroll:
			continue
		child.reparent(_scroll_body)


func _install_safe_bottom() -> void:
	_safe_bottom = Control.new()
	_safe_bottom.name = "SafeAreaBottom"
	_safe_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_bottom.visible = false
	_column.add_child(_safe_bottom)


func _refresh_safe_bottom() -> void:
	if not is_instance_valid(_safe_bottom):
		return
	var inset := 0.0
	if respect_safe_bottom and (OS.has_feature("android") or OS.has_feature("ios")):
		inset = scaled_safe_bottom(
			get_viewport_rect().size,
			Vector2(DisplayServer.screen_get_size()),
			DisplayServer.get_display_safe_area()
		)
	_safe_bottom.custom_minimum_size.y = inset
	_safe_bottom.visible = inset > 0.5


## Nominates one child to absorb whatever height the sheet has left over, so a
## list does not sit at its scene minimum while the sheet opens at a fraction
## of the screen. The floor is whatever the scene asked for.
func set_fill_child(control: Control) -> void:
	_fill_child = control
	_fill_child_floor = control.custom_minimum_size.y if control != null else 0.0


func _fit_scroll_to_host(host_h: float) -> void:
	if not is_instance_valid(_scroll) or not is_instance_valid(_scroll_body):
		return
	# Both minimums are reset BEFORE measuring, and that ordering is the whole
	# point: `_panel`'s minimum already contains the scroll's, and the scroll's
	# already contains the fill child's. Measuring without zeroing them first
	# and then subtracting a child's own contribution feeds the result back into
	# the next measurement -- measured, that grew the Battle picker's list to
	# 1698 px on a 1602 px screen, pushing the panel off the top of the sheet.
	_scroll.custom_minimum_size.y = 0.0
	var filling := is_instance_valid(_fill_child) and _fill_child.visible
	if is_instance_valid(_fill_child):
		_fill_child.custom_minimum_size.y = _fill_child_floor
	var chrome_h := _panel.get_combined_minimum_size().y
	var max_panel_h := host_h * clampf(max_height_ratio, 0.5, 1.0)
	var available := maxf(MIN_SCROLL_HEIGHT, max_panel_h - chrome_h)
	if filling:
		var body_without_fill := (
			_scroll_body.get_combined_minimum_size().y - _fill_child.custom_minimum_size.y
		)
		_fill_child.custom_minimum_size.y = maxf(
			_fill_child_floor, available - body_without_fill
		)
	_scroll.custom_minimum_size.y = minf(_scroll_body.get_combined_minimum_size().y, available)


func _on_viewport_size_changed() -> void:
	if visible:
		call_deferred("fit_to_content")


func _on_drag_input(event: InputEvent) -> void:
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
