class_name BattleScale
extends RefCounted

const BODY_HEIGHT_REFERENCE_CM := 120.0
const BODY_HEIGHT_CURVE := 0.42
const BODY_HEIGHT_MIN_CM := 20.0
const BODY_HEIGHT_MAX_CM := 2000.0
const ARENA_REFERENCE_HEIGHT_RATIO := 0.45
const DESIGN_ARENA := Vector2(720.0, 800.0)
const PLAYER_SHOT_X := 0.27
const OPPONENT_SHOT_X := 0.73
const GROUND_Y_RATIO := 0.91
const ANIMA_VISUAL_HEIGHT_CAP_CM := 300.0
const SEEKER_OVERLAP_RATIO := 0.6
const SEEKER_CAMERA_EDGE_PAD_RATIO := 0.025
## Dipilih dari perbandingan langsung 3 varian jarak di Duel (100%/70%/45%
## dari kolom penuh yang dihitung `seeker_reserved_column()`). Kolom penuh
## (100%) dijamin nol overlap di semua orientasi tapi terasa terlalu jauh;
## 45% yang paling disukai secara visual overlap parah di potret (~46% lebar
## figur di 720x1602). 0,75 adalah titik tengah yang diuji: overlap di
## potret <=20% lebar figur (test_scan_ui.gd _test_duel_view), landscape
## tetap nol -- figur dan Anima boleh bersinggungan tipis, ditanggung
## z-order yang sudah ada di `player_seeker_z()`/`anima_behind_seeker()`.
const SEEKER_COLUMN_GAP_SCALE := 0.75
const SEEKER_REFERENCE_WIDTH_PX := 158.0
const SEEKER_REFERENCE_HEIGHT_PX := 282.0
## Sprite Anima duduk satu tingkat di atas anchor-nya (`z_as_relative` bawaan),
## jadi lantai depan figur pemain harus melewati anchor tertinggi yang pernah
## diberikan `_set_fighter_z` **berikut** sprite di atasnya — bukan anchor-nya
## saja.
const PLAYER_SEEKER_Z_BEHIND := 0
const PLAYER_SEEKER_Z_FRONT := 5
const BACKGROUND_PAN_EDGE_MARGIN := 0.04


static func anima_display_height_cm(body_height_cm: float) -> float:
	return minf(
		clampf(body_height_cm, BODY_HEIGHT_MIN_CM, BODY_HEIGHT_MAX_CM),
		ANIMA_VISUAL_HEIGHT_CAP_CM
	)


static func anima_behind_seeker(anima_height_cm: float, seeker_height_cm: float) -> bool:
	return (
		seeker_height_cm > 0.0
		and anima_display_height_cm(anima_height_cm) > seeker_height_cm * SEEKER_OVERLAP_RATIO
	)


## Lantai z figur Seeker pemain terhadap Anima-nya sendiri. Ambangnya sengaja
## `anima_behind_seeker()` yang sama dengan Boss Seeker: begitu Anima setinggi
## itu, figur di belakangnya kehilangan siluetnya, dan dua ambang untuk satu
## gagasan yang sama akan berpisah diam-diam.
static func player_seeker_z(anima_height_cm: float, seeker_height_cm: float) -> int:
	return (
		PLAYER_SEEKER_Z_FRONT
		if anima_behind_seeker(anima_height_cm, seeker_height_cm)
		else PLAYER_SEEKER_Z_BEHIND
	)


## Figur Seeker ditempatkan **setelah** kamera memutuskan zoom dan pusatnya:
## edge clamp menjaganya di viewport, companion clamp menjaganya tetap di samping
## Anima. Ini lebar kolom di ruang layer yang harus dicadangkan di sisi yang punya
## figur — badan opaknya plus dua pad, satu untuk tepi kamera dan satu untuk udara
## ke Anima terdekat.
##
## ponytail: pad-nya piksel layar dipakai apa adanya sebagai piksel layer.
## Plafonnya zoom arena 0,72–1,14, jadi selisihnya <=5 px pada stage 720; kalau
## rentang zoom melebar, ubah jadi pembagian dengan zoom yang sedang dipakai.
static func seeker_reserved_column(
	loaded: Dictionary, sprite_scale: float, stage_width: float
) -> float:
	if loaded.is_empty():
		return 0.0
	return (
		seeker_reference_width(loaded) * absf(sprite_scale)
		+ stage_width * SEEKER_CAMERA_EDGE_PAD_RATIO * 2.0
	) * SEEKER_COLUMN_GAP_SCALE


## Lebar badan Seeker yang benar-benar tergambar, dalam piksel sheet.
static func seeker_reference_width(loaded: Dictionary) -> float:
	return float(_metrics(loaded).get("reference_width_px", SEEKER_REFERENCE_WIDTH_PX))


## Tinggi badan Seeker yang benar-benar tergambar, dalam piksel sheet.
static func seeker_reference_height(loaded: Dictionary) -> float:
	return float(_metrics(loaded).get("reference_height_px", SEEKER_REFERENCE_HEIGHT_PX))


## Skala satu Seeker terhadap Seeker lain yang sudah diletakkan. Bbox sheet
## masing-masing dibatalkan dulu supaya rasio akhirnya hanya mengikuti tinggi
## dunia kanonis, bukan tinggi piksel atau padding transparan.
static func seeker_scale_relative_to(
	body_height_cm: float,
	loaded: Dictionary,
	reference_body_height_cm: float,
	reference_loaded: Dictionary,
	reference_scale: float
) -> float:
	var reference_body_px := (
		seeker_reference_height(reference_loaded) * absf(reference_scale)
	)
	return (
		reference_body_px
		* maxf(1.0, body_height_cm)
		/ maxf(1.0, reference_body_height_cm)
		/ maxf(1.0, seeker_reference_height(loaded))
	)


## Lebar sel sheet Seeker; padding transparannya tidak boleh ikut menentukan
## komposisi, jadi ia selalu dipasangkan dengan `seeker_opaque_center()`.
static func seeker_frame_width(loaded: Dictionary) -> float:
	var frame_value: Variant = loaded.get("frame_size", Vector2i(341, 341))
	if typeof(frame_value) == TYPE_VECTOR2I:
		return float((frame_value as Vector2i).x)
	if typeof(frame_value) == TYPE_VECTOR2:
		return (frame_value as Vector2).x
	return 341.0


## Jarak pusat badan yang benar-benar tergambar dari origin sprite, dalam piksel
## sheet. `flip_h` mencerminkan sel terhadap origin itu, jadi figur yang dibalik
## memakai angka yang sama dengan tanda terbalik.
static func seeker_opaque_center(loaded: Dictionary) -> float:
	var frame_w := seeker_frame_width(loaded)
	var width := seeker_reference_width(loaded)
	var min_x := float(_metrics(loaded).get("reference_min_x_px", (frame_w - width) * 0.5))
	return min_x + width * 0.5 - frame_w * 0.5


## Sesudah kamera memilih zoom-nya, pusat badan opak Seeker dijaga dari tepi
## viewport sekaligus tetap di samping Anima miliknya. Edge clamp mencegah
## clipping di layar sempit; companion clamp mencegah figur terlepas jauh ke
## ujung layar saat Battle Arena melebar di landscape.
##
## `companion_edge_x` berada di koordinat X stage: tepi kiri Anima untuk figur
## pemain yang `flipped`, atau tepi kanan Anima untuk Boss di sisi seberang.
static func seeker_pinned_x(
	loaded: Dictionary,
	sprite_scale: float,
	stage_width: float,
	layer_x: float,
	camera_zoom: float,
	flipped: bool,
	companion_edge_x: float
) -> float:
	var half_screen_width := (
		seeker_reference_width(loaded) * absf(sprite_scale) * camera_zoom * 0.5
	)
	var pad := stage_width * SEEKER_CAMERA_EDGE_PAD_RATIO
	var edge_center := (
		pad + half_screen_width if flipped
		else stage_width - pad - half_screen_width
	)
	var companion_center := (
		companion_edge_x - pad - half_screen_width if flipped
		else companion_edge_x + pad + half_screen_width
	)
	var target_center := (
		maxf(edge_center, companion_center) if flipped
		else minf(edge_center, companion_center)
	)
	var body := seeker_opaque_center(loaded) * absf(sprite_scale)
	return (target_center - layer_x) / camera_zoom + (body if flipped else -body)


static func background_pan_for_session(session_id: String) -> float:
	if session_id.is_empty():
		return 0.5
	var normalized := float(posmod(session_id.hash(), 10001)) / 10000.0
	return lerpf(BACKGROUND_PAN_EDGE_MARGIN, 1.0 - BACKGROUND_PAN_EDGE_MARGIN, normalized)


## Background dan petarung berbagi foot-contact line 91%. Zoom/crop boleh
## mengubah bagian langit yang terlihat, tetapi garis lantai sumber tidak boleh
## bergeser dari kaki. Tinggi minimum menjaga overscan impact di kedua tepi
## meski ground line dekat sekali dengan bagian bawah gambar.
static func background_draw_size(
	texture_size: Vector2,
	stage_size: Vector2,
	guard: float,
	geometry_zoom: float = 1.0
) -> Vector2:
	var safe_guard := maxf(0.0, guard)
	var guarded_size := stage_size + Vector2.ONE * safe_guard * 2.0
	var cover_scale := maxf(
		guarded_size.x / texture_size.x,
		guarded_size.y / texture_size.y
	)
	var draw_size := texture_size * cover_scale * maxf(1.0, geometry_zoom)
	var ground := clampf(GROUND_Y_RATIO, 0.001, 0.999)
	var minimum_height := maxf(
		(stage_size.y * ground + safe_guard) / ground,
		(stage_size.y * (1.0 - ground) + safe_guard) / (1.0 - ground)
	)
	if draw_size.y < minimum_height:
		draw_size *= minimum_height / draw_size.y
	return draw_size


static func grounded_background_y(stage_height: float, draw_height: float) -> float:
	return (stage_height - draw_height) * GROUND_Y_RATIO


static func usable_height(arena_size: Vector2) -> float:
	# Width must not change height. Extra vertical space above the design
	# card is background; a shorter arena is the only thing that shrinks.
	return minf(maxf(1.0, arena_size.y), DESIGN_ARENA.y)


static func fighter_scale(body_height_cm: float, loaded: Dictionary, arena_size: Vector2) -> float:
	var reference_height := _reference_size(loaded).y
	var arena_height := usable_height(arena_size)
	var clamped_height := clampf(body_height_cm, BODY_HEIGHT_MIN_CM, BODY_HEIGHT_MAX_CM)
	var height_ratio := clamped_height / BODY_HEIGHT_REFERENCE_CM
	var target_height := arena_height * ARENA_REFERENCE_HEIGHT_RATIO * pow(
		height_ratio, BODY_HEIGHT_CURVE
	)
	target_height = clampf(
		target_height,
		arena_height * ARENA_REFERENCE_HEIGHT_RATIO * 0.42,
		arena_height * 0.88
	)
	return target_height / reference_height


static func fighter_pair_scales(
	first_height_cm: float,
	first_loaded: Dictionary,
	second_height_cm: float,
	second_loaded: Dictionary,
	arena_size: Vector2
) -> Vector2:
	var scales := shared_scales(
		[first_height_cm, second_height_cm],
		[first_loaded, second_loaded],
		arena_size
	)
	return Vector2(scales[0], scales[1])


## Height follows the 720×800 design card; extra window height is background.
## Beside a Seeker, Anima height is linear to her on-screen height so 3 m is
## about 2× a 165 cm Seeker. A wide body still shrinks only the Animas.
static func shared_scales(
	heights: Array,
	loadeds: Array,
	arena_size: Vector2
) -> PackedFloat32Array:
	var count := mini(heights.size(), loadeds.size())
	var scales := PackedFloat32Array()
	scales.resize(count)
	var seeker_px := 0.0
	var seeker_cm := 0.0
	if count >= 3:
		var seeker_loaded: Dictionary = (
			loadeds[2] if typeof(loadeds[2]) == TYPE_DICTIONARY else {}
		)
		seeker_cm = float(heights[2])
		scales[2] = fighter_scale(seeker_cm, seeker_loaded, arena_size)
		seeker_px = _reference_size(seeker_loaded).y * scales[2]
	for index in count:
		if index == 2:
			continue
		var loaded: Dictionary = (
			loadeds[index] if typeof(loadeds[index]) == TYPE_DICTIONARY else {}
		)
		var height := anima_display_height_cm(float(heights[index])) if index < 2 else float(heights[index])
		if index < 2 and seeker_cm > 0.0 and seeker_px > 0.0:
			scales[index] = (seeker_px * (height / seeker_cm)) / _reference_size(loaded).y
		else:
			scales[index] = fighter_scale(height, loaded, arena_size)
	return scales


static func _metrics(loaded: Dictionary) -> Dictionary:
	var metrics: Variant = loaded.get("render_metrics", {})
	return metrics if typeof(metrics) == TYPE_DICTIONARY else {}


static func _reference_size(loaded: Dictionary) -> Vector2:
	var metrics := _metrics(loaded)
	var reference_height := maxf(1.0, float(metrics.get("reference_height_px", 300.0)))
	var reference_width := maxf(1.0, float(metrics.get("reference_width_px", reference_height)))
	return Vector2(reference_width, reference_height)
