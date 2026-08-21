class_name CollectionView
extends Control

signal preview_requested(row: Dictionary, revision: int)
signal profile_requested(row: Dictionary)
signal summon_requested(row: Dictionary, care_synced: bool)
signal first_scan_requested
signal retry_requested
signal atlas_requested
signal synthesis_requested(preselected: Dictionary)

const BADGE_INSET := Vector2(10.0, 8.0)
const BADGE_FONT_SIZE := 20

@onready var _status: Label = %CollectionStatus
@onready var _list: ItemList = %AnimaList
@onready var _empty_action: Button = %CollectionEmptyAction
@onready var _sheet = %CollectionSheetOverlay
@onready var _sheet_portrait: TextureRect = %CollectionSheetPortrait
@onready var _sheet_name: Label = %CollectionSheetName
@onready var _sheet_meta: Label = %CollectionSheetMeta
@onready var _active_badge: Label = %CollectionActiveBadge
@onready var _condition_status: Label = %CollectionConditionStatus
@onready var _condition_skeleton = %ConditionSkeleton
@onready var _care_rows: VBoxContainer = %CareRows
@onready var _profile_button: Button = %CollectionProfileButton
@onready var _summon_button: Button = %CollectionSummonButton
@onready var _synthesis_button: Button = %CollectionSynthesisButton

@onready var _base_values := {
	"hp": %SheetStatHp,
	"atk": %SheetStatAttack,
	"def": %SheetStatDefense,
	"spd": %SheetStatSpeed,
	"special": %SheetStatSpecial,
}
@onready var 	_care_meters := {
	"hunger": %SheetCareHunger,
	"energy": %SheetCareEnergy,
	"hygiene": %SheetCareHygiene,
	"exp": %SheetCareExp,
}

var _active_id := ""
var _selected_row: Dictionary = {}
var _thumbnail_provider: Callable
var _care_cache: Dictionary = {}
var _revision := 0
var _busy := false
var _condition_loading := false
var _condition_synced := false
var _empty_mode := &"scan"
var _evolution_enabled := false
var _synthesis_enabled := false
var _eligible_synthesis_sources := 0


func _ready() -> void:
	%CollectionAtlasTab.pressed.connect(func() -> void: atlas_requested.emit())
	_synthesis_button.pressed.connect(func() -> void: synthesis_requested.emit({}))
	_list.item_selected.connect(_on_item_selected)
	_list.draw.connect(_draw_level_badges)
	_empty_action.pressed.connect(_on_empty_action)
	_sheet.dismissed.connect(_on_sheet_dismissed)
	_profile_button.pressed.connect(_view_profile)
	_summon_button.pressed.connect(_summon)


func refresh_localized_ui() -> void:
	%CollectionCollectionTab.text = tr("COLLECTION_TAB_COLLECTION")
	%CollectionAtlasTab.text = tr("COLLECTION_TAB_ATLAS")
	_synthesis_button.text = tr("SYNTHESIS_LAB_ACTION")


func set_rows(rows: Array[Dictionary], active_id: String, thumbnail_provider: Callable) -> void:
	_active_id = active_id
	_thumbnail_provider = thumbnail_provider
	_list.clear()
	var selected := -1
	_eligible_synthesis_sources = 0
	for row in rows:
		if SynthesisLabView.is_eligible_source(row):
			_eligible_synthesis_sources += 1
		var id := str(row.get("id", ""))
		var name := LocaleManager.display_name(row)
		if CareRules.is_evolving(row):
			name += " · " + tr("COLLECTION_EVOLVING")
		elif _evolution_enabled and CareRules.evolution_ready(row):
			name += " · " + tr("COLLECTION_READY_EVOLVE")
		var label := tr("COLLECTION_ITEM_META") % [
			name,
			LocaleManager.element_compact(row),
		]
		var texture: Texture2D = thumbnail_provider.call(row)
		_list.add_item(label, texture, true)
		var index := _list.item_count - 1
		_list.set_item_metadata(index, row)
		_list.set_item_tooltip(
			index,
			tr("COLLECTION_ITEM_TOOLTIP") % [
				name,
				LocaleManager.format_integer(int(row.get("rarity", 1))),
			]
		)
		if id == active_id:
			selected = index
	if selected >= 0:
		_list.select(selected)
	_list.visible = not rows.is_empty()
	_status.text = (
		tr("COLLECTION_EMPTY")
		if rows.is_empty()
		else tr("COLLECTION_COUNT") % LocaleManager.format_integer(rows.size())
	)
	_empty_mode = &"scan"
	_empty_action.text = tr("COLLECTION_START_SCAN")
	_empty_action.visible = rows.is_empty()
	_update_synthesis_state()
	if not _selected_row.is_empty():
		var selected_id := str(_selected_row.get("id", ""))
		var replacement := _row_with_id(rows, selected_id)
		if replacement.is_empty():
			close_sheet()
		else:
			_selected_row = replacement
			_fill_identity()
			_update_active_state()


func set_error() -> void:
	_status.text = tr("STATUS_ROSTER_ERROR")
	_list.visible = false
	_empty_mode = &"retry"
	_empty_action.text = tr("ACTION_RETRY")
	_empty_action.visible = true
	close_sheet()


func set_busy(busy: bool) -> void:
	_busy = busy
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP
	_empty_action.disabled = busy
	_update_action_state()
	_update_synthesis_state()


func set_evolution_enabled(enabled: bool) -> void:
	_evolution_enabled = enabled


func set_synthesis_enabled(enabled: bool) -> void:
	_synthesis_enabled = enabled
	_update_synthesis_state()


func _update_synthesis_state() -> void:
	_synthesis_button.visible = _synthesis_enabled
	_synthesis_button.disabled = _busy or _eligible_synthesis_sources < 2
	_synthesis_button.tooltip_text = (
		tr("SYNTHESIS_NEEDS_TWO_SOURCES")
		if _eligible_synthesis_sources < 2
		else tr("SYNTHESIS_LAB_ACTION")
	)


func begin_visit() -> void:
	_care_cache.clear()
	close_sheet()


func is_sheet_open() -> bool:
	return _sheet.visible


func selected_revision() -> int:
	return _revision


func show_preview(row: Dictionary, request_sync: bool = true) -> void:
	if row.is_empty():
		return
	_selected_row = row.duplicate(true)
	_revision += 1
	_fill_identity()
	_fill_base_stats()
	_update_active_state()

	var anima_id := str(_selected_row.get("id", ""))
	if CareRules.is_evolving(_selected_row):
		_apply_condition(_selected_row, true)
	elif _care_cache.has(anima_id):
		_selected_row = GameState.as_dict(_care_cache[anima_id])
		_fill_identity()
		_fill_base_stats()
		_apply_condition(_selected_row, true)
	elif not request_sync:
		_apply_condition(_selected_row, true)
	else:
		_set_condition_loading()
		preview_requested.emit(_selected_row.duplicate(true), _revision)
	call_deferred("_reveal_sheet", _revision)


func show_preview_loading(row: Dictionary) -> void:
	show_preview(row, false)
	_set_condition_loading()


func apply_care_sync(row: Dictionary, revision: int) -> bool:
	if not _selection_matches(row, revision):
		return false
	var normalized := row.duplicate(true)
	_care_cache[str(normalized.get("id", ""))] = normalized
	_selected_row = normalized
	_fill_identity()
	_apply_condition(normalized, true)
	_sheet.fit_to_content()
	return true


func set_care_sync_error(revision: int) -> void:
	if revision != _revision or _selected_row.is_empty() or not _sheet.visible:
		return
	_apply_condition(_selected_row, false)
	_condition_status.text = tr("COLLECTION_CONDITION_ERROR")
	_condition_status.visible = true


func close_sheet() -> void:
	if not _sheet.visible:
		return
	_sheet.close()


func _on_sheet_dismissed() -> void:
	_revision += 1
	_condition_skeleton.set_loading(false)


func set_sheet_busy(busy: bool) -> void:
	_busy = busy
	_update_action_state()


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	var row := GameState.as_dict(_list.get_item_metadata(index))
	if not row.is_empty():
		show_preview(row)


## Level per kartu digambar sendiri karena `ItemList` hanya punya satu slot teks
## per item. Angkanya dibaca dari metadata row yang sudah dipasang `set_rows()`,
## jadi tidak ada jalur data kedua yang bisa basi saat care sync mengubah EXP.
## Teks telanjang, tanpa chip: ia duduk di margin kosong sebelah kiri art, jadi
## tidak ada yang perlu dipisahkan dari latar oleh sebuah panel.
##
## `get_item_rect()` mengembalikan koordinat konten dan terukur TIDAK ikut
## bergeser saat list di-scroll, jadi offset scrollbar dikurangi sendiri; tanpa
## itu badge menempel di layar sementara kartunya jalan.
func _draw_level_badges() -> void:
	var font := _list.get_theme_font(&"font", &"ResourceValueLabel")
	var ink := _list.get_theme_color(&"font_color", &"ResourceValueLabel")
	var window := Rect2(Vector2.ZERO, _list.size)
	for index in _list.item_count:
		var text := _badge_text(index)
		if text.is_empty():
			continue
		var origin := _badge_origin(index)
		var text_size := font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BADGE_FONT_SIZE
		)
		if not window.intersects(Rect2(origin, text_size)):
			continue
		_list.draw_string(
			font,
			origin + Vector2(0.0, font.get_ascent(BADGE_FONT_SIZE)),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			BADGE_FONT_SIZE,
			ink
		)


func _badge_text(index: int) -> String:
	var row := GameState.as_dict(_list.get_item_metadata(index))
	if row.is_empty():
		return ""
	return LocaleManager.level_label(
		CareRules.level_from_exp(int(row.get("care_score", 0)))
	)


func _badge_origin(index: int) -> Vector2:
	return (
		_list.get_item_rect(index).position
		+ BADGE_INSET
		- Vector2(0.0, _list.get_v_scroll_bar().value)
	)


func _fill_identity() -> void:
	_sheet_name.text = LocaleManager.display_name(_selected_row)
	_sheet_meta.text = tr("COLLECTION_SHEET_META") % [
		LocaleManager.element_compact(_selected_row),
		LocaleManager.level_label(CareRules.level_from_exp(int(_selected_row.get("care_score", 0)))),
		LocaleManager.format_integer(int(_selected_row.get("rarity", 1))),
	]
	_sheet_portrait.texture = (
		_thumbnail_provider.call(_selected_row)
		if _thumbnail_provider.is_valid()
		else null
	)
	_update_evolution_cue()


func _update_evolution_cue() -> void:
	if CareRules.is_evolving(_selected_row):
		_condition_status.text = tr("COLLECTION_EVOLVING")
		_condition_status.visible = true
	elif _evolution_enabled and CareRules.evolution_ready(_selected_row):
		_condition_status.text = tr("COLLECTION_READY_EVOLVE")
		_condition_status.visible = true
	else:
		_condition_status.visible = false


func _fill_base_stats() -> void:
	var stats := GameState.as_dict(_selected_row.get("base_stats"))
	for key in _base_values:
		var value := _base_values[key] as Label
		value.text = LocaleManager.format_integer(
			CareRules.grown_stat_for_row(stats.get(key, 0), _selected_row)
		)


func _set_condition_loading() -> void:
	_condition_loading = true
	_condition_synced = false
	_condition_status.text = tr("COLLECTION_CONDITION_LOADING")
	_condition_status.visible = true
	_care_rows.visible = false
	_condition_skeleton.set_loading(true)
	for meter in _care_meters.values():
		var care_meter := meter as ProgressBar
		care_meter.value = 0.0
		care_meter.modulate = Color.WHITE
	_update_action_state()
	_sheet.fit_to_content()


func _apply_condition(row: Dictionary, synced: bool) -> void:
	var care := CareRules.normalized_care(row.get("care"))
	_condition_skeleton.set_loading(false)
	_care_rows.visible = not CareRules.is_evolving(row)
	for key in _care_meters:
		var meter := _care_meters[key] as ProgressBar
		meter.modulate = Color.WHITE
		if key == "exp":
			UiJuice.tween_meter(meter, CareRules.exp_progress(int(row.get("care_score", 0))))
		else:
			UiJuice.tween_meter(meter, float(care[key]))
	_condition_loading = false
	_condition_synced = synced
	if not synced:
		_condition_status.text = tr("COLLECTION_CONDITION_ERROR")
		_condition_status.visible = true
	else:
		_update_evolution_cue()
	_update_action_state()
	_sheet.fit_to_content()


func _update_active_state() -> void:
	var active := str(_selected_row.get("id", "")) == _active_id
	_active_badge.visible = active
	_summon_button.text = tr("COLLECTION_SUMMONED") if active else tr("COLLECTION_SUMMON")
	_update_action_state()


func _update_action_state() -> void:
	var has_selection := not _selected_row.is_empty()
	var active := has_selection and str(_selected_row.get("id", "")) == _active_id
	var evolving := has_selection and CareRules.is_evolving(_selected_row)
	_profile_button.disabled = _busy or not has_selection
	_summon_button.disabled = (
		_busy or _condition_loading or not has_selection or active or evolving
	)


func _view_profile() -> void:
	if _profile_button.disabled:
		return
	var row := _selected_row.duplicate(true)
	close_sheet()
	profile_requested.emit(row)


func _summon() -> void:
	if _summon_button.disabled:
		return
	summon_requested.emit(_selected_row.duplicate(true), _condition_synced)


func _on_empty_action() -> void:
	if _empty_mode == &"retry":
		retry_requested.emit()
	else:
		first_scan_requested.emit()


func _selection_matches(row: Dictionary, revision: int) -> bool:
	return (
		revision == _revision
		and _sheet.visible
		and str(row.get("id", "")) == str(_selected_row.get("id", ""))
	)


func _reveal_sheet(revision: int) -> void:
	if revision == _revision:
		_sheet.open()


static func _row_with_id(rows: Array[Dictionary], anima_id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id", "")) == anima_id:
			return row
	return {}
