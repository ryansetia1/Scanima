class_name SynthesisIncubatorVisual
extends Control

## Indeterminate Synthesis activity indicator. It deliberately communicates
## "work continues" without inventing a percentage or ETA the backend does not
## expose. The brand-only drawing keeps the capsule crisp at every viewport.

const REDRAW_INTERVAL_SEC := 1.0 / 15.0
const PARTICLE_COUNT := 12

var _phase := 0.0
var _redraw_accumulator := 0.0


func _ready() -> void:
	resized.connect(queue_redraw)
	_sync_processing()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		_sync_processing()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, TAU * 100.0)
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL_SEC:
		_redraw_accumulator = fmod(_redraw_accumulator, REDRAW_INTERVAL_SEC)
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var center := Vector2(size.x * 0.5, size.y * 0.46)
	var capsule_width := minf(size.x * 0.30, 170.0)
	var capsule_height := minf(size.y * 0.72, 260.0)
	var pulse := 1.0 + sin(_phase * 1.35) * 0.025

	_draw_feed_lines(center, capsule_width, capsule_height)
	_draw_halo(center, capsule_width, capsule_height, pulse)
	_draw_capsule(center, capsule_width, capsule_height, pulse)
	_draw_particles(center, capsule_width, capsule_height)


func _draw_feed_lines(center: Vector2, width: float, height: float) -> void:
	var source_y := size.y - 2.0
	var source_points := [Vector2(size.x * 0.25, source_y), Vector2(size.x * 0.75, source_y)]
	var capsule_points := [
		center + Vector2(-width * 0.28, height * 0.38),
		center + Vector2(width * 0.28, height * 0.38),
	]
	for index in 2:
		var color := ScanimaBackground.CYAN if index == 0 else ScanimaBackground.VIOLET
		var start: Vector2 = source_points[index]
		var finish: Vector2 = capsule_points[index]
		draw_line(start, finish, Color(color, 0.22), 2.0, true)
		var travel := fposmod(_phase * 0.24 + float(index) * 0.5, 1.0)
		var signal_point := start.lerp(finish, travel)
		draw_circle(signal_point, 4.0, Color(color, 0.86))


func _draw_halo(center: Vector2, width: float, height: float, pulse: float) -> void:
	for glow in 5:
		var grow := float(5 - glow) * 11.0
		var glow_points := _capsule_points(
			center,
			(width + grow) * pulse,
			(height + grow * 1.4) * pulse,
			18
		)
		var alpha := 0.008 + float(glow) * 0.008
		draw_colored_polygon(glow_points, Color(ScanimaBackground.CYAN, alpha))

	for ring in 3:
		var radius := width * (0.68 + float(ring) * 0.22) * pulse
		var color := ScanimaBackground.CYAN if ring % 2 == 0 else ScanimaBackground.VIOLET
		var start_angle := _phase * (0.18 + float(ring) * 0.04) + float(ring) * 1.7
		draw_arc(
			center,
			radius,
			start_angle,
			start_angle + 4.25,
			48,
			Color(color, 0.24 - float(ring) * 0.045),
			2.0,
			true
		)


func _draw_capsule(center: Vector2, width: float, height: float, pulse: float) -> void:
	var outer := _capsule_points(center, width * pulse, height * pulse, 24)
	draw_colored_polygon(outer, Color(ScanimaBackground.BG_MID, 0.96))
	draw_polyline(_closed(outer), Color(ScanimaBackground.CYAN, 0.78), 3.0, true)

	var inner := _capsule_points(center, width - 18.0, height - 18.0, 24)
	draw_colored_polygon(inner, Color(ScanimaBackground.BG_TOP, 0.90))
	draw_polyline(_closed(inner), Color(ScanimaBackground.VIOLET, 0.40), 2.0, true)

	var core_pulse := 1.0 + sin(_phase * 1.8) * 0.08
	draw_circle(center, 45.0 * core_pulse, Color(ScanimaBackground.VIOLET, 0.10))
	draw_circle(center, 31.0 * core_pulse, Color(ScanimaBackground.CYAN, 0.14))
	draw_circle(center, 13.0, Color(ScanimaBackground.GOLD, 0.72))

	for scan_line in 6:
		var y := center.y - height * 0.28 + float(scan_line) * height * 0.11
		var line_alpha := 0.08 + 0.08 * sin(_phase * 1.4 + float(scan_line))
		draw_line(
			Vector2(center.x - width * 0.28, y),
			Vector2(center.x + width * 0.28, y),
			Color(ScanimaBackground.CYAN, maxf(0.025, line_alpha)),
			1.0,
			true
		)


func _draw_particles(center: Vector2, width: float, height: float) -> void:
	for index in PARTICLE_COUNT:
		var seed := float(index) / float(PARTICLE_COUNT)
		var angle := TAU * seed + _phase * (0.12 + float(index % 3) * 0.025)
		var orbit := Vector2(width * (0.72 + float(index % 4) * 0.09), height * 0.38)
		var point := center + Vector2(cos(angle) * orbit.x, sin(angle) * orbit.y)
		var color := ScanimaBackground.GOLD if index % 4 == 0 else ScanimaBackground.CYAN
		draw_circle(point, 1.8 + float(index % 3), Color(color, 0.34))


func _sync_processing() -> void:
	set_process(is_visible_in_tree())


static func _capsule_points(
	center: Vector2, width: float, height: float, arc_segments: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := width * 0.5
	var straight_half := maxf(0.0, height * 0.5 - radius)
	var top_center := center - Vector2(0.0, straight_half)
	var bottom_center := center + Vector2(0.0, straight_half)
	for step in arc_segments + 1:
		var angle := PI + PI * float(step) / float(arc_segments)
		points.append(top_center + Vector2.from_angle(angle) * radius)
	for step in arc_segments + 1:
		var angle := PI * float(step) / float(arc_segments)
		points.append(bottom_center + Vector2.from_angle(angle) * radius)
	return points


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not closed.is_empty():
		closed.append(closed[0])
	return closed
