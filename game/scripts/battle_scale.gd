class_name BattleScale
extends RefCounted

const BODY_HEIGHT_REFERENCE_CM := 120.0
const BODY_HEIGHT_CURVE := 0.42
const BODY_HEIGHT_MIN_CM := 20.0
const BODY_HEIGHT_MAX_CM := 2000.0
const ARENA_REFERENCE_HEIGHT_RATIO := 0.45
const DESIGN_ARENA := Vector2(720.0, 800.0)
const MAX_BODY_WIDTH_RATIO := 0.50
const SHOT_WIDTH_RATIO := 0.90
const PLAYER_SHOT_X := 0.27
const OPPONENT_SHOT_X := 0.73
const GROUND_Y_RATIO := 0.91
const FIGHTER_EDGE_PAD_RATIO := 0.055


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


## Height follows the 720×800 design card; extra window height is background.
## A wide body shrinks both Animas together to fit the 720-wide card. The
## Seeker occupies a separate back lane, so Anima width must not shrink her.
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
	return _fit_shot(scales, loadeds)


# ponytail: Camera2D zoom-to-fit without a camera. Ceiling: uses the 720-wide
# design card, not the window. Upgrade to a real Camera2D if the arena leaves Control.
static func _fit_shot(scales: PackedFloat32Array, loadeds: Array) -> PackedFloat32Array:
	var count := scales.size()
	if count == 0:
		return scales
	var widths := PackedFloat32Array()
	widths.resize(count)
	var max_width := 0.0
	for index in count:
		var loaded: Dictionary = (
			loadeds[index] if index < loadeds.size() and typeof(loadeds[index]) == TYPE_DICTIONARY else {}
		)
		widths[index] = _reference_size(loaded).x * scales[index]
		max_width = maxf(max_width, widths[index])
	var fit := 1.0
	var max_body := DESIGN_ARENA.x * MAX_BODY_WIDTH_RATIO
	if max_width > max_body:
		fit = minf(fit, max_body / max_width)
	if count >= 2:
		var left := DESIGN_ARENA.x * PLAYER_SHOT_X - widths[0] * 0.5
		var right := DESIGN_ARENA.x * OPPONENT_SHOT_X + widths[1] * 0.5
		var span := right - left
		var budget := DESIGN_ARENA.x * SHOT_WIDTH_RATIO
		if span > budget:
			fit = minf(fit, budget / span)
	if fit < 1.0:
		for index in mini(count, 2):
			scales[index] *= fit
	return scales


static func fighter_anchor_x(is_player: bool, opaque_width: float, arena_width: float) -> float:
	var fallback := arena_width * (PLAYER_SHOT_X if is_player else OPPONENT_SHOT_X)
	if opaque_width <= 0.0 or arena_width <= 0.0:
		return fallback
	var pad := arena_width * FIGHTER_EDGE_PAD_RATIO
	return pad + opaque_width * 0.5 if is_player else arena_width - pad - opaque_width * 0.5


static func _reference_size(loaded: Dictionary) -> Vector2:
	var metrics_value: Variant = loaded.get("render_metrics", {})
	var metrics: Dictionary = metrics_value if typeof(metrics_value) == TYPE_DICTIONARY else {}
	var reference_height := maxf(1.0, float(metrics.get("reference_height_px", 300.0)))
	var reference_width := maxf(1.0, float(metrics.get("reference_width_px", reference_height)))
	return Vector2(reference_width, reference_height)
