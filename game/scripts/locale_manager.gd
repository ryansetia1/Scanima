extends Node

signal locale_changed(locale: String)

const DEFAULT_LOCALE := "en"
const SUPPORTED_LOCALES := ["en"]

var current_locale: String = DEFAULT_LOCALE


func _ready() -> void:
	var requested := DEFAULT_LOCALE
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--locale="):
			requested = argument.trim_prefix("--locale=")
			break
	set_locale(requested)


func set_locale(locale: String) -> void:
	var normalized := locale.to_lower().replace("-", "_").get_slice("_", 0)
	if not SUPPORTED_LOCALES.has(normalized):
		normalized = DEFAULT_LOCALE
	if normalized == current_locale and TranslationServer.get_locale() == normalized:
		return
	current_locale = normalized
	TranslationServer.set_locale(current_locale)
	locale_changed.emit(current_locale)


func text(key: StringName) -> String:
	return tr(key)


func format_integer(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	grouped = digits + grouped
	return "-" + grouped if value < 0 else grouped


func format_decimal(value: float, decimals: int = 1) -> String:
	return String.num(value, decimals)


func format_percent(value: float) -> String:
	return tr("FORMAT_PERCENT") % format_integer(roundi(value))


func format_megabytes(bytes: int) -> String:
	return tr("FORMAT_MEGABYTES") % format_decimal(float(bytes) / 1048576.0)


func format_ratio(value: int, total: int) -> String:
	return tr("FORMAT_RATIO") % [format_integer(value), format_integer(total)]


func element_name(code: String) -> String:
	var key := "ELEMENT_%s" % code.to_upper()
	var translated := tr(key)
	return translated if translated != key else tr("ELEMENT_UNKNOWN")


func stage_name(stage: int) -> String:
	var key := "STAGE_%d" % stage
	var translated := tr(key)
	return translated if translated != key else format_integer(stage)


func gate_reason(code: String) -> String:
	var key := "GATE_%s" % code.to_upper()
	var translated := tr(key)
	return translated if translated != key else tr("GATE_UNKNOWN")


func care_state(sleeping: bool, dormant: bool) -> String:
	if dormant:
		return tr("CARE_STATE_DORMANT")
	if sleeping:
		return tr("CARE_STATE_SLEEPING")
	return tr("CARE_STATE_ACTIVE")


func display_name(row: Dictionary) -> String:
	var nickname := str(row.get("nickname", "")).strip_edges()
	if not nickname.is_empty():
		return nickname
	var species := str(row.get("species_key", "")).replace("_", " ").strip_edges()
	return species.capitalize() if not species.is_empty() else tr("ANIMA_FALLBACK_NAME")
