class_name IncubatorEffect
extends Node2D

## Inkubator procedural untuk jeda generation Replicate.
##
## Tidak memakai texture atau particle asset: seluruh telur energi, ring,
## scanner, dan spark digambar dari primitive CanvasItem. Dengan begitu efeknya
## selalu tersedia saat app baru dipasang dan tidak menambah ukuran APK.

const CYAN := Color(0.20, 0.92, 1.00)
const BLUE := Color(0.18, 0.48, 1.00)
const VIOLET := Color(0.67, 0.35, 1.00)
const GOLD := Color(1.00, 0.78, 0.30)
const CORE_DARK := Color(0.025, 0.055, 0.12)
const BASE_SCALE := Vector2(1.32, 1.32)
const REDRAW_INTERVAL_SEC := 1.0 / 30.0

var _phase := 0.0
var _charge := 0.0
var _burst := 0.0
var _redraw_accumulator := 0.0
var _active := false
var _fx_tween: Tween = null


func _ready() -> void:
	visible = false
	set_process(false)


func start() -> void:
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_phase = 0.0
	_charge = 0.45
	_burst = 0.0
	_redraw_accumulator = 0.0
	_active = true
	visible = true
	scale = Vector2(0.94, 0.94)
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	set_process(true)
	queue_redraw()
	if UiMotion.reduced_motion:
		scale = BASE_SCALE
		modulate = Color.WHITE
		return

	_fx_tween = create_tween().set_parallel(true)
	_fx_tween.tween_property(self, "scale", BASE_SCALE, 0.42) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_fx_tween.tween_property(self, "modulate:a", 1.0, 0.24) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Mengembang dan memutihkan ring, lalu mengembalikan kontrol tepat saat flash
## mencapai puncak. Fade ring tetap berjalan di belakang reveal Anima supaya
## keduanya terasa sebagai satu transisi, bukan dua animasi berurutan.
func burst() -> void:
	if not _active:
		return
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	if UiMotion.reduced_motion:
		_finish_burst()
		await get_tree().process_frame
		return

	_fx_tween = create_tween().set_parallel(true)
	_fx_tween.tween_method(_set_burst, 0.0, 1.0, 0.56) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	_fx_tween.tween_property(self, "scale", Vector2(1.76, 1.76), 0.56) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_fx_tween.tween_property(self, "modulate:a", 0.0, 0.34).set_delay(0.22)
	_fx_tween.tween_callback(_finish_burst).set_delay(0.58)

	await get_tree().create_timer(0.20).timeout


func stop() -> void:
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = null
	_active = false
	visible = false
	set_process(false)
	scale = Vector2.ONE
	modulate = Color.WHITE
	_burst = 0.0


func is_active() -> bool:
	return _active


func _finish_burst() -> void:
	_fx_tween = null
	_active = false
	visible = false
	set_process(false)
	scale = Vector2.ONE
	modulate = Color.WHITE
	_burst = 0.0


func _set_burst(value: float) -> void:
	_burst = value
	queue_redraw()


func _process(delta: float) -> void:
	if UiMotion.reduced_motion:
		return
	_phase += delta
	_charge = move_toward(_charge, 1.0, delta * 0.7)
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL_SEC:
		_redraw_accumulator = fmod(_redraw_accumulator, REDRAW_INTERVAL_SEC)
		queue_redraw()


func _draw() -> void:
	var center := Vector2(0.0, -116.0)
	var pulse := 1.0 + sin(_phase * 3.2) * 0.025
	var energy := 0.72 + _charge * 0.28

	# Aura berlapis. Alpha rendah yang bertumpuk memberi kesan glow tanpa shader.
	draw_circle(center, 142.0 * pulse, _alpha(BLUE, 0.025 * energy))
	draw_circle(center, 116.0 * pulse, _alpha(VIOLET, 0.035 * energy))
	draw_circle(center, 94.0 * pulse, _alpha(CYAN, 0.045 * energy))

	var floor_glow := _ellipse_points(Vector2(0.0, -3.0), 94.0, 18.0, 0.0, 40)
	draw_colored_polygon(floor_glow, _alpha(CYAN, 0.07 * energy))
	draw_polyline(_closed(floor_glow), _alpha(GOLD, 0.42), 2.0, true)

	# Dua orbit miring memberi kedalaman dan gerak yang lebih mewah daripada
	# spinner tunggal. Highlight arc bergerak dengan kecepatan berbeda.
	var orbit_a := _ellipse_points(center, 150.0, 51.0, 0.26, 64)
	var orbit_b := _ellipse_points(center, 126.0, 43.0, -0.48, 64)
	draw_polyline(_closed(orbit_a), _alpha(CYAN, 0.30 * energy), 2.0, true)
	draw_polyline(_closed(orbit_b), _alpha(VIOLET, 0.34 * energy), 2.0, true)
	_draw_orbit_arc(center, 150.0, 51.0, 0.26, _phase * 1.25, CYAN, 4.0)
	_draw_orbit_arc(center, 126.0, 43.0, -0.48, -_phase * 0.92, VIOLET, 3.0)

	# HUD ring tersegmentasi dan tick radial membuat silhouette terasa seperti
	# mesin inkubasi premium, bukan sekadar telur yang berdenyut.
	for segment in 8:
		var start_angle := _phase * 0.48 + float(segment) * TAU / 8.0
		var segment_color := GOLD if segment % 4 == 0 else (CYAN if segment % 2 == 0 else VIOLET)
		draw_arc(
			center,
			108.0 + float(segment % 2) * 8.0,
			start_angle,
			start_angle + 0.42,
			8,
			_alpha(segment_color, 0.62 * energy),
			3.0,
			true
		)
		var direction := Vector2(cos(start_angle), sin(start_angle))
		draw_line(
			center + Vector2(direction.x * 166.0, direction.y * 103.0),
			center + Vector2(direction.x * 178.0, direction.y * 111.0),
			_alpha(segment_color, 0.68),
			3.0,
			true
		)

	# Telur energi: bagian atas lebih ramping, bagian bawah lebih penuh.
	var egg := _egg_points(center, 76.0 * pulse, 108.0 * pulse, 72)
	draw_colored_polygon(egg, _alpha(CORE_DARK, 0.96))
	draw_polyline(_closed(egg), _alpha(BLUE, 0.62 * energy), 9.0, true)
	draw_polyline(_closed(egg), _alpha(CYAN, 0.92 * energy), 3.0, true)

	# Garis material holografik dan scanner hidup di dalam silhouette telur.
	for row in 5:
		var y := center.y - 68.0 + row * 34.0
		var half_width := _egg_half_width(y - center.y, 70.0, 102.0)
		draw_line(
			Vector2(-half_width, y),
			Vector2(half_width, y),
			_alpha(BLUE if row % 2 == 0 else VIOLET, 0.20),
			1.5,
			true
		)

	var scan_t := fposmod(_phase * 0.36, 1.0)
	var scan_y := center.y - 82.0 + scan_t * 164.0
	var scan_half := _egg_half_width(scan_y - center.y, 70.0, 102.0)
	draw_line(
		Vector2(-scan_half, scan_y),
		Vector2(scan_half, scan_y),
		_alpha(CYAN, 0.88),
		4.0,
		true
	)
	draw_line(
		Vector2(-scan_half * 0.7, scan_y + 7.0),
		Vector2(scan_half * 0.7, scan_y + 7.0),
		_alpha(CYAN, 0.18),
		10.0,
		true
	)

	# Core berlian berdenyut sebagai focal point.
	var core_scale := 1.0 + sin(_phase * 5.4) * 0.08
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -27.0) * core_scale,
		center + Vector2(21.0, 0.0) * core_scale,
		center + Vector2(0.0, 27.0) * core_scale,
		center + Vector2(-21.0, 0.0) * core_scale,
	])
	draw_colored_polygon(diamond, _alpha(VIOLET, 0.42))
	draw_polyline(_closed(diamond), _alpha(CYAN, 0.95), 3.0, true)
	draw_circle(center, 8.0 + sin(_phase * 6.0) * 2.0, _alpha(GOLD, 0.95))

	# Orbit spark: cyan/violet menjaga bahasa futuristik, gold memberi aksen
	# premium. Ukurannya berubah, tetapi jumlah draw call tetap konstan.
	for i in 16:
		var angle := _phase * (0.42 + float(i % 3) * 0.08) + TAU * float(i) / 16.0
		var radius_x := 118.0 + float((i * 17) % 35)
		var radius_y := 74.0 + float((i * 11) % 26)
		var point := center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
		var twinkle := 1.5 + (sin(_phase * 5.0 + i * 1.7) + 1.0) * 1.6
		var color := GOLD if i % 4 == 0 else (VIOLET if i % 2 == 0 else CYAN)
		draw_circle(point, twinkle, _alpha(color, 0.78))

	if _burst > 0.0:
		var fade := 1.0 - _burst
		draw_circle(center, 42.0 + _burst * 138.0, _alpha(Color.WHITE, fade * 0.34))
		draw_arc(center, 88.0 + _burst * 190.0, 0.0, TAU, 72, _alpha(CYAN, fade), 7.0, true)
		draw_arc(center, 64.0 + _burst * 240.0, 0.0, TAU, 72, _alpha(GOLD, fade * 0.82), 3.0, true)


func _draw_orbit_arc(
	center: Vector2,
	radius_x: float,
	radius_y: float,
	rotation_angle: float,
	arc_start: float,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array()
	for i in 14:
		var angle := arc_start + float(i) / 13.0 * 0.88
		points.append(
			center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y).rotated(rotation_angle)
		)
	draw_polyline(points, _alpha(color, 0.92), width, true)


func _ellipse_points(
	center: Vector2,
	radius_x: float,
	radius_y: float,
	rotation_angle: float,
	segments: int
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(
			center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y).rotated(rotation_angle)
		)
	return points


func _egg_points(center: Vector2, radius_x: float, radius_y: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		var vertical := sin(angle)
		var width_factor := 0.82 if vertical < 0.0 else 1.04
		points.append(center + Vector2(cos(angle) * radius_x * width_factor, vertical * radius_y))
	return points


func _egg_half_width(local_y: float, radius_x: float, radius_y: float) -> float:
	var normalized := clampf(local_y / radius_y, -1.0, 1.0)
	var width_factor := 0.82 if normalized < 0.0 else 1.04
	return sqrt(maxf(0.0, 1.0 - normalized * normalized)) * radius_x * width_factor


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
