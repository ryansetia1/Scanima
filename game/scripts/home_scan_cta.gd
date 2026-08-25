## HomeScanCta – circle-spin + camera graphic for the empty-state home lobby.
## Draws spinning arcs and corner brackets identically to FirstAnimaEffect but
## as a Control so it slots into the HomeView layout. The camera TextureRect and
## the CTA button live as children in the scene; this node only owns the drawing.
class_name HomeScanCta
extends Control

const CYAN := Color(0.20, 0.92, 1.00)
const VIOLET := Color(0.67, 0.35, 1.00)
const GOLD := Color(1.00, 0.78, 0.30)
const REDRAW_INTERVAL_SEC := 1.0 / 15.0

## Radius of the outer ring, relative to the node's own centre.
const RING_RADIUS := 108.0
const INNER_RADIUS := 82.0
const CORNER_HALF := 74.0
const CORNER_LEN := 25.0

var _phase := 0.0
var _redraw_accumulator := 0.0


func _ready() -> void:
	visible = false
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_active(active: bool) -> void:
	visible = active
	set_process(active)
	if active:
		_phase = 0.0
		queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL_SEC:
		_redraw_accumulator = fmod(_redraw_accumulator, REDRAW_INTERVAL_SEC)
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var pulse := 1.0 + sin(_phase * 2.4) * 0.035

	# Outer fill + ring
	draw_circle(center, RING_RADIUS * pulse, Color(0.06, 0.12, 0.28, 0.30))
	draw_arc(center, RING_RADIUS * pulse, 0.0, TAU, 64, Color(CYAN, 0.28), 3.0, true)

	# Spinning violet arc
	draw_arc(
		center,
		INNER_RADIUS * pulse,
		_phase * 0.7,
		_phase * 0.7 + TAU * 0.68,
		44,
		Color(VIOLET, 0.60),
		5.0,
		true
	)

	# Corner brackets
	for corner: Vector2 in [
		Vector2(-CORNER_HALF, -CORNER_HALF),
		Vector2(CORNER_HALF, -CORNER_HALF),
		Vector2(CORNER_HALF, CORNER_HALF),
		Vector2(-CORNER_HALF, CORNER_HALF),
	]:
		var h := -1.0 if corner.x > 0.0 else 1.0
		var v := -1.0 if corner.y > 0.0 else 1.0
		draw_line(center + corner, center + corner + Vector2(h * CORNER_LEN, 0.0), Color(CYAN, 0.72), 4.0)
		draw_line(center + corner, center + corner + Vector2(0.0, v * CORNER_LEN), Color(CYAN, 0.72), 4.0)

	# Scan line
	var travel := RING_RADIUS * 2.0 * pulse
	var scan_y := center.y - RING_RADIUS * pulse + fposmod(_phase * 34.0, travel)
	draw_line(
		Vector2(center.x - CORNER_HALF, scan_y),
		Vector2(center.x + CORNER_HALF, scan_y),
		Color(CYAN, 0.70),
		3.0
	)
