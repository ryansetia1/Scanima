class_name ElementCatalog
extends RefCounted

## Lapisan presentasi elemen: ikon, label, dan teks bantuan. Roster serta alias
## dimiliki `ElementRules` supaya simulasi tidak perlu ikut menarik autoload
## `LocaleManager` yang dipakai di bawah.
const ROSTER: PackedStringArray = ElementRules.ROSTER
const ALIASES := ElementRules.ALIASES

const _ICON_PATHS := {
	"metal": "res://assets/icons/element-metal.svg",
	"wood": "res://assets/icons/element-wood.svg",
	"stone": "res://assets/icons/element-stone.svg",
	"ceramic": "res://assets/icons/element-ceramic.svg",
	"glass": "res://assets/icons/element-glass.svg",
	"plastic": "res://assets/icons/element-plastic.svg",
	"cloth": "res://assets/icons/element-cloth.svg",
	"paper": "res://assets/icons/element-paper.svg",
	"plant": "res://assets/icons/element-plant.svg",
	"food": "res://assets/icons/element-food.svg",
	"fauna": "res://assets/icons/element-fauna.svg",
	"flow": "res://assets/icons/element-flow.svg",
	"spark": "res://assets/icons/element-spark.svg",
	"flame": "res://assets/icons/element-flame.svg",
	"frost": "res://assets/icons/element-frost.svg",
	"air": "res://assets/icons/element-air.svg",
	"toxin": "res://assets/icons/element-toxin.svg",
	"sound": "res://assets/icons/element-sound.svg",
}

static var _icon_cache: Dictionary = {}


static func normalize(code: String, fallback := "stone") -> String:
	var value := code.strip_edges().to_lower()
	if value in ROSTER:
		return value
	var aliased := str(ALIASES.get(value, ""))
	if not aliased.is_empty() and aliased in ROSTER:
		return aliased
	return fallback if fallback in ROSTER else "stone"


static func icon(code: String) -> Texture2D:
	var key := normalize(code, "")
	if key.is_empty():
		return null
	if _icon_cache.has(key):
		return _icon_cache[key] as Texture2D
	var path := str(_ICON_PATHS.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture != null:
		_icon_cache[key] = texture
	return texture


static func apply_icon(target: TextureRect, code: String) -> void:
	var texture := icon(code)
	target.texture = texture
	target.visible = texture != null


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
