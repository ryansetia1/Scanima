class_name AnimaDetailsView
extends Control

signal delete_requested(anima_id: String)
signal rename_requested(anima_id: String)
signal help_requested(title: String, body: String)

@onready var _empty_state: Label = %DetailsEmpty
@onready var _content: Control = %DetailsContent
@onready var _portrait: TextureRect = %DetailsPortrait
@onready var _name: Label = %DetailsName
@onready var _meta: Label = %DetailsMeta
@onready var _element_row = %DetailElementRow
@onready var _rarity_row = %DetailRarityRow
@onready var _stage_row = %DetailStageRow
@onready var _care_score_row = %DetailCareScoreRow
@onready var _strike_row = %DetailStrikeRow
@onready var _surge_row = %DetailSurgeRow
@onready var _hp_row = %StatHpRow
@onready var _atk_row = %StatAtkRow
@onready var _def_row = %StatDefRow
@onready var _spd_row = %StatSpdRow
@onready var _special_row = %StatSpecialRow
@onready var _rename_button: Button = %EditAnimaNameButton
@onready var _delete_button: Button = %DeleteAnimaButton

var _anima_id := ""
var _busy := false


func _ready() -> void:
	_rename_button.pressed.connect(_request_rename)
	_delete_button.pressed.connect(_request_delete)
	for row in _info_rows():
		row.help_requested.connect(_forward_help)
	refresh_localized_ui()


func set_anima(row: Dictionary, portrait: Texture2D) -> void:
	if row.is_empty():
		_anima_id = ""
		_empty_state.visible = true
		_content.visible = false
		_rename_button.disabled = true
		_delete_button.disabled = true
		return

	_anima_id = str(row.get("id", ""))
	_empty_state.visible = false
	_content.visible = true
	_rename_button.disabled = _busy or _anima_id.is_empty()
	_delete_button.disabled = _busy or _anima_id.is_empty()
	_portrait.texture = portrait
	_name.text = LocaleManager.display_name(row)
	_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(CareRules.level_from_exp(int(row.get("care_score", 0)))),
		LocaleManager.element_name(str(row.get("element", ""))),
	]
	_element_row.set_value_text(LocaleManager.element_name(str(row.get("element", ""))))
	_rarity_row.set_value_text(LocaleManager.format_ratio(int(row.get("rarity", 1)), 5))
	var level := CareRules.level_from_exp(int(row.get("care_score", 0)))
	_stage_row.set_value_text(
		"%s · %s" % [LocaleManager.level_label(level), LocaleManager.form_name(level)]
	)
	_care_score_row.set_value_text(LocaleManager.format_integer(int(row.get("care_score", 0))))
	_strike_row.set_value_text(LocaleManager.move_name(row, "strike"))
	_surge_row.set_value_text(LocaleManager.move_name(row, "surge"))

	var stats := GameState.as_dict(row.get("base_stats"))
	var exp := int(row.get("care_score", 0))
	_hp_row.set_value_text(_stat(stats, "hp", exp))
	_atk_row.set_value_text(_stat(stats, "atk", exp))
	_def_row.set_value_text(_stat(stats, "def", exp))
	_spd_row.set_value_text(_stat(stats, "spd", exp))
	_special_row.set_value_text(_stat(stats, "special", exp))


func set_busy(busy: bool) -> void:
	_busy = busy
	_rename_button.disabled = _busy or _anima_id.is_empty()
	_delete_button.disabled = _busy or _anima_id.is_empty()


func _request_rename() -> void:
	if not _anima_id.is_empty():
		rename_requested.emit(_anima_id)


func _request_delete() -> void:
	if not _anima_id.is_empty():
		delete_requested.emit(_anima_id)


func refresh_localized_ui() -> void:
	_element_row.configure(tr("DETAILS_ELEMENT"), tr("DETAILS_ELEMENT"), tr("DETAILS_ELEMENT_HELP"))
	_rarity_row.configure(tr("DETAILS_RARITY"), tr("DETAILS_RARITY"), tr("DETAILS_RARITY_HELP"))
	_stage_row.configure(tr("DETAILS_STAGE"), tr("DETAILS_STAGE"), tr("DETAILS_STAGE_HELP"))
	_care_score_row.configure(
		tr("DETAILS_CARE_SCORE"),
		tr("DETAILS_CARE_SCORE"),
		tr("DETAILS_CARE_SCORE_HELP")
	)
	_strike_row.configure(tr("DETAILS_STRIKE"), tr("DETAILS_STRIKE"), tr("DETAILS_STRIKE_HELP"))
	_surge_row.configure(tr("DETAILS_SURGE"), tr("DETAILS_SURGE"), tr("DETAILS_SURGE_HELP"))
	_hp_row.configure(tr("STAT_HP"), tr("STAT_HP"), tr("STAT_HP_HELP"))
	_atk_row.configure(tr("STAT_ATK"), tr("STAT_ATK"), tr("STAT_ATK_HELP"))
	_def_row.configure(tr("STAT_DEF"), tr("STAT_DEF"), tr("STAT_DEF_HELP"))
	_spd_row.configure(tr("STAT_SPD"), tr("STAT_SPD"), tr("STAT_SPD_HELP"))
	_special_row.configure(tr("STAT_SPECIAL"), tr("STAT_SPECIAL"), tr("STAT_SPECIAL_HELP"))


func _info_rows() -> Array:
	return [
		_element_row,
		_rarity_row,
		_stage_row,
		_care_score_row,
		_strike_row,
		_surge_row,
		_hp_row,
		_atk_row,
		_def_row,
		_spd_row,
		_special_row,
	]


func _forward_help(title: String, body: String) -> void:
	help_requested.emit(title, body)


func _stat(stats: Dictionary, key: String, exp: int) -> String:
	return (
		LocaleManager.format_integer(CareRules.grown_stat(stats[key], exp))
		if stats.has(key)
		else tr("VALUE_UNAVAILABLE")
	)
