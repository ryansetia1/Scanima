class_name ScanimaBackground
extends Node2D

## Procedural visual shell shared by production and the art inspector.
## No texture asset means the UI stays sharp at every aspect ratio and adds
## essentially nothing to the APK. Redraw is capped at 15 fps; the motion is
## deliberately ambient while the Anima and incubator remain the focal point.

const BG_TOP := Color(0.018, 0.026, 0.07)
const BG_MID := Color(0.035, 0.055, 0.13)
const BG_BOTTOM := Color(0.055, 0.035, 0.11)
const CYAN := Color(0.278, 0.902, 1.0)
const VIOLET := Color(0.67, 0.42, 1.0)
const GOLD := Color(1.0, 0.82, 0.4)
const REDRAW_INTERVAL_SEC := 1.0 / 15.0

var _phase: float = 0.0
var _redraw_accumulator: float = 0.0


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL_SEC:
		_redraw_accumulator = fmod(_redraw_accumulator, REDRAW_INTERVAL_SEC)
		queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return

	_draw_gradient(size)
	var chamber_center := Vector2(size.x * 0.5, size.y * 0.43)
	_draw_chamber(chamber_center, size)
	_draw_particles(size)
	_draw_floor_grid(size)
	_draw_vignette(size)


func _draw_gradient(size: Vector2) -> void:
	const BANDS := 36
	for band in BANDS:
		var t := float(band) / float(BANDS - 1)
		var color := BG_TOP.lerp(BG_MID, t * 2.0) if t < 0.5 else BG_MID.lerp(BG_BOTTOM, (t - 0.5) * 2.0)
		draw_rect(
			Rect2(0.0, size.y * t, size.x, size.y / float(BANDS) + 2.0),
			color
		)


func _draw_chamber(center: Vector2, size: Vector2) -> void:
	var pulse := 1.0 + sin(_phase * 0.72) * 0.035
	draw_circle(center, minf(size.x * 0.46, 330.0) * pulse, Color(CYAN, 0.018))
	draw_circle(center, minf(size.x * 0.36, 255.0) * pulse, Color(VIOLET, 0.022))

	for ring in 4:
		var radius := (142.0 + float(ring) * 38.0) * pulse
		var color := CYAN if ring % 2 == 0 else VIOLET
		draw_arc(
			center,
			radius,
			_phase * (0.08 + float(ring) * 0.025) + float(ring),
			_phase * (0.08 + float(ring) * 0.025) + float(ring) + 4.2,
			72,
			Color(color, 0.08 - float(ring) * 0.012),
			2.0,
			true
		)

	for tick in 24:
		var angle := TAU * float(tick) / 24.0 + _phase * 0.035
		var inner := 208.0 + float(tick % 3) * 5.0
		var outer := inner + (12.0 if tick % 6 == 0 else 6.0)
		var direction := Vector2.from_angle(angle)
		draw_line(
			center + direction * inner,
			center + direction * outer,
			Color(GOLD if tick % 6 == 0 else CYAN, 0.22),
			2.0,
			true
		)

	var floor_center := center + Vector2(0.0, 250.0)
	for glow in 5:
		var width := 250.0 - float(glow) * 24.0
		var alpha := 0.018 + float(glow) * 0.008
		draw_colored_polygon(
			_ellipse_points(floor_center, width, 42.0 - float(glow) * 4.0, 64),
			Color(CYAN, alpha)
		)


func _draw_particles(size: Vector2) -> void:
	for i in 26:
		var particle_seed := float(i * 47 % 101) / 101.0
		var x := fposmod(particle_seed * size.x + _phase * (5.0 + float(i % 5)), size.x)
		var y := fposmod(float((i * 83) % 127) / 127.0 * size.y - _phase * (3.0 + i % 4), size.y)
		var twinkle := 0.35 + (sin(_phase * 1.8 + float(i) * 2.1) + 1.0) * 0.25
		var color := GOLD if i % 7 == 0 else (VIOLET if i % 3 == 0 else CYAN)
		draw_circle(Vector2(x, y), 1.2 + float(i % 3), Color(color, 0.12 * twinkle))


func _draw_floor_grid(size: Vector2) -> void:
	var horizon := size.y * 0.71
	for line in 9:
		var t := float(line) / 8.0
		var eased := t * t
		var y := lerpf(horizon, size.y + 10.0, eased)
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(CYAN, 0.055 * (1.0 - t)), 1.0)

	for column in 11:
		var bottom_x := size.x * float(column) / 10.0
		var horizon_x := lerpf(size.x * 0.42, size.x * 0.58, float(column) / 10.0)
		draw_line(
			Vector2(horizon_x, horizon),
			Vector2(bottom_x, size.y),
			Color(VIOLET, 0.045),
			1.0
		)


func _draw_vignette(size: Vector2) -> void:
	draw_rect(Rect2(0.0, 0.0, size.x, 170.0), Color(0.005, 0.01, 0.035, 0.28))
	draw_rect(Rect2(0.0, size.y - 330.0, size.x, 330.0), Color(0.005, 0.008, 0.03, 0.22))
	draw_line(Vector2(0.0, 2.0), Vector2(size.x, 2.0), Color(CYAN, 0.2), 2.0)


func _ellipse_points(center: Vector2, radius_x: float, radius_y: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		var angle := TAU * float(i) / float(count)
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points
