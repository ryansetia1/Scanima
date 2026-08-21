class_name AnimaDetailsView
extends Control

signal delete_requested(anima_id: String)
signal rename_requested(anima_id: String)
signal gallery_publish_requested(anima_id: String, publish: bool)
signal evolve_requested(row: Dictionary)
signal synthesis_requested(row: Dictionary)
signal help_requested(title: String, body: String)

## Cermin `_validated_anima_name()` di Postgres. Preflight ini hanya menghemat
## satu round trip; database tetap pagar terakhirnya, dan daftar impersonasi
## sengaja tidak ikut turun ke client — ia berubah tanpa build baru.
const NAME_PATTERN := "^[A-Za-z0-9][A-Za-z0-9 '-]{0,31}$"
const NAME_MAX_LENGTH := 32

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
@onready var _evolve_button: Button = %EvolveAnimaButton
@onready var _evolution_status: Label = %EvolutionStatusLabel
@onready var _synthesis_button: Button = %SynthesisAnimaButton
@onready var _synthesis_history: Control = %SynthesisHistoryPanel
@onready var _history_title: Label = %SynthesisHistoryTitle
@onready var _history_source_a: TextureRect = %SynthesisHistorySourceA
@onready var _history_source_a_label: Label = %SynthesisHistorySourceALabel
@onready var _history_source_b: TextureRect = %SynthesisHistorySourceB
@onready var _history_source_b_label: Label = %SynthesisHistorySourceBLabel
@onready var _history_mode: Label = %SynthesisHistoryMode
@onready var _history_summary: Label = %SynthesisHistorySummary
@onready var _delete_button: Button = %DeleteAnimaButton

var _anima_id := ""
var _element_code := ""
var _row: Dictionary = {}
var _busy := false
var _gallery_published := false
var _gallery_available := false
var _evolution_enabled := false
var _synthesis_enabled := false
var _synthesis_history_textures: Dictionary = {}


func _ready() -> void:
	_rename_button.pressed.connect(_request_rename)
	_gallery_button.pressed.connect(_request_gallery_toggle)
	_evolve_button.pressed.connect(_request_evolve)
	_synthesis_button.pressed.connect(_request_synthesis)
	_delete_button.pressed.connect(_request_delete)
	_about_help.pressed.connect(_show_about_help)
	_combat_help.pressed.connect(_show_combat_help)
	refresh_localized_ui()


func set_anima(row: Dictionary, portrait: Texture2D) -> void:
	var next_id := str(row.get("id", ""))
	if next_id != _anima_id:
		_synthesis_history_textures.clear()
	_row = row.duplicate(true) if not row.is_empty() else {}
	if row.is_empty():
		_anima_id = ""
		_element_code = ""
		_empty_state.visible = true
		_content.visible = false
		_rename_button.disabled = true
		_gallery_button.disabled = true
		_evolve_button.visible = false
		_evolution_status.visible = false
		_synthesis_button.visible = false
		_synthesis_history.visible = false
		_delete_button.disabled = true
		return

	_anima_id = str(row.get("id", ""))
	_element_code = str(row.get("element", ""))
	_empty_state.visible = false
	_content.visible = true
	var evolving := CareRules.is_evolving(row)
	_rename_button.disabled = _busy or _anima_id.is_empty() or evolving
	_gallery_button.disabled = _busy or _anima_id.is_empty() or not _gallery_available or evolving
	_delete_button.disabled = _busy or _anima_id.is_empty() or evolving
	_portrait.texture = portrait
	_name.text = LocaleManager.display_name(row)
	var level := CareRules.level_from_exp(int(row.get("care_score", 0)))
	_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(level),
		LocaleManager.element_compact(row),
	]
	_trait_element.text = LocaleManager.element_compact(row)
	_trait_rarity.text = LocaleManager.format_ratio(int(row.get("rarity", 1)), 5)
	_trait_stage.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(level),
		LocaleManager.form_name_for_row(row),
	]
	_trait_exp.text = LocaleManager.format_integer(int(row.get("care_score", 0)))
	_trait_strike.text = _move_line(row, "strike")
	_trait_surge.text = _move_line(row, "surge")

	var stats := GameState.as_dict(row.get("base_stats"))
	_stat_hp.text = _stat_for_row(stats, "hp", row)
	_stat_atk.text = _stat_for_row(stats, "atk", row)
	_stat_def.text = _stat_for_row(stats, "def", row)
	_stat_spd.text = _stat_for_row(stats, "spd", row)
	_stat_special.text = _stat_for_row(stats, "special", row)
	_apply_evolution_ui(row)
	_apply_synthesis_ui(row)
	_apply_synthesis_history(
		GameState.as_dict(row.get("synthesis_history")),
		_synthesis_history_textures
	)


func set_busy(busy: bool) -> void:
	_busy = busy
	var evolving := CareRules.is_evolving(_row)
	_rename_button.disabled = _busy or _anima_id.is_empty() or evolving
	_gallery_button.disabled = _busy or _anima_id.is_empty() or not _gallery_available or evolving
	_delete_button.disabled = _busy or _anima_id.is_empty() or evolving
	if not _row.is_empty():
		_apply_evolution_ui(_row)
		_apply_synthesis_ui(_row)


func set_evolution_enabled(enabled: bool) -> void:
	_evolution_enabled = enabled
	if not _row.is_empty():
		_apply_evolution_ui(_row)


func set_synthesis_enabled(enabled: bool) -> void:
	_synthesis_enabled = enabled
	if not _row.is_empty():
		_apply_synthesis_ui(_row)


func set_synthesis_history(history: Dictionary, textures: Dictionary = {}) -> void:
	if _row.is_empty():
		return
	if not textures.is_empty():
		_synthesis_history_textures = textures.duplicate()
	_apply_synthesis_history(history, _synthesis_history_textures)


func set_gallery_status(status: Dictionary) -> void:
	_gallery_available = bool(status.get("available", false))
	_gallery_published = bool(status.get("published", false))
	if not _gallery_available:
		_gallery_button.visible = false
		return
	_gallery_button.visible = true
	_gallery_button.text = tr("GALLERY_UNPUBLISH") if _gallery_published else tr("GALLERY_PUBLISH")
	_gallery_button.disabled = (
		_busy or _anima_id.is_empty() or CareRules.is_evolving(_row)
	)


func _apply_synthesis_ui(row: Dictionary) -> void:
	var eligible := SynthesisLabView.is_eligible_source(row)
	_synthesis_button.visible = _synthesis_enabled
	# `_busy` hanya menunda tap, bukan menolak Anima-nya, jadi tooltip alasan
	# ketidaklayakan cuma dipasang kalau Anima ini memang tidak memenuhi syarat.
	_synthesis_button.disabled = _busy or not eligible
	_synthesis_button.tooltip_text = (
		tr("SYNTHESIS_USE_SOURCE_ACTION") if eligible else tr("SYNTHESIS_SOURCE_INELIGIBLE")
	)


func _apply_synthesis_history(history: Dictionary, textures: Dictionary) -> void:
	_synthesis_history.visible = not history.is_empty()
	if history.is_empty():
		return
	var source_a := GameState.as_dict(history.get("source_a"))
	var source_b := GameState.as_dict(history.get("source_b"))
	_history_source_a.texture = textures.get("source_a") as Texture2D
	_history_source_b.texture = textures.get("source_b") as Texture2D
	_history_source_a_label.text = tr("SYNTHESIS_HISTORY_SOURCE") % [
		str(source_a.get("name", tr("ANIMA_FALLBACK_NAME"))),
		tr(_form_key(int(source_a.get("selected_stage", 1)))),
	]
	_history_source_b_label.text = tr("SYNTHESIS_HISTORY_SOURCE") % [
		str(source_b.get("name", tr("ANIMA_FALLBACK_NAME"))),
		tr(_form_key(int(source_b.get("selected_stage", 1)))),
	]
	_history_mode.text = tr("SYNTHESIS_HISTORY_MODE") % [
		tr(_mode_key(str(history.get("mode", "balanced")))),
		LocaleManager.format_integer(int(history.get("resonance", 0))),
	]
	var summary := GameState.as_dict(history.get("inheritance_summary"))
	_history_summary.text = tr("SYNTHESIS_HISTORY_SUMMARY") % [
		str(summary.get("source_a", "")),
		str(summary.get("source_b", "")),
		str(summary.get("coherence", "")),
	]


func _apply_evolution_ui(row: Dictionary) -> void:
	var evolving := CareRules.is_evolving(row)
	var evolution_ready := _evolution_enabled and CareRules.evolution_ready(row)
	var stage3 := CareRules.committed_stage(row) >= 3
	_evolve_button.visible = evolution_ready and not stage3 and not evolving
	_evolve_button.disabled = _busy or not evolution_ready
	_evolution_status.visible = evolving
	if evolving:
		_evolution_status.text = tr("EVOLUTION_CHAMBER_STATUS")
	elif evolution_ready and not stage3:
		_evolve_button.text = tr("EVOLVE_ACTION")


func _move_line(row: Dictionary, action: String) -> String:
	var move := LocaleManager.move_name(row, action)
	if CareRules.evolution_version(row) < 1:
		return move
	var effect_id := str(
		row.get("surge_effect_id" if action == "surge" else "strike_effect_id", "")
	).strip_edges()
	if effect_id.is_empty():
		return move
	return tr("DETAILS_MOVE_EFFECT") % [move, LocaleManager.effect_name(effect_id)]


func _request_evolve() -> void:
	if _row.is_empty() or not CareRules.evolution_ready(_row):
		return
	evolve_requested.emit(_row.duplicate(true))


func _request_synthesis() -> void:
	if not _synthesis_button.disabled and not _row.is_empty():
		synthesis_requested.emit(_row.duplicate(true))


static func _form_key(stage: int) -> String:
	return SynthesisLabView._form_key(stage)


static func _mode_key(mode: String) -> String:
	match mode:
		"dominant_a":
			return "SYNTHESIS_MODE_DOMINANT_A"
		"dominant_b":
			return "SYNTHESIS_MODE_DOMINANT_B"
		_:
			return "SYNTHESIS_MODE_BALANCED"


static func is_valid_anima_name(value: String) -> bool:
	var name := value.strip_edges()
	return (
		RegEx.create_from_string(NAME_PATTERN).search(name) != null
		and RegEx.create_from_string("[A-Za-z]").search(name) != null
		and not name.contains("  ")
	)


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
	_evolve_button.text = tr("EVOLVE_ACTION")
	_synthesis_button.text = tr("SYNTHESIS_USE_SOURCE_ACTION")
	_history_title.text = tr("SYNTHESIS_HISTORY_TITLE")
	if not _row.is_empty():
		set_anima(_row, _portrait.texture)


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


func _stat_for_row(stats: Dictionary, key: String, row: Dictionary) -> String:
	return (
		LocaleManager.format_integer(CareRules.grown_stat_for_row(stats[key], row))
		if stats.has(key)
		else tr("VALUE_UNAVAILABLE")
	)
