class_name AnimaDetailsView
extends Control

@onready var _empty_state: Label = %DetailsEmpty
@onready var _content: Control = %DetailsContent
@onready var _portrait: TextureRect = %DetailsPortrait
@onready var _name: Label = %DetailsName
@onready var _meta: Label = %DetailsMeta
@onready var _element: Label = %DetailElement
@onready var _rarity: Label = %DetailRarity
@onready var _stage: Label = %DetailStage
@onready var _care_score: Label = %DetailCareScore
@onready var _hp: Label = %StatHp
@onready var _atk: Label = %StatAtk
@onready var _def: Label = %StatDef
@onready var _spd: Label = %StatSpd
@onready var _special: Label = %StatSpecial


func set_anima(row: Dictionary, portrait: Texture2D) -> void:
	if row.is_empty():
		_empty_state.visible = true
		_content.visible = false
		return

	_empty_state.visible = false
	_content.visible = true
	_portrait.texture = portrait
	_name.text = LocaleManager.display_name(row)
	_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.element_name(str(row.get("element", ""))),
		LocaleManager.stage_name(int(row.get("stage", 1))),
	]
	_element.text = LocaleManager.element_name(str(row.get("element", "")))
	_rarity.text = LocaleManager.format_ratio(int(row.get("rarity", 1)), 5)
	_stage.text = LocaleManager.stage_name(int(row.get("stage", 1)))
	_care_score.text = LocaleManager.format_integer(int(row.get("care_score", 0)))

	var stats := GameState.as_dict(row.get("base_stats"))
	_hp.text = _stat(stats, "hp")
	_atk.text = _stat(stats, "atk")
	_def.text = _stat(stats, "def")
	_spd.text = _stat(stats, "spd")
	_special.text = _stat(stats, "special")


func _stat(stats: Dictionary, key: String) -> String:
	return (
		LocaleManager.format_integer(int(stats[key]))
		if stats.has(key)
		else tr("VALUE_UNAVAILABLE")
	)
