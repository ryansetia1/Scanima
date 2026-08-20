class_name LocalDaylight
extends RefCounted

const SECONDS_PER_HOUR := 3600.0
const DAWN_START_SEC := 5.5 * SECONDS_PER_HOUR
const DAWN_END_SEC := 6.5 * SECONDS_PER_HOUR
const DUSK_START_SEC := 17.5 * SECONDS_PER_HOUR
const DUSK_END_SEC := 18.5 * SECONDS_PER_HOUR


static func daylight_blend(hour: int = -1, minute: int = -1, second: int = -1) -> float:
	if hour < 0:
		var local_time := Time.get_time_dict_from_system()
		hour = int(local_time.get("hour", 0))
		minute = int(local_time.get("minute", 0))
		second = int(local_time.get("second", 0))
	else:
		minute = maxi(0, minute)
		second = maxi(0, second)
	var local_seconds := (
		float(hour) * SECONDS_PER_HOUR
		+ float(minute * 60)
		+ float(second)
	)
	if local_seconds < DAWN_START_SEC or local_seconds >= DUSK_END_SEC:
		return 0.0
	if local_seconds < DAWN_END_SEC:
		return smoothstep(DAWN_START_SEC, DAWN_END_SEC, local_seconds)
	if local_seconds < DUSK_START_SEC:
		return 1.0
	return 1.0 - smoothstep(DUSK_START_SEC, DUSK_END_SEC, local_seconds)
