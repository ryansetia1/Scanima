class_name CollectionView
extends Control

signal anima_selected(row: Dictionary)

@onready var _status: Label = %CollectionStatus
@onready var _list: ItemList = %AnimaList


func _ready() -> void:
	_list.item_selected.connect(_on_item_selected)


func set_rows(rows: Array[Dictionary], active_id: String, thumbnail_provider: Callable) -> void:
	_list.clear()
	var selected := -1
	for row in rows:
		var id := str(row.get("id", ""))
		var name := LocaleManager.display_name(row)
		var label := tr("COLLECTION_ITEM_META") % [
			name,
			LocaleManager.element_name(str(row.get("element", ""))),
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
	_status.text = (
		tr("COLLECTION_EMPTY")
		if rows.is_empty()
		else tr("COLLECTION_COUNT") % LocaleManager.format_integer(rows.size())
	)


func set_error() -> void:
	_status.text = tr("STATUS_ROSTER_ERROR")


func set_busy(busy: bool) -> void:
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	var row := GameState.as_dict(_list.get_item_metadata(index))
	if not row.is_empty():
		anima_selected.emit(row)
