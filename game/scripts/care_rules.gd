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
	"hunger": 4.0,
	"energy": 7.1,
	"hygiene": 4.2,
}
const BENCH_DECAY_PER_HOUR := {
	"hunger": 1.0,
	"hygiene": 1.05,
}
const BENCH_HUNGER_FLOOR := 40.0
const BENCH_HYGIENE_FLOOR := 50.0
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
const EXP_MAX := 860
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


# Hold at floor only when already at/above it. Never raise a neglected bench.
static func _decayed_need(current: float, rate: float, hours: float, hold_floor: float) -> float:
	var next := current - rate * hours
	if current >= hold_floor:
		return clampf(next, hold_floor, 100.0)
	return clampf(next, 0.0, 100.0)


static func apply_decay(
	care_value: Variant,
	synced_at: float,
	now: float,
	sleep_started_at: float = 0.0,
	sleep_energy_at_start: float = -1.0,
	sleep_full_hours: float = -1.0,
	benched: bool = false
) -> Dictionary:
	var care := normalized_care(care_value)
	var hours := effective_decay_hours(synced_at, now)
	var hunger_rate: float = BENCH_DECAY_PER_HOUR.hunger if benched else DECAY_PER_HOUR.hunger
	var hygiene_rate: float = BENCH_DECAY_PER_HOUR.hygiene if benched else DECAY_PER_HOUR.hygiene
	care["hunger"] = _decayed_need(
		float(care["hunger"]), hunger_rate, hours, BENCH_HUNGER_FLOOR if benched else 0.0
	)
	care["hygiene"] = _decayed_need(
		float(care["hygiene"]), hygiene_rate, hours, BENCH_HYGIENE_FLOOR if benched else 0.0
	)

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


static func score_for_action(
	action: String,
	care_before: Variant,
	play_score_today: int = 0,
	restore: float = CARE_RESTORE
) -> int:
	var care := normalized_care(care_before)
	match action:
		"feed":
			return 3 if care["hunger"] < 40.0 and minf(100.0, care["hunger"] + restore) >= 40.0 else 0
		"clean":
			return 3 if care["hygiene"] < 50.0 else 0
		"play":
			return 1 if play_score_today < PLAY_SCORE_DAILY_CAP else 0
		_:
			return 0


static func need_is_full(care_value: Variant, need: String) -> bool:
	var care := normalized_care(care_value)
	return float(care.get(need, 0.0)) >= NEED_FULL_AT


static func enters_dormant(
	care_value: Variant,
	effective_hours: float,
	benched: bool = false
) -> bool:
	if benched:
		return false
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
	var is_benched := not active_id.is_empty() and str(row.get("id", "")) != active_id
	var sleep_started := timestamp_seconds(row.get("sleep_started_at"))
	if sleep_started <= 0.0:
		return apply_decay(row.get("care"), synced, clock, 0.0, -1.0, -1.0, is_benched)
	var start_energy := float(row.get("sleep_energy_at_start", -1.0))
	var hours_to_full := (
		SLEEP_FULL_HOURS if str(row.get("id", "")) == active_id else BENCH_SLEEP_FULL_HOURS
	)
	return apply_decay(
		row.get("care"), synced, clock, sleep_started, start_energy, hours_to_full, is_benched
	)


static func collection_pose(row: Dictionary, active_id: String, now: float = -1.0) -> String:
	if has_timestamp(row.get("dormant_since")):
		return "defeated"
	# Energy penuh = bangun di kartu, termasuk bangku yang server masih tandai
	# tidur. Jangan baca care.energy mentah: row roster adalah nilai sync
	# terakhir. Sesudah bangun, Hungry/Dirty harus kelihatan sekilas.
	var projected := projected_care(row, active_id, now)
	if not need_is_full(projected, "energy"):
		if str(row.get("id", "")) != active_id or has_timestamp(row.get("sleep_started_at")):
			return "sleep"
	return visual_pose(false, false, projected)


static func battle_unavailable_key(
	row: Dictionary,
	active_id: String = "",
	picking: bool = false,
	now: float = -1.0
) -> String:
	if row.is_empty():
		return "BATTLE_NO_ANIMA"
	if str(row.get("status", "")) != "ready":
		return "BATTLE_ANIMA_NOT_READY"
	if has_timestamp(row.get("dormant_since")):
		return "BATTLE_ANIMA_DORMANT"
	var is_active := not active_id.is_empty() and str(row.get("id", "")) == active_id
	if has_timestamp(row.get("sleep_started_at")) and (not picking or is_active):
		return "BATTLE_ANIMA_SLEEPING"
	# Hunger is a care pose, not a Battle lock. Bits come from Battle; food
	# costs Bits. Gating the faucet on the sink soft-locks 0 Bits + empty bag.
	if picking:
		var projected := projected_care(row, active_id, now)
		if float(projected.get("energy", 0.0)) < BATTLE_ENERGY_COST:
			return "BATTLE_ANIMA_LOW_ENERGY"
		return ""
	var stored: Variant = row.get("care")
	if typeof(stored) != TYPE_DICTIONARY or (stored as Dictionary).is_empty():
		return ""
	if float((stored as Dictionary).get("energy", 0.0)) < BATTLE_ENERGY_COST:
		return "BATTLE_ANIMA_LOW_ENERGY"
	return ""


static func battle_pick_reason_key(unavailable_key: String) -> String:
	match unavailable_key:
		"BATTLE_ANIMA_HUNGRY":
			return "BATTLE_PICK_HUNGRY"
		"BATTLE_ANIMA_LOW_ENERGY":
			return "BATTLE_PICK_LOW_ENERGY"
		"BATTLE_ANIMA_SLEEPING":
			return "BATTLE_PICK_SLEEPING"
		"BATTLE_ANIMA_DORMANT":
			return "BATTLE_PICK_DORMANT"
		"BATTLE_ANIMA_NOT_READY":
			return "BATTLE_PICK_NOT_READY"
		_:
			return unavailable_key


static func is_hungry(care_value: Variant) -> bool:
	return need_is_low(care_value, "hunger")


static func need_is_low(care_value: Variant, need: String) -> bool:
	var care := normalized_care(care_value)
	match need:
		"hunger":
			return care["hunger"] < HUNGRY_POSE_NEED
		"hygiene":
			return care["hygiene"] < DIRTY_POSE_NEED
		"energy":
			return care["energy"] < BATTLE_ENERGY_COST
		_:
			return false


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


static func exp_to_next_level(level: int) -> int:
	var lv := clampi(level, 1, LEVEL_CAP)
	return 0 if lv >= LEVEL_CAP else EXP_PER_LEVEL * ceili(float(lv) / 5.0)


static func exp_for_level(level: int) -> int:
	var steps := clampi(level, 1, LEVEL_CAP) - 1
	var complete_bands := floori(float(steps) / 5.0)
	var remaining_steps := steps % 5
	return (
		EXP_PER_LEVEL * 5 * complete_bands * (complete_bands + 1) / 2
		+ remaining_steps * EXP_PER_LEVEL * (complete_bands + 1)
	)


static func level_from_exp(total_exp: int) -> int:
	var value := maxi(0, total_exp)
	for level in range(LEVEL_CAP, 1, -1):
		if value >= exp_for_level(level):
			return level
	return 1


static func exp_into_level(total_exp: int) -> int:
	var level := level_from_exp(total_exp)
	if level >= LEVEL_CAP:
		return 0
	return maxi(0, total_exp) - exp_for_level(level)


static func exp_progress(total_exp: int) -> float:
	var level := level_from_exp(total_exp)
	if level >= LEVEL_CAP:
		return 100.0
	return float(exp_into_level(total_exp)) / float(exp_to_next_level(level)) * 100.0


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


static func grown_stat(base_value: Variant, total_exp: int) -> int:
	return int(float(base_value) * growth_multiplier(level_from_exp(total_exp)))


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
