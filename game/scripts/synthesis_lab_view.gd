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
@onready var _source_a_card: Button = %SynthesisSourceACard
@onready var _source_a_portrait: TextureRect = %SynthesisSourceAPortrait
@onready var _source_a_name: Label = %SynthesisSourceAName
@onready var _source_a_meta: Label = %SynthesisSourceAMeta
@onready var _source_b_card: Button = %SynthesisSourceBCard
@onready var _source_b_portrait: TextureRect = %SynthesisSourceBPortrait
@onready var _source_b_name: Label = %SynthesisSourceBName
@onready var _source_b_meta: Label = %SynthesisSourceBMeta
@onready var _picker_overlay: Control = %SynthesisPickerOverlay
@onready var _picker_back: Button = %SynthesisPickerBack
@onready var _picker_backdrop: Button = %SynthesisPickerBackdrop
@onready var _picker_title: Label = %SynthesisPickerTitle
@onready var _picker_list: ItemList = %SynthesisPickerList
@onready var _editor_scroll: ScrollContainer = %Scroll
@onready var _incubating_view: Control = %SynthesisIncubatingView
@onready var _incubating_title: Label = %SynthesisIncubatingTitle
@onready var _incubating_body: Label = %SynthesisIncubatingBody
@onready var _incubating_source_a_title: Label = %SynthesisIncubatingSourceATitle
@onready var _incubating_source_a_portrait: TextureRect = %SynthesisIncubatingSourceAPortrait
@onready var _incubating_source_a_name: Label = %SynthesisIncubatingSourceAName
@onready var _incubating_source_a_meta: Label = %SynthesisIncubatingSourceAMeta
@onready var _incubating_source_b_title: Label = %SynthesisIncubatingSourceBTitle
@onready var _incubating_source_b_portrait: TextureRect = %SynthesisIncubatingSourceBPortrait
@onready var _incubating_source_b_name: Label = %SynthesisIncubatingSourceBName
@onready var _incubating_source_b_meta: Label = %SynthesisIncubatingSourceBMeta
@onready var _mode_buttons: Array[Button] = [
	%SynthesisDominantA,
	%SynthesisBalanced,
	%SynthesisDominantB,
]
@onready var _review_button: Button = %SynthesisReviewButton
@onready var _preview_panel: Control = %SynthesisPreviewPanel
@onready var _chance: Label = %SynthesisChance
@onready var _chance_caption: Label = %SynthesisChanceCaption
@onready var _breakdown_grid: GridContainer = %SynthesisBreakdownGrid
@onready var _shape_title: Label = %SynthesisShapeTitle
@onready var _stat_grid: GridContainer = %SynthesisStatGrid
@onready var _confirm_button: Button = %SynthesisConfirmButton
@onready var _outcome_panel: Control = %SynthesisOutcomePanel
@onready var _outcome_title: Label = %SynthesisOutcomeTitle
@onready var _outcome_body: Label = %SynthesisOutcomeBody
@onready var _result_portrait: TextureRect = %SynthesisResultPortrait
@onready var _result_meta: Label = %SynthesisResultMeta
@onready var _result_button: Button = %SynthesisResultButton

var _rows: Array[Dictionary] = []
var _eligible: Array[Dictionary] = []
var _source_a_id := ""
var _source_b_id := ""
var _picker_slot := ""
var _thumbnail_provider: Callable
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
	_source_a_card.pressed.connect(_open_source_picker.bind("a"))
	_source_b_card.pressed.connect(_open_source_picker.bind("b"))
	_picker_back.pressed.connect(close_picker)
	_picker_backdrop.pressed.connect(close_picker)
	_picker_list.item_selected.connect(_on_picker_selected)
	_picker_list.fixed_icon_size = Vector2i(112, 112)
	for index in _mode_buttons.size():
		_mode_buttons[index].pressed.connect(_select_mode.bind(index))
	_review_button.pressed.connect(_request_preview)
	_confirm_button.pressed.connect(_request_attempt)
	_result_button.pressed.connect(_request_result)
	refresh_localized_ui()
	_select_mode(1)


func set_thumbnail_provider(provider: Callable) -> void:
	_thumbnail_provider = provider
	_paint_source_cards()
	_paint_incubating_sources()


func set_rows(rows: Array[Dictionary], preselected_a_id: String = "") -> void:
	# `GameState.pending_synthesis` is the only authority for an in-flight
	# Synthesis. Accepting it as an argument as well let the outcome panel and the
	# control lock disagree whenever a caller passed a stale copy.
	var pending := GameState.pending_synthesis
	_rows.clear()
	_eligible.clear()
	for row in rows:
		var stored := row.duplicate(true)
		_rows.append(stored)
		if is_eligible_source(stored):
			_eligible.append(stored)
	_updating = true
	_source_a_id = str(pending.get("source_a_id", preselected_a_id))
	_source_b_id = str(pending.get("source_b_id", ""))
	_normalize_source_ids()
	_mode = str(pending.get("mode", _mode))
	if not _mode in MODES:
		_mode = "balanced"
	_updating = false
	_paint_mode()
	_paint_source_cards()
	if _picker_overlay.visible:
		_populate_source_picker()
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


func close_picker() -> bool:
	if not _picker_overlay.visible:
		return false
	_picker_overlay.visible = false
	_picker_slot = ""
	return true


func apply_preview(data: Dictionary) -> void:
	_set_incubating(false)
	_preview = data.duplicate(true)
	_outcome_kind = &"preview"
	_outcome_data = {}
	_error_key = ""
	var breakdown := GameState.as_dict(data.get("breakdown"))
	_chance.text = tr("SYNTHESIS_CHANCE_VALUE") % LocaleManager.format_integer(
		int(breakdown.get("chance", 0))
	)
	_paint_review_factors(breakdown)
	_paint_review_stats(data)
	_preview_panel.visible = true
	_outcome_panel.visible = false
	_update_actions()


func show_error_key(message_key: String) -> void:
	_set_incubating(false)
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
	_set_incubating(false)
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
	_outcome_panel.visible = false
	_result_portrait.visible = false
	_result_meta.visible = false
	_result_button.visible = false
	_paint_incubating_sources()
	_set_incubating(true)
	_update_actions()


func show_result(row: Dictionary, portrait: Texture2D) -> void:
	_set_incubating(false)
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
	var row_a := _selected_row(_source_a_id)
	var row_b := _selected_row(_source_b_id)
	if row_a.is_empty() or row_b.is_empty():
		return {}
	return {
		"source_a_id": str(row_a.get("id", "")),
		"source_a_stage": CareRules.committed_stage(row_a),
		"source_b_id": str(row_b.get("id", "")),
		"source_b_stage": CareRules.committed_stage(row_b),
		"mode": _mode,
	}


func refresh_localized_ui() -> void:
	_back_button.text = ""
	_back_button.tooltip_text = tr("ACTION_BACK")
	_title.text = tr("SYNTHESIS_TITLE")
	_subtitle.text = tr("SYNTHESIS_SUBTITLE")
	_intro.text = tr("SYNTHESIS_INTRO")
	_source_a_title.text = tr("SYNTHESIS_SOURCE_A")
	_source_b_title.text = tr("SYNTHESIS_SOURCE_B")
	_mode_title.text = tr("SYNTHESIS_MODE_TITLE")
	_review_title.text = tr("SYNTHESIS_REVIEW_TITLE")
	_chance_caption.text = tr("SYNTHESIS_CHANCE_CAPTION")
	_shape_title.text = tr("SYNTHESIS_SHAPE_TITLE")
	_incubating_title.text = tr("SYNTHESIS_INCUBATING_TITLE")
	_incubating_body.text = tr("SYNTHESIS_INCUBATING_BODY")
	_incubating_source_a_title.text = tr("SYNTHESIS_SOURCE_A")
	_incubating_source_b_title.text = tr("SYNTHESIS_SOURCE_B")
	_mode_buttons[0].text = tr("SYNTHESIS_MODE_DOMINANT_A")
	_mode_buttons[1].text = tr("SYNTHESIS_MODE_BALANCED")
	_mode_buttons[2].text = tr("SYNTHESIS_MODE_DOMINANT_B")
	_review_button.text = tr("SYNTHESIS_REVIEW_ACTION")
	_confirm_button.text = tr("SYNTHESIS_CONFIRM_ACTION")
	_result_button.text = tr("SYNTHESIS_VIEW_RESULT")
	_picker_back.tooltip_text = tr("ACTION_BACK")
	_source_a_card.tooltip_text = tr("SYNTHESIS_PICK_SOURCE_A")
	_source_b_card.tooltip_text = tr("SYNTHESIS_PICK_SOURCE_B")
	_paint_mode()
	_paint_source_cards()
	_paint_incubating_sources()
	if _picker_overlay.visible:
		_populate_source_picker()
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


func _normalize_source_ids() -> void:
	if not GameState.pending_synthesis.is_empty():
		if not _row_id_exists(_source_a_id):
			_source_a_id = ""
		if not _row_id_exists(_source_b_id):
			_source_b_id = ""
		return
	if not _source_id_exists(_source_a_id):
		_source_a_id = str(_eligible[0].get("id", "")) if not _eligible.is_empty() else ""
	if not _source_id_exists(_source_b_id) or _source_b_id == _source_a_id:
		_source_b_id = ""
		for row in _eligible:
			var candidate := str(row.get("id", ""))
			if candidate != _source_a_id:
				_source_b_id = candidate
				break


func _row_id_exists(anima_id: String) -> bool:
	if anima_id.is_empty():
		return false
	for row in _rows:
		if str(row.get("id", "")) == anima_id:
			return true
	return false


func _source_id_exists(anima_id: String) -> bool:
	if anima_id.is_empty():
		return false
	for row in _eligible:
		if str(row.get("id", "")) == anima_id:
			return true
	return false


func _paint_source_cards() -> void:
	_paint_source_card(
		_selected_row(_source_a_id),
		_source_a_name,
		_source_a_meta,
		_source_a_portrait
	)
	_paint_source_card(
		_selected_row(_source_b_id),
		_source_b_name,
		_source_b_meta,
		_source_b_portrait
	)


func _paint_incubating_sources() -> void:
	_paint_source_card(
		_selected_row(_source_a_id),
		_incubating_source_a_name,
		_incubating_source_a_meta,
		_incubating_source_a_portrait
	)
	_paint_source_card(
		_selected_row(_source_b_id),
		_incubating_source_b_name,
		_incubating_source_b_meta,
		_incubating_source_b_portrait
	)


func _set_incubating(active: bool) -> void:
	_editor_scroll.visible = not active
	_incubating_view.visible = active
	_subtitle.visible = not active
	if active and is_visible_in_tree():
		_back_button.grab_focus()


func _paint_source_card(
	row: Dictionary,
	name_label: Label,
	meta_label: Label,
	portrait: TextureRect
) -> void:
	if row.is_empty():
		name_label.text = tr("SYNTHESIS_SOURCE_NONE")
		meta_label.text = ""
		portrait.texture = null
		return
	name_label.text = LocaleManager.display_name(row)
	meta_label.text = _source_meta(row)
	portrait.texture = _thumbnail_for(row)


func _source_meta(row: Dictionary) -> String:
	if row.is_empty():
		return tr("SYNTHESIS_SOURCE_NONE")
	return tr("SYNTHESIS_SOURCE_META") % [
		LocaleManager.level_label(CareRules.level_from_exp(int(row.get("care_score", 0)))),
		LocaleManager.element_compact(row),
		tr(_form_key(CareRules.committed_stage(row))),
	]


func _thumbnail_for(row: Dictionary) -> Texture2D:
	if row.is_empty() or not _thumbnail_provider.is_valid():
		return null
	var value: Variant = _thumbnail_provider.call(row)
	return value as Texture2D if value is Texture2D else null


func _open_source_picker(slot: String) -> void:
	if _busy or not GameState.pending_synthesis.is_empty() or _eligible.is_empty():
		return
	_picker_slot = slot
	_populate_source_picker()
	_picker_overlay.visible = true
	_picker_back.grab_focus()


func _populate_source_picker() -> void:
	_picker_list.clear()
	_picker_title.text = tr(
		"SYNTHESIS_PICK_SOURCE_A" if _picker_slot == "a" else "SYNTHESIS_PICK_SOURCE_B"
	)
	var selected_id := _source_a_id if _picker_slot == "a" else _source_b_id
	var other_id := _source_b_id if _picker_slot == "a" else _source_a_id
	var selected_index := -1
	for row in _eligible:
		var anima_id := str(row.get("id", ""))
		var label := tr("SYNTHESIS_PICKER_META") % [
			LocaleManager.display_name(row),
			LocaleManager.level_label(CareRules.level_from_exp(int(row.get("care_score", 0)))),
			LocaleManager.element_compact(row),
		]
		_picker_list.add_item(label, _thumbnail_for(row), true)
		var index := _picker_list.item_count - 1
		_picker_list.set_item_metadata(index, row)
		_picker_list.set_item_disabled(index, anima_id == other_id)
		_picker_list.set_item_tooltip(index, label)
		if anima_id == selected_id:
			selected_index = index
	if selected_index >= 0:
		_picker_list.select(selected_index)
		_picker_list.ensure_current_is_visible()


func _on_picker_selected(index: int) -> void:
	if index < 0 or index >= _picker_list.item_count or _picker_list.is_item_disabled(index):
		return
	var row := GameState.as_dict(_picker_list.get_item_metadata(index))
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return
	if _picker_slot == "a":
		_source_a_id = anima_id
	else:
		_source_b_id = anima_id
	close_picker()
	_paint_source_cards()
	_invalidate_preview()


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
	_set_incubating(false)
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
	if locked:
		close_picker()
	_source_a_card.disabled = locked or _eligible.is_empty()
	_source_b_card.disabled = locked or _eligible.is_empty()
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


func _selected_row(anima_id: String) -> Dictionary:
	if anima_id.is_empty():
		return {}
	for row in _rows:
		if str(row.get("id", "")) == anima_id:
			return row
	return {}


func _paint_review_factors(breakdown: Dictionary) -> void:
	var specs: Array[Array] = [
		["base", "SYNTHESIS_FACTOR_BASE"],
		["level", "SYNTHESIS_FACTOR_LEVEL"],
		["care", "SYNTHESIS_FACTOR_CARE"],
		["affinity", "SYNTHESIS_FACTOR_AFFINITY"],
		["mode", "SYNTHESIS_FACTOR_BIAS"],
		["calibration", "SYNTHESIS_FACTOR_CALIBRATION"],
	]
	for index in specs.size():
		var cell := _breakdown_grid.get_child(index) as Control
		_paint_metric_cell(
			cell,
			tr(str(specs[index][1])),
			tr("SYNTHESIS_FACTOR_VALUE") % LocaleManager.format_integer(
				int(breakdown.get(str(specs[index][0]), 0))
			)
		)


func _paint_review_stats(data: Dictionary) -> void:
	var a := GameState.as_dict(GameState.as_dict(data.get("source_a")).get("base_stats"))
	var b := GameState.as_dict(GameState.as_dict(data.get("source_b")).get("base_stats"))
	var weight_a := 0.70 if _mode == "dominant_a" else (0.30 if _mode == "dominant_b" else 0.50)
	var specs: Array[Array] = [
		["hp", "STAT_HP"],
		["atk", "STAT_ATK"],
		["def", "STAT_DEF"],
		["spd", "STAT_SPD"],
		["special", "STAT_SPECIAL"],
	]
	for index in specs.size():
		var key := str(specs[index][0])
		var cell := _stat_grid.get_child(index) as Control
		_paint_metric_cell(
			cell,
			tr(str(specs[index][1])),
			LocaleManager.format_integer(roundi(
				float(a.get(key, 50)) * weight_a + float(b.get(key, 50)) * (1.0 - weight_a)
			))
		)


func _paint_metric_cell(cell: Control, name_text: String, value_text: String) -> void:
	if cell == null:
		return
	var name_label := cell.get_node_or_null("Name") as Label
	var value_label := cell.get_node_or_null("Value") as Label
	if name_label != null:
		name_label.text = name_text
	if value_label != null:
		value_label.text = value_text


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
