class_name CareRules
extends RefCounted

## Pure mirror aturan care server. Postgres tetap sumber kebenaran; fungsi ini
## dipakai untuk preview UI dan test headless supaya angka produk tidak tersebar
## sebagai magic number di scan_flow.gd.

const DEFAULT_CARE := {
	"hunger": 100.0,
	"energy": 100.0,
	"hygiene": 100.0,
	"bond": 0.0,
}
const DECAY_PER_HOUR := {
	"hunger": 10.0,
	"energy": 7.1,
	"hygiene": 4.2,
}
const MAX_DECAY_HOURS := 48.0
const CARE_RESTORE := 35.0
const PLAY_ENERGY_COST := 5.0
const BATTLE_ENERGY_COST := 20.0
const SLEEP_FULL_HOURS := 6.0
const DORMANT_RECOVERY_NEED := 50.0
const LEVEL_CAP := 40
const EXP_PER_LEVEL := 5
const ADULT_LEVEL := 16
const EVOLVED_LEVEL := 36


static func normalized_care(value: Variant) -> Dictionary:
	var source: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var care := DEFAULT_CARE.duplicate(true)
	for need in care:
		care[need] = clampf(float(source.get(need, care[need])), 0.0, 100.0)
	return care


static func effective_decay_hours(synced_at: float, now: float) -> float:
	var elapsed := maxf(0.0, (now - synced_at) / 3600.0)
	return minf(MAX_DECAY_HOURS, elapsed)


static func apply_decay(
	care_value: Variant,
	synced_at: float,
	now: float,
	sleep_started_at: float = 0.0,
	sleep_energy_at_start: float = -1.0
) -> Dictionary:
	var care := normalized_care(care_value)
	var hours := effective_decay_hours(synced_at, now)
	care["hunger"] = clampf(care["hunger"] - DECAY_PER_HOUR.hunger * hours, 0.0, 100.0)
	care["hygiene"] = clampf(care["hygiene"] - DECAY_PER_HOUR.hygiene * hours, 0.0, 100.0)

	if sleep_started_at > 0.0:
		var start_energy: float = (
			float(care["energy"]) if sleep_energy_at_start < 0.0 else sleep_energy_at_start
		)
		var sleep_fraction := clampf((now - sleep_started_at) / 3600.0 / SLEEP_FULL_HOURS, 0.0, 1.0)
		care["energy"] = lerpf(start_energy, 100.0, sleep_fraction)
	else:
		care["energy"] = clampf(care["energy"] - DECAY_PER_HOUR.energy * hours, 0.0, 100.0)

	care["bond"] = 0.0
	return care


static func score_for_action(action: String, care_before: Variant, play_score_today: int = 0) -> int:
	var care := normalized_care(care_before)
	match action:
		"feed":
			return 3 if care["hunger"] < 40.0 else 0
		"clean":
			return 3 if care["hygiene"] < 50.0 else 0
		"play":
			return 1 if play_score_today < 5 else 0
		_:
			return 0


static func enters_dormant(care_value: Variant, effective_hours: float) -> bool:
	var care := normalized_care(care_value)
	return (
		effective_hours >= MAX_DECAY_HOURS
		and care["hunger"] <= 0.0
		and care["hygiene"] <= 0.0
	)


static func can_recover_from_dormant(care_value: Variant) -> bool:
	var care := normalized_care(care_value)
	return care["hunger"] >= DORMANT_RECOVERY_NEED and care["hygiene"] >= DORMANT_RECOVERY_NEED


static func level_from_exp(exp: int) -> int:
	return clampi(1 + int(maxi(0, exp) / EXP_PER_LEVEL), 1, LEVEL_CAP)


static func exp_into_level(exp: int) -> int:
	if level_from_exp(exp) >= LEVEL_CAP:
		return EXP_PER_LEVEL
	return maxi(0, exp) % EXP_PER_LEVEL


static func exp_progress(exp: int) -> float:
	if level_from_exp(exp) >= LEVEL_CAP:
		return 100.0
	return float(exp_into_level(exp)) / float(EXP_PER_LEVEL) * 100.0


static func form_key(level: int) -> String:
	var lv := clampi(level, 1, LEVEL_CAP)
	if lv >= EVOLVED_LEVEL:
		return "evolved"
	if lv >= ADULT_LEVEL:
		return "adult"
	return "hatchling"


static func growth_multiplier(level: int) -> float:
	var lv := clampi(level, 1, LEVEL_CAP)
	var mult := 1.0 + 0.02 * float(lv - 1)
	if lv >= ADULT_LEVEL:
		mult += 0.15
	if lv >= EVOLVED_LEVEL:
		mult += 0.20
	return mult


static func grown_stat(base_value: Variant, exp: int) -> int:
	return int(float(base_value) * growth_multiplier(level_from_exp(exp)))
