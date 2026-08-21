class_name SynthesisLabView
extends Control

signal back_requested
signal preview_requested(payload: Dictionary)
signal attempt_requested(payload: Dictionary)
signal result_requested(row: Dictionary)

const MIN_LEVEL := 10
const MODES: Array[String] = ["dominant_a", "balanced", "dominant_b"]

@onready var _back_button: Button = %SynthesisBackButton
@onready var _title: Label = %SynthesisTitle
@onready var _subtitle: Label = %SynthesisSubtitle
@onready var _intro: Label = %SynthesisIntro
@onready var _source_a_title: Label = %SynthesisSourceATitle
@onready var _source_b_title: Label = %SynthesisSourceBTitle
@onready var _mode_title: Label = %SynthesisModeTitle
@onready var _review_title: Label = %SynthesisReviewTitle
@onready var _source_a: OptionButton = %SynthesisSourceA
@onready var _source_a_form: OptionButton = %SynthesisSourceAForm
@onready var _source_a_meta: Label = %SynthesisSourceAMeta
@onready var _source_b: OptionButton = %SynthesisSourceB
@onready var _source_b_form: OptionButton = %SynthesisSourceBForm
@onready var _source_b_meta: Label = %SynthesisSourceBMeta
@onready var _mode_buttons: Array[Button] = [
	%SynthesisDominantA,
	%SynthesisBalanced,
	%SynthesisDominantB,
]
@onready var _review_button: Button = %SynthesisReviewButton
@onready var _preview_panel: Control = %SynthesisPreviewPanel
@onready var _chance: Label = %SynthesisChance
@onready var _breakdown: Label = %SynthesisBreakdown
@onready var _stat_shape: Label = %SynthesisStatShape
@onready var _cost: Label = %SynthesisCost
@onready var _consequence: Label = %SynthesisConsequence
@onready var _confirm_button: Button = %SynthesisConfirmButton
@onready var _outcome_panel: Control = %SynthesisOutcomePanel
@onready var _outcome_title: Label = %SynthesisOutcomeTitle
@onready var _outcome_body: Label = %SynthesisOutcomeBody
@onready var _result_portrait: TextureRect = %SynthesisResultPortrait
@onready var _result_meta: Label = %SynthesisResultMeta
@onready var _result_button: Button = %SynthesisResultButton

var _eligible: Array[Dictionary] = []
var _mode := "balanced"
var _preview: Dictionary = {}
var _result_row: Dictionary = {}
var _outcome_kind: StringName = &""
var _outcome_data: Dictionary = {}
var _error_key := ""
var _busy := false
var _updating := false


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_source_a.item_selected.connect(func(_index: int) -> void: _selection_changed(true))
	_source_b.item_selected.connect(func(_index: int) -> void: _selection_changed(false))
	_source_a_form.item_selected.connect(func(_index: int) -> void: _invalidate_preview())
	_source_b_form.item_selected.connect(func(_index: int) -> void: _invalidate_preview())
	for index in _mode_buttons.size():
		_mode_buttons[index].pressed.connect(_select_mode.bind(index))
	_review_button.pressed.connect(_request_preview)
	_confirm_button.pressed.connect(_request_attempt)
	_result_button.pressed.connect(_request_result)
	refresh_localized_ui()
	_select_mode(1)


func set_rows(rows: Array[Dictionary], preselected_a_id: String = "") -> void:
	# `GameState.pending_synthesis` is the only authority for an in-flight
	# Synthesis. Accepting it as an argument as well let the outcome panel and the
	# control lock disagree whenever a caller passed a stale copy.
	var pending := GameState.pending_synthesis
	_eligible.clear()
	for row in rows:
		if is_eligible_source(row):
			_eligible.append(row.duplicate(true))
	_updating = true
	_fill_source_option(_source_a)
	_fill_source_option(_source_b)
	var source_a_id := str(pending.get("source_a_id", preselected_a_id))
	var source_b_id := str(pending.get("source_b_id", ""))
	_select_source_id(_source_a, source_a_id)
	_select_source_id(_source_b, source_b_id)
	if _source_b.selected == _source_a.selected and _eligible.size() > 1:
		_source_b.select(1 if _source_a.selected == 0 else 0)
	_rebuild_form_option(_source_a_form, _selected_row(_source_a))
	_rebuild_form_option(_source_b_form, _selected_row(_source_b))
	_select_stage(_source_a_form, int(pending.get("source_a_stage", 0)))
	_select_stage(_source_b_form, int(pending.get("source_b_stage", 0)))
	_mode = str(pending.get("mode", _mode))
	if not _mode in MODES:
		_mode = "balanced"
	_updating = false
	_paint_mode()
	_paint_source_meta()
	if pending.is_empty():
		_reset_outcome()
		_invalidate_preview()
	else:
		show_generating(pending)
	_update_actions()


func set_busy(busy: bool) -> void:
	_busy = busy
	_back_button.disabled = false
	_update_actions()


func apply_preview(data: Dictionary) -> void:
	_preview = data.duplicate(true)
	_outcome_kind = &"preview"
	_outcome_data = {}
	_error_key = ""
	var breakdown := GameState.as_dict(data.get("breakdown"))
	var chance := int(breakdown.get("chance", 0))
	_chance.text = tr("SYNTHESIS_CHANCE_VALUE") % LocaleManager.format_integer(chance)
	_breakdown.text = tr("SYNTHESIS_BREAKDOWN") % [
		LocaleManager.format_integer(int(breakdown.get("base", 0))),
		LocaleManager.format_integer(int(breakdown.get("level", 0))),
		LocaleManager.format_integer(int(breakdown.get("care", 0))),
		LocaleManager.format_integer(int(breakdown.get("affinity", 0))),
		LocaleManager.format_integer(int(breakdown.get("mode", 0))),
		LocaleManager.format_integer(int(breakdown.get("calibration", 0))),
	]
	_stat_shape.text = _stat_shape_line(data)
	var cost := GameState.as_dict(data.get("cost"))
	_cost.text = tr("SYNTHESIS_COST") % [
		LocaleManager.format_integer(int(cost.get("cores", 1))),
		LocaleManager.format_integer(int(cost.get("bits", 250))),
	]
	_consequence.text = tr("SYNTHESIS_FAILURE_CONSEQUENCE")
	_preview_panel.visible = true
	_outcome_panel.visible = false
	_update_actions()


func show_error_key(message_key: String) -> void:
	_preview = {}
	_outcome_kind = &"error"
	_outcome_data = {}
	_error_key = message_key
	_preview_panel.visible = false
	_outcome_panel.visible = true
	_outcome_title.text = tr("SYNTHESIS_UNAVAILABLE_TITLE")
	_outcome_body.text = tr(message_key)
	_result_portrait.visible = false
	_result_meta.visible = false
	_result_button.visible = false
	_update_actions()


func show_resonance_failure(data: Dictionary) -> void:
	_preview = {}
	_outcome_kind = &"resonance_failure"
	_outcome_data = data.duplicate(true)
	_error_key = ""
	_preview_panel.visible = false
	_outcome_panel.visible = true
	_outcome_title.text = tr("SYNTHESIS_RESONANCE_FAILED_TITLE")
	_outcome_body.text = tr("SYNTHESIS_RESONANCE_FAILED_BODY") % [
		LocaleManager.format_integer(int(data.get("chance", 0))),
		LocaleManager.format_integer(int(data.get("calibration", 0))),
	]
	_result_portrait.visible = false
	_result_meta.visible = false
	_result_button.visible = false
	_update_actions()


func show_generating(_pending: Dictionary) -> void:
	_preview = {}
	_outcome_kind = &"generating"
	_outcome_data = {}
	_error_key = ""
	_preview_panel.visible = false
	_outcome_panel.visible = true
	_outcome_title.text = tr("SYNTHESIS_INCUBATING_TITLE")
	_outcome_body.text = tr("SYNTHESIS_INCUBATING_BODY")
	_result_portrait.visible = false
	_result_meta.visible = false
	_result_button.visible = false
	_update_actions()


func show_result(row: Dictionary, portrait: Texture2D) -> void:
	_result_row = row.duplicate(true)
	_preview = {}
	_outcome_kind = &"result"
	_outcome_data = {}
	_error_key = ""
	_preview_panel.visible = false
	_outcome_panel.visible = true
	_outcome_title.text = tr("SYNTHESIS_COMPLETE_TITLE")
	_outcome_body.text = tr("SYNTHESIS_COMPLETE_BODY")
	_result_portrait.texture = portrait
	_result_portrait.visible = true
	_result_meta.text = tr("SYNTHESIS_RESULT_META") % [
		LocaleManager.display_name(row),
		LocaleManager.element_compact(row),
		LocaleManager.level_label(CareRules.level_from_exp(int(row.get("care_score", 0)))),
	]
	_result_meta.visible = true
	_result_button.visible = true
	_update_actions()


func current_payload() -> Dictionary:
	var row_a := _selected_row(_source_a)
	var row_b := _selected_row(_source_b)
	if row_a.is_empty() or row_b.is_empty():
		return {}
	return {
		"source_a_id": str(row_a.get("id", "")),
		"source_a_stage": _selected_stage(_source_a_form),
		"source_b_id": str(row_b.get("id", "")),
		"source_b_stage": _selected_stage(_source_b_form),
		"mode": _mode,
	}


func refresh_localized_ui() -> void:
	_back_button.text = tr("ACTION_BACK")
	_title.text = tr("SYNTHESIS_TITLE")
	_subtitle.text = tr("SYNTHESIS_SUBTITLE")
	_intro.text = tr("SYNTHESIS_INTRO")
	_source_a_title.text = tr("SYNTHESIS_SOURCE_A")
	_source_b_title.text = tr("SYNTHESIS_SOURCE_B")
	_mode_title.text = tr("SYNTHESIS_MODE_TITLE")
	_review_title.text = tr("SYNTHESIS_REVIEW_TITLE")
	_mode_buttons[0].text = tr("SYNTHESIS_MODE_DOMINANT_A")
	_mode_buttons[1].text = tr("SYNTHESIS_MODE_BALANCED")
	_mode_buttons[2].text = tr("SYNTHESIS_MODE_DOMINANT_B")
	_review_button.text = tr("SYNTHESIS_REVIEW_ACTION")
	_confirm_button.text = tr("SYNTHESIS_CONFIRM_ACTION")
	_result_button.text = tr("SYNTHESIS_VIEW_RESULT")
	var selection := current_payload()
	_updating = true
	_fill_source_option(_source_a)
	_fill_source_option(_source_b)
	_select_source_id(_source_a, str(selection.get("source_a_id", "")))
	_select_source_id(_source_b, str(selection.get("source_b_id", "")))
	_rebuild_form_option(_source_a_form, _selected_row(_source_a))
	_rebuild_form_option(_source_b_form, _selected_row(_source_b))
	_select_stage(_source_a_form, int(selection.get("source_a_stage", 0)))
	_select_stage(_source_b_form, int(selection.get("source_b_stage", 0)))
	_updating = false
	_paint_mode()
	_paint_source_meta()
	match _outcome_kind:
		&"preview":
			apply_preview(_preview)
		&"error":
			show_error_key(_error_key)
		&"resonance_failure":
			show_resonance_failure(_outcome_data)
		&"generating":
			show_generating({})
		&"result":
			show_result(_result_row, _result_portrait.texture)


func _fill_source_option(option: OptionButton) -> void:
	option.clear()
	for row in _eligible:
		option.add_item(tr("SYNTHESIS_SOURCE_OPTION") % [
			LocaleManager.display_name(row),
			LocaleManager.level_label(CareRules.level_from_exp(int(row.get("care_score", 0)))),
		])


func _selection_changed(source_a_changed: bool) -> void:
	if _updating:
		return
	var source_option := _source_a if source_a_changed else _source_b
	var form_option := _source_a_form if source_a_changed else _source_b_form
	_rebuild_form_option(form_option, _selected_row(source_option))
	if _eligible.size() > 1 and _source_a.selected == _source_b.selected:
		_source_b.select((_source_a.selected + 1) % _eligible.size())
		_rebuild_form_option(_source_b_form, _selected_row(_source_b))
	_paint_source_meta()
	_invalidate_preview()


func _rebuild_form_option(option: OptionButton, row: Dictionary) -> void:
	option.clear()
	var stage := CareRules.committed_stage(row)
	for form_stage in range(1, stage + 1):
		option.add_item(tr(_form_key(form_stage)))
		option.set_item_metadata(option.item_count - 1, form_stage)
	if option.item_count > 0:
		option.select(option.item_count - 1)


func _paint_source_meta() -> void:
	_source_a_meta.text = _source_meta(_selected_row(_source_a))
	_source_b_meta.text = _source_meta(_selected_row(_source_b))


func _source_meta(row: Dictionary) -> String:
	if row.is_empty():
		return tr("SYNTHESIS_SOURCE_NONE")
	return tr("SYNTHESIS_SOURCE_META") % [
		LocaleManager.element_compact(row),
		LocaleManager.format_integer(CareRules.committed_stage(row)),
	]


func _select_mode(index: int) -> void:
	if index < 0 or index >= MODES.size():
		return
	_mode = MODES[index]
	_paint_mode()
	_invalidate_preview()


func _paint_mode() -> void:
	for index in _mode_buttons.size():
		_mode_buttons[index].button_pressed = MODES[index] == _mode


func _request_preview() -> void:
	var payload := current_payload()
	if not payload.is_empty() and _selection_valid():
		preview_requested.emit(payload)


func _request_attempt() -> void:
	var payload := current_payload()
	if not payload.is_empty() and not _preview.is_empty() and _selection_valid():
		attempt_requested.emit(payload)


func _request_result() -> void:
	if not _result_row.is_empty():
		result_requested.emit(_result_row.duplicate(true))


func _invalidate_preview() -> void:
	if _updating:
		return
	_preview = {}
	_preview_panel.visible = false
	_reset_outcome()
	_update_actions()


func _reset_outcome() -> void:
	_result_row = {}
	_outcome_kind = &""
	_outcome_data = {}
	_error_key = ""
	_outcome_panel.visible = false
	_result_portrait.visible = false
	_result_meta.visible = false
	_result_button.visible = false


func _update_actions() -> void:
	var pending := not GameState.pending_synthesis.is_empty()
	var locked := _busy or pending
	_source_a.disabled = locked
	_source_a_form.disabled = locked
	_source_b.disabled = locked
	_source_b_form.disabled = locked
	for button in _mode_buttons:
		button.disabled = locked
	var valid := _selection_valid()
	_review_button.disabled = locked or not valid
	_confirm_button.disabled = locked or not valid or _preview.is_empty()


func _selection_valid() -> bool:
	var payload := current_payload()
	return (
		_eligible.size() >= 2
		and not payload.is_empty()
		and str(payload.get("source_a_id", "")) != str(payload.get("source_b_id", ""))
		and int(payload.get("source_a_stage", 0)) > 0
		and int(payload.get("source_b_stage", 0)) > 0
	)


func _selected_row(option: OptionButton) -> Dictionary:
	var index := option.selected
	if index < 0 or index >= _eligible.size():
		return {}
	return _eligible[index]


func _select_source_id(option: OptionButton, anima_id: String) -> void:
	if anima_id.is_empty():
		return
	for index in _eligible.size():
		if str(_eligible[index].get("id", "")) == anima_id:
			option.select(index)
			return


func _select_stage(option: OptionButton, stage: int) -> void:
	if stage <= 0:
		return
	for index in option.item_count:
		if int(option.get_item_metadata(index)) == stage:
			option.select(index)
			return


func _selected_stage(option: OptionButton) -> int:
	if option.selected < 0 or option.selected >= option.item_count:
		return 0
	return int(option.get_item_metadata(option.selected))


func _stat_shape_line(data: Dictionary) -> String:
	var a := GameState.as_dict(GameState.as_dict(data.get("source_a")).get("base_stats"))
	var b := GameState.as_dict(GameState.as_dict(data.get("source_b")).get("base_stats"))
	var weight_a := 0.70 if _mode == "dominant_a" else (0.30 if _mode == "dominant_b" else 0.50)
	var values: Array[String] = []
	for key in ["hp", "atk", "def", "spd", "special"]:
		values.append(LocaleManager.format_integer(roundi(
			float(a.get(key, 50)) * weight_a + float(b.get(key, 50)) * (1.0 - weight_a)
		)))
	return tr("SYNTHESIS_STAT_SHAPE") % values


static func is_eligible_source(row: Dictionary) -> bool:
	# The Level gate lives in server config; MIN_LEVEL is only the offline
	# fallback, so lowering it in ops does not keep valid Sources hidden.
	var min_level := maxi(1, int(
		GameState.client_config.get("synthesis_min_level", MIN_LEVEL)
	))
	return (
		str(row.get("status", "")) == "ready"
		and not CareRules.has_timestamp(row.get("dormant_since"))
		and not CareRules.is_evolving(row)
		and CareRules.level_from_exp(int(row.get("care_score", 0))) >= min_level
	)


static func _form_key(stage: int) -> String:
	match stage:
		2:
			return "FORM_ADULT"
		3:
			return "FORM_EVOLVED"
		_:
			return "FORM_HATCHLING"
