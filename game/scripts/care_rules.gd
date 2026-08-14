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
const PLAY_SCORE_DAILY_CAP := 5
const BATTLE_ENERGY_COST := 20.0
const SLEEP_FULL_HOURS := 6.0
const BENCH_SLEEP_FULL_HOURS := 3.0
const DORMANT_RECOVERY_NEED := 50.0
const HUNGRY_POSE_NEED := 40.0
const BATTLE_MIN_HUNGER := HUNGRY_POSE_NEED
const DIRTY_POSE_NEED := 50.0
const NEED_FULL_AT := 99.5
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
	sleep_energy_at_start: float = -1.0,
	sleep_full_hours: float = -1.0
) -> Dictionary:
	var care := normalized_care(care_value)
	var hours := effective_decay_hours(synced_at, now)
	care["hunger"] = clampf(care["hunger"] - DECAY_PER_HOUR.hunger * hours, 0.0, 100.0)
	care["hygiene"] = clampf(care["hygiene"] - DECAY_PER_HOUR.hygiene * hours, 0.0, 100.0)

	if sleep_started_at > 0.0:
		var start_energy: float = (
			float(care["energy"]) if sleep_energy_at_start < 0.0 else sleep_energy_at_start
		)
		var hours_to_full := SLEEP_FULL_HOURS if sleep_full_hours <= 0.0 else sleep_full_hours
		var sleep_fraction := clampf((now - sleep_started_at) / 3600.0 / hours_to_full, 0.0, 1.0)
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
			return 1 if play_score_today < PLAY_SCORE_DAILY_CAP else 0
		_:
			return 0


static func need_is_full(care_value: Variant, need: String) -> bool:
	var care := normalized_care(care_value)
	return float(care.get(need, 0.0)) >= NEED_FULL_AT


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


static func has_timestamp(value: Variant) -> bool:
	if value == null:
		return false
	var text := str(value).strip_edges()
	return not text.is_empty() and text != "<null>"


static func timestamp_seconds(value: Variant) -> float:
	if not has_timestamp(value):
		return -1.0
	return float(Time.get_unix_time_from_datetime_string(str(value)))


static func projected_care(row: Dictionary, active_id: String = "", now: float = -1.0) -> Dictionary:
	var clock := now if now >= 0.0 else Time.get_unix_time_from_system()
	var synced := timestamp_seconds(row.get("care_synced_at"))
	if synced <= 0.0:
		return normalized_care(row.get("care"))
	var sleep_started := timestamp_seconds(row.get("sleep_started_at"))
	if sleep_started <= 0.0:
		return apply_decay(row.get("care"), synced, clock)
	var start_energy := float(row.get("sleep_energy_at_start", -1.0))
	var hours_to_full := (
		SLEEP_FULL_HOURS if str(row.get("id", "")) == active_id else BENCH_SLEEP_FULL_HOURS
	)
	return apply_decay(row.get("care"), synced, clock, sleep_started, start_energy, hours_to_full)


static func collection_pose(row: Dictionary, active_id: String, now: float = -1.0) -> String:
	if has_timestamp(row.get("dormant_since")):
		return "defeated"
	# Energy penuh = Idle, termasuk yang masih ditandai tidur di bangku. Server
	# menahan sleep supaya Energy tidak luruh dan tidak ada +5 EXP; pose bangun
	# adalah sinyal siap Summon. Jangan baca care.energy mentah: row roster
	# menyimpan nilai saat sync terakhir, jadi tidur yang sudah pulih tetap
	# terlihat Sleep sampai tap memicu apply_care.
	if need_is_full(projected_care(row, active_id, now), "energy"):
		return "idle"
	if str(row.get("id", "")) != active_id or has_timestamp(row.get("sleep_started_at")):
		return "sleep"
	return "idle"


static func is_hungry(care_value: Variant) -> bool:
	return normalized_care(care_value)["hunger"] < BATTLE_MIN_HUNGER


static func visual_pose(sleeping: bool, dormant: bool, care_value: Variant = {}) -> String:
	if dormant:
		return "defeated"
	if sleeping:
		return "sleep"
	var care := normalized_care(care_value)
	if care["hunger"] < HUNGRY_POSE_NEED:
		return "hungry"
	if care["hygiene"] < DIRTY_POSE_NEED:
		return "dirty"
	return "idle"


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


static func play_exp_used(row: Dictionary, today: String = "") -> int:
	var used_on := _utc_date(row.get("play_score_on"))
	var current := today if not today.is_empty() else local_today_string()
	if used_on.is_empty() or used_on != current:
		return 0
	return clampi(int(row.get("play_score_today", 0)), 0, PLAY_SCORE_DAILY_CAP)


static func play_exp_remaining(row: Dictionary, today: String = "") -> int:
	return PLAY_SCORE_DAILY_CAP - play_exp_used(row, today)


static func local_today_string() -> String:
	var date := Time.get_date_dict_from_system(false)
	return "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]


static func _utc_date(value: Variant) -> String:
	if value == null:
		return ""
	var text := str(value)
	return text.substr(0, 10) if text.length() >= 10 and text[0] >= "0" and text[0] <= "9" else ""


static func leveled_up(before: int, after: int) -> int:
	var new_level := level_from_exp(after)
	return new_level if new_level > level_from_exp(before) else 0
