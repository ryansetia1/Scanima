class_name BattleScale
extends RefCounted

const BODY_HEIGHT_REFERENCE_CM := 120.0
const BODY_HEIGHT_CURVE := 0.42
const BODY_HEIGHT_MIN_CM := 20.0
const BODY_HEIGHT_MAX_CM := 2000.0
const ARENA_REFERENCE_HEIGHT_RATIO := 0.50
const DESIGN_ARENA := Vector2(720.0, 800.0)


static func usable_height(arena_size: Vector2) -> float:
	# Width must not change height. Extra vertical space above the design
	# card is background; a shorter arena is the only thing that shrinks.
	return minf(maxf(1.0, arena_size.y), DESIGN_ARENA.y)


static func fighter_scale(body_height_cm: float, loaded: Dictionary, arena_size: Vector2) -> float:
	var reference_height := _reference_size(loaded).y
	var arena_height := usable_height(arena_size)
	var height_ratio := clampf(
		body_height_cm, BODY_HEIGHT_MIN_CM, BODY_HEIGHT_MAX_CM
	) / BODY_HEIGHT_REFERENCE_CM
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


## One world scale for every body in the shot. Height is locked to the
## 720×800 design card regardless of window width. Extra height is
## background; a shorter arena is the only shrink. A Boss Seeker after
## the pair uses the same curve so the trainer stays in proportion.
static func shared_scales(
	heights: Array,
	loadeds: Array,
	arena_size: Vector2
) -> PackedFloat32Array:
	var count := mini(heights.size(), loadeds.size())
	var scales := PackedFloat32Array()
	scales.resize(count)
	for index in count:
		var loaded: Dictionary = (
			loadeds[index] if typeof(loadeds[index]) == TYPE_DICTIONARY else {}
		)
		scales[index] = fighter_scale(float(heights[index]), loaded, arena_size)
	return scales


static func _reference_size(loaded: Dictionary) -> Vector2:
	var metrics_value: Variant = loaded.get("render_metrics", {})
	var metrics: Dictionary = metrics_value if typeof(metrics_value) == TYPE_DICTIONARY else {}
	var reference_height := maxf(1.0, float(metrics.get("reference_height_px", 300.0)))
	var reference_width := maxf(1.0, float(metrics.get("reference_width_px", reference_height)))
	return Vector2(reference_width, reference_height)
