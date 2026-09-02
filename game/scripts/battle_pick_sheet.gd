class_name BattlePickSheet
extends UiBottomSheet

signal profile_requested(row: Dictionary)
signal battle_requested(row: Dictionary)

const DIM := Color(1.0, 1.0, 1.0, 0.42)
## Sama dengan Collection: lantai lebar kartu, bukan jumlah kolom yang dipatok.
const CARD_MIN_WIDTH := 290.0

@onready var _title: Label = %BattlePickTitle
@onready var _empty: Label = %BattlePickEmpty
@onready var _list: ItemList = %BattlePickList
@onready var _detail: VBoxContainer = %BattlePickDetail
@onready var _portrait: TextureRect = %BattlePickPortrait
@onready var _name: Label = %BattlePickName
@onready var _meta: Label = %BattlePickMeta
@onready var _reason: Label = %BattlePickReason
@onready var _active_badge: Label = %BattlePickActive
@onready var _profile_button: Button = %BattlePickProfileButton
@onready var _battle_button: Button = %BattlePickBattleButton

var _active_id := ""
var _training := false
var _busy := false
var _thumbnail_provider: Callable
var _selected_row: Dictionary = {}


func _ready() -> void:
	super._ready()
	# Not `item_selected`: that fires on PRESS, so every attempt to scroll the
	# roster opened the detail page for whichever Anima the thumb landed on.
	UiJuice.install_item_list_touch_scroll(
		_list, _on_item_selected, _list.deselect_all
	)
	set_fill_child(_list)
	_list.resized.connect(_fit_columns)
	_fit_columns()
	_profile_button.pressed.connect(_on_profile)
	_battle_button.pressed.connect(_on_battle)
	dismissed.connect(_reset)


func _fit_columns() -> void:
	UiJuice.fit_item_grid(_list, CARD_MIN_WIDTH)


func open_picker(
	rows: Array,
	active_id: String,
	thumbnail_provider: Callable,
	training: bool
) -> void:
	_active_id = active_id
	_training = training
	_thumbnail_provider = thumbnail_provider
	_busy = false
	_fill_list(rows)
	_show_list()
	open()


func is_open() -> bool:
	return visible


func handle_back() -> bool:
	if not visible:
		return false
	if _detail.visible:
		_show_list()
		return true
	close()
	return true


func set_busy(busy: bool) -> void:
	_busy = busy
	_update_actions()


func _fill_list(rows: Array) -> void:
	_list.clear()
	for entry in rows:
		var row := GameState.as_dict(entry)
		if row.is_empty():
			continue
		var anima_name := LocaleManager.display_name(row)
		var level_label := LocaleManager.level_label(CareRules.level_from_exp(int(row.get("care_score", 0))))
		var unavailable := CareRules.battle_unavailable_key(row, _active_id, true)
		# Element is deliberately NOT in the grid row: measured on device,
		# "Drakabyss · Lv. 6 · Flow · Plant" needs more than the 290 px column,
		# so it clipped to an ellipsis AND leaked a second line over the art of
		# the row below. The detail panel already shows the element, and Level is
		# what the row was missing, so the row keeps name + Level and the reason
		# when there is one.
		# Both variants stay at two segments, because three did not fit: measured
		# on device, "Drowake · Lv. 16 · Sleeping" still wrapped past the 290 px
		# column and leaked its tail over the row below even with the cell
		# clipped to one line. An unavailable row leads with the REASON rather
		# than the Level -- that is the part the player has to act on.
		var label := (
			tr("COLLECTION_ITEM_META") % [
				anima_name, tr(CareRules.battle_pick_reason_key(unavailable))
			]
			if not unavailable.is_empty()
			else tr("COLLECTION_ITEM_META") % [anima_name, level_label]
		)
		var texture: Texture2D = (
			_thumbnail_provider.call(row) if _thumbnail_provider.is_valid() else null
		)
		_list.add_item(label, texture, true)
		var index := _list.item_count - 1
		_list.set_item_metadata(index, row)
		if not unavailable.is_empty():
			_list.set_item_icon_modulate(index, DIM)
	_empty.visible = _list.item_count == 0
	_list.visible = _list.item_count > 0


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	var row := GameState.as_dict(_list.get_item_metadata(index))
	if row.is_empty():
		return
	_selected_row = row
	_fill_detail()
	_show_detail()


func _fill_detail() -> void:
	var unavailable := CareRules.battle_unavailable_key(_selected_row, _active_id, true)
	_name.text = LocaleManager.display_name(_selected_row)
	_meta.text = tr("COLLECTION_SHEET_META") % [
		LocaleManager.element_compact(_selected_row),
		LocaleManager.level_label(CareRules.level_from_exp(int(_selected_row.get("care_score", 0)))),
		LocaleManager.format_integer(int(_selected_row.get("rarity", 1))),
	]
	_reason.text = tr(CareRules.battle_pick_reason_key(unavailable)) if not unavailable.is_empty() else ""
	_reason.visible = not unavailable.is_empty()
	_active_badge.visible = str(_selected_row.get("id", "")) == _active_id
	_portrait.texture = (
		_thumbnail_provider.call(_selected_row) if _thumbnail_provider.is_valid() else null
	)
	_battle_button.text = tr("BATTLE_TRAIN") if _training else tr("BATTLE_START")
	_update_actions()


func _update_actions() -> void:
	var has_row := not _selected_row.is_empty()
	var unavailable := (
		CareRules.battle_unavailable_key(_selected_row, _active_id, true) if has_row else "BATTLE_NO_ANIMA"
	)
	_profile_button.disabled = _busy or not has_row
	_battle_button.disabled = _busy or not has_row or not unavailable.is_empty()


func _show_list() -> void:
	_selected_row = {}
	_title.text = tr("BATTLE_CHOOSE_ANIMA")
	_detail.visible = false
	_empty.visible = _list.item_count == 0
	_list.visible = _list.item_count > 0
	if _list.item_count > 0:
		_list.deselect_all()
	_update_actions()
	fit_to_content()


func _show_detail() -> void:
	_title.text = tr("BATTLE_CHOOSE_ANIMA")
	_list.visible = false
	_empty.visible = false
	_detail.visible = true
	fit_to_content()


func _reset() -> void:
	_selected_row = {}
	_detail.visible = false


func _on_profile() -> void:
	if _profile_button.disabled:
		return
	var row := _selected_row.duplicate(true)
	close()
	profile_requested.emit(row)


func _on_battle() -> void:
	if _battle_button.disabled:
		return
	battle_requested.emit(_selected_row.duplicate(true))
