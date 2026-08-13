class_name ScanOverlay
extends Control

const CYAN := Color(0.20, 0.92, 1.00)
const VIOLET := Color(0.67, 0.35, 1.00)
const REDRAW_INTERVAL_SEC := 1.0 / 15.0
const EDGE_MARGIN := 22.0
const CORNER_LENGTH := 34.0
const SCAN_SPEED_PX := 130.0

var _phase := 0.0
var _redraw_accumulator := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func set_active(active: bool) -> void:
	visible = active
	set_process(active and not UiMotion.reduced_motion)
	if active:
		_phase = 0.0
		_redraw_accumulator = 0.0
		queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL_SEC:
		_redraw_accumulator = fmod(_redraw_accumulator, REDRAW_INTERVAL_SEC)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		queue_redraw()


func _draw() -> void:
	if size.x <= EDGE_MARGIN * 2.0 or size.y <= EDGE_MARGIN * 2.0:
		return

	var frame := Rect2(
		Vector2(EDGE_MARGIN, EDGE_MARGIN),
		size - Vector2.ONE * EDGE_MARGIN * 2.0
	)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.06, 0.16, 0.10))
	_draw_corners(frame)

	var travel := maxf(frame.size.y, 1.0)
	var scan_y := frame.position.y + travel * 0.5
	if not UiMotion.reduced_motion:
		scan_y = frame.position.y + fposmod(_phase * SCAN_SPEED_PX, travel)
	var scan_from := Vector2(frame.position.x, scan_y)
	var scan_to := Vector2(frame.end.x, scan_y)
	draw_rect(
		Rect2(scan_from - Vector2(0.0, 10.0), Vector2(frame.size.x, 20.0)),
		Color(VIOLET, 0.10)
	)
	draw_line(scan_from, scan_to, Color(CYAN, 0.88), 3.0, true)


func _draw_corners(frame: Rect2) -> void:
	var top_left := frame.position
	var top_right := Vector2(frame.end.x, frame.position.y)
	var bottom_right := frame.end
	var bottom_left := Vector2(frame.position.x, frame.end.y)
	for corner in [
		[top_left, Vector2.RIGHT, Vector2.DOWN],
		[top_right, Vector2.LEFT, Vector2.DOWN],
		[bottom_right, Vector2.LEFT, Vector2.UP],
		[bottom_left, Vector2.RIGHT, Vector2.UP],
	]:
		var point: Vector2 = corner[0]
		draw_line(point, point + corner[1] * CORNER_LENGTH, Color(CYAN, 0.80), 4.0, true)
		draw_line(point, point + corner[2] * CORNER_LENGTH, Color(CYAN, 0.80), 4.0, true)
