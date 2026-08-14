class_name AnimaDetailsView
extends Control

signal delete_requested(anima_id: String)
signal rename_requested(anima_id: String)
signal gallery_publish_requested(anima_id: String, publish: bool)
signal help_requested(title: String, body: String)

@onready var _empty_state: Label = %DetailsEmpty
@onready var _content: Control = %DetailsContent
@onready var _portrait: TextureRect = %DetailsPortrait
@onready var _name: Label = %DetailsName
@onready var _meta: Label = %DetailsMeta
@onready var _trait_element: Label = %TraitElement
@onready var _trait_rarity: Label = %TraitRarity
@onready var _trait_stage: Label = %TraitStage
@onready var _trait_exp: Label = %TraitExp
@onready var _trait_strike: Label = %TraitStrike
@onready var _trait_surge: Label = %TraitSurge
@onready var _stat_hp: Label = %StatHp
@onready var _stat_atk: Label = %StatAtk
@onready var _stat_def: Label = %StatDef
@onready var _stat_spd: Label = %StatSpd
@onready var _stat_special: Label = %StatSpecial
@onready var _about_help: Button = %AboutHelp
@onready var _combat_help: Button = %CombatHelp
@onready var _rename_button: Button = %EditAnimaNameButton
@onready var _gallery_button: Button = %GalleryPublishButton
@onready var _delete_button: Button = %DeleteAnimaButton

var _anima_id := ""
var _element_code := ""
var _busy := false
var _gallery_published := false
var _gallery_available := false


func _ready() -> void:
	_rename_button.pressed.connect(_request_rename)
	_gallery_button.pressed.connect(_request_gallery_toggle)
	_delete_button.pressed.connect(_request_delete)
	_about_help.pressed.connect(_show_about_help)
	_combat_help.pressed.connect(_show_combat_help)
	refresh_localized_ui()


func set_anima(row: Dictionary, portrait: Texture2D) -> void:
	if row.is_empty():
		_anima_id = ""
		_element_code = ""
		_empty_state.visible = true
		_content.visible = false
		_rename_button.disabled = true
		_gallery_button.disabled = true
		_delete_button.disabled = true
		return

	_anima_id = str(row.get("id", ""))
	_element_code = str(row.get("element", ""))
	_empty_state.visible = false
	_content.visible = true
	_rename_button.disabled = _busy or _anima_id.is_empty()
	_gallery_button.disabled = _busy or _anima_id.is_empty() or not _gallery_available
	_delete_button.disabled = _busy or _anima_id.is_empty()
	_portrait.texture = portrait
	_name.text = LocaleManager.display_name(row)
	_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(CareRules.level_from_exp(int(row.get("care_score", 0)))),
		LocaleManager.element_compact(row),
	]
	_trait_element.text = LocaleManager.element_compact(row)
	_trait_rarity.text = LocaleManager.format_ratio(int(row.get("rarity", 1)), 5)
	var level := CareRules.level_from_exp(int(row.get("care_score", 0)))
	_trait_stage.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(level),
		LocaleManager.form_name(level),
	]
	_trait_exp.text = LocaleManager.format_integer(int(row.get("care_score", 0)))
	_trait_strike.text = LocaleManager.move_name(row, "strike")
	_trait_surge.text = LocaleManager.move_name(row, "surge")

	var stats := GameState.as_dict(row.get("base_stats"))
	var exp := int(row.get("care_score", 0))
	_stat_hp.text = _stat(stats, "hp", exp)
	_stat_atk.text = _stat(stats, "atk", exp)
	_stat_def.text = _stat(stats, "def", exp)
	_stat_spd.text = _stat(stats, "spd", exp)
	_stat_special.text = _stat(stats, "special", exp)


func set_busy(busy: bool) -> void:
	_busy = busy
	_rename_button.disabled = _busy or _anima_id.is_empty()
	_gallery_button.disabled = _busy or _anima_id.is_empty() or not _gallery_available
	_delete_button.disabled = _busy or _anima_id.is_empty()


func set_gallery_status(status: Dictionary) -> void:
	_gallery_available = bool(status.get("available", false))
	_gallery_published = bool(status.get("published", false))
	if not _gallery_available:
		_gallery_button.visible = false
		return
	_gallery_button.visible = true
	_gallery_button.text = tr("GALLERY_UNPUBLISH") if _gallery_published else tr("GALLERY_PUBLISH")
	_gallery_button.disabled = _busy or _anima_id.is_empty()


func _request_rename() -> void:
	if not _anima_id.is_empty():
		rename_requested.emit(_anima_id)


func _request_gallery_toggle() -> void:
	if _anima_id.is_empty():
		return
	gallery_publish_requested.emit(_anima_id, not _gallery_published)


func _request_delete() -> void:
	if not _anima_id.is_empty():
		delete_requested.emit(_anima_id)


func refresh_localized_ui() -> void:
	_about_help.tooltip_text = tr("DETAILS_TRAITS")
	_combat_help.tooltip_text = tr("DETAILS_ATTRIBUTES")


func _show_about_help() -> void:
	help_requested.emit(
		tr("DETAILS_TRAITS"),
		"\n\n".join([
			"%s — %s" % [tr("DETAILS_ELEMENT"), ElementCatalog.help_text(_element_code)],
			"%s — %s" % [tr("DETAILS_RARITY"), tr("DETAILS_RARITY_HELP")],
			"%s — %s" % [tr("DETAILS_STAGE"), tr("DETAILS_STAGE_HELP")],
			"%s — %s" % [tr("DETAILS_CARE_SCORE"), tr("DETAILS_CARE_SCORE_HELP")],
			"%s — %s" % [tr("DETAILS_STRIKE"), tr("DETAILS_STRIKE_HELP")],
			"%s — %s" % [tr("DETAILS_SURGE"), tr("DETAILS_SURGE_HELP")],
		])
	)


func _show_combat_help() -> void:
	help_requested.emit(
		tr("DETAILS_ATTRIBUTES"),
		"\n\n".join([
			"%s — %s" % [tr("STAT_HP"), tr("STAT_HP_HELP")],
			"%s — %s" % [tr("STAT_ATK"), tr("STAT_ATK_HELP")],
			"%s — %s" % [tr("STAT_DEF"), tr("STAT_DEF_HELP")],
			"%s — %s" % [tr("STAT_SPD"), tr("STAT_SPD_HELP")],
			"%s — %s" % [tr("STAT_SPECIAL"), tr("STAT_SPECIAL_HELP")],
		])
	)


func _stat(stats: Dictionary, key: String, exp: int) -> String:
	return (
		LocaleManager.format_integer(CareRules.grown_stat(stats[key], exp))
		if stats.has(key)
		else tr("VALUE_UNAVAILABLE")
	)
