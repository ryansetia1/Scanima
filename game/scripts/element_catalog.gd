class_name ElementCatalog
extends RefCounted

## Lapisan presentasi elemen: label dan teks bantuan. Elemen tidak punya ikon —
## delapan belas roster berarti delapan belas aset yang harus dijaga konsisten,
## sementara namanya sudah cukup di setiap layar yang menampilkannya. Roster
## serta alias dimiliki `ElementRules` supaya simulasi tidak perlu ikut menarik
## autoload `LocaleManager` yang dipakai di bawah.
const ROSTER: PackedStringArray = ElementRules.ROSTER
const ALIASES := ElementRules.ALIASES


static func normalize(code: String, fallback := "stone") -> String:
	var value := code.strip_edges().to_lower()
	if value in ROSTER:
		return value
	var aliased := str(ALIASES.get(value, ""))
	if not aliased.is_empty() and aliased in ROSTER:
		return aliased
	return fallback if fallback in ROSTER else "stone"


static func compact_label(row: Dictionary) -> String:
	var primary := normalize(str(row.get("element", "")))
	var secondary_raw := str(row.get("secondary_element", "")).strip_edges()
	if secondary_raw.is_empty() or int(row.get("typing_version", 1)) < 2:
		return LocaleManager.element_name(primary)
	var secondary := normalize(secondary_raw, "")
	if secondary.is_empty() or secondary == primary:
		return LocaleManager.element_name(primary)
	return TranslationServer.translate("ELEMENT_PAIR") % [
		LocaleManager.element_name(primary),
		LocaleManager.element_name(secondary),
	]


static func help_text(code: String) -> String:
	var key := "ELEMENT_%s_HELP" % normalize(code, "unknown").to_upper()
	var translated := TranslationServer.translate(key)
	return translated if translated != key else TranslationServer.translate("DETAILS_ELEMENT_HELP")
