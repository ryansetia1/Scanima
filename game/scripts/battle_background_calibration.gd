class_name BattleBackgroundCalibration
extends RefCounted

const MODE_DUEL := &"duel"
const MODE_TEAM := &"team"
const DEFAULT_PROFILE := {
	"offset_ratio": Vector2.ZERO,
	"zoom_multiplier": 1.0,
	"pivot_y": BattleScale.GROUND_Y_RATIO,
	"source_foot_y": BattleScale.GROUND_Y_RATIO,
	"fighter_offset_ratio_y": 0.0,
}
const PORTRAIT_PROFILE := {
	"offset_ratio": Vector2(0.0, 100.0 / 1602.0),
	"zoom_multiplier": 1.0,
	"pivot_y": BattleScale.GROUND_Y_RATIO,
	"source_foot_y": BattleScale.GROUND_Y_RATIO,
	"fighter_offset_ratio_y": -117.0 / 1602.0,
}
const LANDSCAPE_PROFILE := {
	"offset_ratio": Vector2(0.0, 5.0 / 720.0),
	"zoom_multiplier": 1.0,
	"pivot_y": BattleScale.GROUND_Y_RATIO,
	"source_foot_y": BattleScale.GROUND_Y_RATIO,
	"fighter_offset_ratio_y": -113.0 / 720.0,
}
const MAX_AUTO_COVER_OFFSET_RATIO := 0.075
## The tuner exports this complete dictionary. Production reads it on every
## layout pass, while debug previews may provide a normalized working copy.
const PROFILES := {
	"duel_landscape": LANDSCAPE_PROFILE,
	"duel_portrait": PORTRAIT_PROFILE,
	"team_landscape": LANDSCAPE_PROFILE,
	"team_portrait": PORTRAIT_PROFILE,
}


static func canonical_profiles() -> Dictionary:
	return PROFILES.duplicate(true)


static func profile_key(mode: StringName, stage_size: Vector2) -> String:
	var orientation := "landscape" if stage_size.x > stage_size.y else "portrait"
	return "%s_%s" % [String(mode), orientation]


static func profile_for(
	mode: StringName, stage_size: Vector2, profiles: Dictionary = {}
) -> Dictionary:
	var key := profile_key(mode, stage_size)
	var fallback: Dictionary = PROFILES.get(key, DEFAULT_PROFILE)
	var source := PROFILES if profiles.is_empty() else profiles
	return normalize_profile(source.get(key, fallback), fallback)


static func normalize_profiles(value: Variant) -> Dictionary:
	var source: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var normalized := {}
	for key: String in PROFILES:
		normalized[key] = normalize_profile(source.get(key, PROFILES[key]), PROFILES[key])
	return normalized


static func normalize_profile(
	value: Variant, fallback: Dictionary = DEFAULT_PROFILE
) -> Dictionary:
	var source: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var fallback_offset: Vector2 = fallback.get("offset_ratio", Vector2.ZERO)
	return {
		"offset_ratio": _offset_ratio(source.get("offset_ratio", fallback_offset), fallback_offset),
		"zoom_multiplier": _finite_float(
			source.get("zoom_multiplier"), float(fallback.get("zoom_multiplier", 1.0))
		),
		"pivot_y": _finite_float(
			source.get("pivot_y"), float(fallback.get("pivot_y", BattleScale.GROUND_Y_RATIO))
		),
		"source_foot_y": _finite_float(
			source.get("source_foot_y"),
			float(fallback.get("source_foot_y", BattleScale.GROUND_Y_RATIO))
		),
		"fighter_offset_ratio_y": _finite_float(
			source.get("fighter_offset_ratio_y"),
			float(fallback.get("fighter_offset_ratio_y", 0.0))
		),
	}


static func background_position(
	stage_size: Vector2,
	draw_size: Vector2,
	horizontal_pan: float,
	profile: Dictionary
) -> Vector2:
	var normalized := normalize_profile(profile)
	var offset_ratio: Vector2 = normalized["offset_ratio"]
	var overflow_x := maxf(0.0, draw_size.x - stage_size.x)
	return Vector2(
		-overflow_x * horizontal_pan,
		stage_size.y * BattleScale.GROUND_Y_RATIO
			- draw_size.y * float(normalized["source_foot_y"]),
	) + offset_ratio * stage_size


static func camera_zoom(base_zoom: float, profile: Dictionary) -> float:
	return maxf(0.001, base_zoom * float(normalize_profile(profile)["zoom_multiplier"]))


static func camera_offset(
	base_offset: float, effective_zoom: float, profile: Dictionary
) -> float:
	var normalized := normalize_profile(profile)
	var safe_zoom := maxf(0.001, effective_zoom)
	return base_offset + (
		float(normalized["source_foot_y"]) - float(normalized["pivot_y"])
	) * (1.0 - 1.0 / safe_zoom)


static func fighter_offset_y(stage_size: Vector2, profile: Dictionary) -> float:
	return stage_size.y * float(normalize_profile(profile)["fighter_offset_ratio_y"])


## A small positive Y calibration consumes nearly all portrait top overscan
## because the source floor sits at 91%. Add only the sub-pixel guard needed to
## preserve impact shake without changing the visible camera zoom.
static func vertical_cover_guard(
	stage_size: Vector2, guard: float, profile: Dictionary
) -> float:
	var safe_guard := maxf(0.0, guard)
	var offset_ratio: Vector2 = normalize_profile(profile)["offset_ratio"]
	if absf(offset_ratio.y) > MAX_AUTO_COVER_OFFSET_RATIO:
		return safe_guard
	var offset_y := stage_size.y * offset_ratio.y
	if offset_y < 0.0:
		return safe_guard - offset_y
	var ground := clampf(BattleScale.GROUND_Y_RATIO, 0.001, 0.999)
	var existing_top := safe_guard * ground / (1.0 - ground)
	var missing_top := maxf(0.0, offset_y + safe_guard - existing_top)
	return safe_guard + missing_top * (1.0 - ground) / ground


## Save/Copy uses one conservative geometry check for the full profile matrix.
## Each opening/gameplay and fighter-size base zoom is composed with the profile;
## the same effective zoom expands the backdrop rect and narrows the shader sample.
## That spare cover crop is what makes a non-zero pan safe to keep.
static func profile_is_safe(
	stage_size: Vector2,
	texture_size: Vector2,
	guard: float,
	base_zooms: Array,
	profile: Dictionary
) -> bool:
	if stage_size.x <= 0.0 or stage_size.y <= 0.0:
		return false
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return false
	var normalized := normalize_profile(profile)
	var offset_ratio: Vector2 = normalized["offset_ratio"]
	var zoom_multiplier := float(normalized["zoom_multiplier"])
	var pivot_y := float(normalized["pivot_y"])
	var source_foot_y := float(normalized["source_foot_y"])
	var fighter_offset_ratio_y := float(normalized["fighter_offset_ratio_y"])
	if not (
		is_finite(offset_ratio.x)
		and is_finite(offset_ratio.y)
		and is_finite(zoom_multiplier)
		and is_finite(pivot_y)
		and is_finite(source_foot_y)
		and is_finite(fighter_offset_ratio_y)
	):
		return false
	if zoom_multiplier <= 0.0 or not (pivot_y >= 0.0 and pivot_y <= 1.0):
		return false
	if source_foot_y < 0.0 or source_foot_y > 1.0:
		return false
	var safe_guard := maxf(0.0, guard)
	var cover_guard := vertical_cover_guard(stage_size, safe_guard, normalized)
	for value: Variant in base_zooms:
		var effective_zoom := camera_zoom(float(value), normalized)
		if effective_zoom < 1.0:
			return false
		var draw_size := BattleScale.background_draw_size(
			texture_size, stage_size, cover_guard, effective_zoom
		)
		var position := background_position(stage_size, draw_size, 0.5, normalized)
		if not (
			position.x <= -safe_guard + 0.01
			and position.y <= -safe_guard + 0.01
			and position.x + draw_size.x >= stage_size.x + safe_guard - 0.01
			and position.y + draw_size.y >= stage_size.y + safe_guard - 0.01
		):
			return false
	return true


static func profiles_to_json(profiles: Dictionary) -> String:
	return JSON.stringify(_plain_profiles(normalize_profiles(profiles)), "\t")


static func profiles_from_json(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return canonical_profiles()
	return normalize_profiles(parser.data)


static func gdscript_snippet(profiles: Dictionary) -> String:
	var normalized := normalize_profiles(profiles)
	var lines := PackedStringArray(["const PROFILES := {"])
	for key: String in PROFILES:
		var profile: Dictionary = normalized[key]
		var offset: Vector2 = profile["offset_ratio"]
		lines.append("\t\"%s\": {" % key)
		lines.append(
			"\t\t\"offset_ratio\": Vector2(%s, %s),"
			% [String.num(offset.x, 6), String.num(offset.y, 6)]
		)
		lines.append(
			"\t\t\"zoom_multiplier\": %s," % String.num(profile["zoom_multiplier"], 6)
		)
		lines.append("\t\t\"pivot_y\": %s," % String.num(profile["pivot_y"], 6))
		lines.append(
			"\t\t\"source_foot_y\": %s," % String.num(profile["source_foot_y"], 6)
		)
		lines.append(
			"\t\t\"fighter_offset_ratio_y\": %s,"
			% String.num(profile["fighter_offset_ratio_y"], 6)
		)
		lines.append("\t},")
	lines.append("}")
	return "\n".join(lines)


static func _plain_profiles(profiles: Dictionary) -> Dictionary:
	var plain := {}
	for key: String in PROFILES:
		var profile: Dictionary = profiles[key]
		var offset: Vector2 = profile["offset_ratio"]
		plain[key] = {
			"offset_ratio": [offset.x, offset.y],
			"zoom_multiplier": profile["zoom_multiplier"],
			"pivot_y": profile["pivot_y"],
			"source_foot_y": profile["source_foot_y"],
			"fighter_offset_ratio_y": profile["fighter_offset_ratio_y"],
		}
	return plain


static func _offset_ratio(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if typeof(value) == TYPE_VECTOR2:
		return value as Vector2
	if typeof(value) == TYPE_VECTOR2I:
		return Vector2(value as Vector2i)
	if typeof(value) == TYPE_ARRAY:
		var array := value as Array
		if array.size() >= 2:
			return Vector2(
				_finite_float(array[0], fallback.x), _finite_float(array[1], fallback.y)
			)
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary := value as Dictionary
		return Vector2(
			_finite_float(dictionary.get("x"), fallback.x),
			_finite_float(dictionary.get("y"), fallback.y)
		)
	return fallback


static func _finite_float(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return fallback
	var number := float(value)
	return number if is_finite(number) else fallback
