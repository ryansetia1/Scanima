class_name FirstAnimaEffect
extends Node2D

const CYAN := Color(0.20, 0.92, 1.00)
const VIOLET := Color(0.67, 0.35, 1.00)
const GOLD := Color(1.00, 0.78, 0.30)
const REDRAW_INTERVAL_SEC := 1.0 / 15.0

var _phase := 0.0
var _redraw_accumulator := 0.0


func _ready() -> void:
	visible = false
	set_process(false)


func set_active(active: bool) -> void:
	visible = active
	set_process(active)
	if active:
		queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL_SEC:
		_redraw_accumulator = fmod(_redraw_accumulator, REDRAW_INTERVAL_SEC)
		queue_redraw()


func _draw() -> void:
	var center := Vector2(0.0, -116.0)
	var pulse := 1.0 + sin(_phase * 2.4) * 0.035
	draw_circle(center, 108.0 * pulse, Color(0.06, 0.12, 0.28, 0.34))
	draw_arc(center, 108.0 * pulse, 0.0, TAU, 64, Color(CYAN, 0.32), 3.0, true)
	draw_arc(
		center,
		82.0 * pulse,
		_phase * 0.7,
		_phase * 0.7 + TAU * 0.68,
		44,
		Color(VIOLET, 0.64),
		5.0,
		true
	)

	for corner in [
		Vector2(-74.0, -74.0),
		Vector2(74.0, -74.0),
		Vector2(74.0, 74.0),
		Vector2(-74.0, 74.0),
	]:
		var horizontal := -1.0 if corner.x > 0.0 else 1.0
		var vertical := -1.0 if corner.y > 0.0 else 1.0
		draw_line(center + corner, center + corner + Vector2(horizontal * 25.0, 0.0), Color(CYAN, 0.74), 4.0)
		draw_line(center + corner, center + corner + Vector2(0.0, vertical * 25.0), Color(CYAN, 0.74), 4.0)

	var scan_y := center.y - 62.0 + fposmod(_phase * 34.0, 124.0)
	draw_line(Vector2(-64.0, scan_y), Vector2(64.0, scan_y), Color(CYAN, 0.76), 3.0)
	draw_circle(center, 22.0 * pulse, Color(VIOLET, 0.42))
	draw_circle(center, 9.0 * pulse, Color(GOLD, 0.92))
