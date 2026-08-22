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
const BACKGROUND_PAN_EDGE_MARGIN := 0.04
const STATIC_BACKGROUND_VERTICAL_PAN := 0.88


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


static func background_pan_for_session(session_id: String) -> float:
	if session_id.is_empty():
		return 0.5
	var normalized := float(posmod(session_id.hash(), 10001)) / 10000.0
	return lerpf(BACKGROUND_PAN_EDGE_MARGIN, 1.0 - BACKGROUND_PAN_EDGE_MARGIN, normalized)


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


static func _reference_size(loaded: Dictionary) -> Vector2:
	var metrics_value: Variant = loaded.get("render_metrics", {})
	var metrics: Dictionary = metrics_value if typeof(metrics_value) == TYPE_DICTIONARY else {}
	var reference_height := maxf(1.0, float(metrics.get("reference_height_px", 300.0)))
	var reference_width := maxf(1.0, float(metrics.get("reference_width_px", reference_height)))
	return Vector2(reference_width, reference_height)
