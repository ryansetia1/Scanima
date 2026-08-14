class_name GalleryView
extends Control

signal back_requested
signal toast_requested(message: String, is_error: bool)

const CARD_MIN := Vector2(300, 360)

@onready var _status: Label = %GalleryStatus
@onready var _grid: GridContainer = %GalleryGrid
@onready var _scroll: ScrollContainer = %GalleryScroll
@onready var _load_more: Button = %GalleryLoadMore
@onready var _detail_sheet: UiBottomSheet = %GalleryDetailSheet

var _entries: Array[Dictionary] = []
var _cursor: String = ""
var _busy := false
var _feature_enabled := true
var _selected: Dictionary = {}
var _detail_portrait: TextureRect
var _detail_name: Label
var _detail_meta: Label
var _detail_report: Button
var _detail_hide: Button
var _thumb_cache: Dictionary = {}


func _ready() -> void:
	%GalleryBack.pressed.connect(func() -> void: back_requested.emit())
	_load_more.pressed.connect(_load_next_page)
	_detail_sheet.dismissed.connect(_on_detail_closed)
	_build_detail_sheet()


func _build_detail_sheet() -> void:
	var slot := _detail_sheet.get_node("%ContentSlot") as VBoxContainer
	for child in slot.get_children():
		child.queue_free()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	slot.add_child(column)
	_detail_portrait = TextureRect.new()
	_detail_portrait.custom_minimum_size = Vector2(256, 256)
	_detail_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_detail_portrait)
	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"PageTitleLabel"
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail_name)
	_detail_meta = Label.new()
	_detail_meta.theme_type_variation = &"BodyLabel"
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail_meta)
	_detail_report = Button.new()
	_detail_report.custom_minimum_size.y = 96
	_detail_report.text = tr("GALLERY_REPORT")
	_detail_report.pressed.connect(_report_selected)
	column.add_child(_detail_report)
	_detail_hide = Button.new()
	_detail_hide.custom_minimum_size.y = 96
	_detail_hide.text = tr("GALLERY_HIDE")
	_detail_hide.pressed.connect(_hide_selected)
	column.add_child(_detail_hide)


func begin_visit() -> void:
	_entries.clear()
	_cursor = ""
	_clear_grid()
	_selected = {}
	if _detail_sheet.visible:
		_detail_sheet.close()
	_load_first_page()


func set_busy(busy: bool) -> void:
	_busy = busy
	_load_more.disabled = busy
	_detail_report.disabled = busy
	_detail_hide.disabled = busy


func refresh_localized_ui() -> void:
	%GalleryBack.text = tr("ACTION_BACK")
	_load_more.text = tr("GALLERY_LOAD_MORE")
	if _detail_report:
		_detail_report.text = tr("GALLERY_REPORT")
	if _detail_hide:
		_detail_hide.text = tr("GALLERY_HIDE")
	if not _entries.is_empty():
		_rebuild_grid()


func is_detail_open() -> bool:
	return _detail_sheet.visible


func close_detail() -> void:
	if _detail_sheet.visible:
		_detail_sheet.close()


func _load_first_page() -> void:
	_entries.clear()
	_cursor = ""
	_clear_grid()
	await _fetch_page(true)


func _load_next_page() -> void:
	if _cursor.is_empty() or _busy:
		return
	await _fetch_page(false)


func _fetch_page(reset_status: bool) -> void:
	if _busy:
		return
	set_busy(true)
	if reset_status:
		_status.text = tr("GALLERY_LOADING")
		_status.visible = true
		_scroll.visible = false
	var res := await Backend.gallery("list", {
		"cursor": _cursor if not reset_status else "",
		"limit": 24,
	})
	set_busy(false)
	if not res.ok:
		_status.text = tr("GALLERY_ERROR")
		_status.visible = true
		_scroll.visible = false
		_load_more.visible = false
		return
	var data := GameState.as_dict(res.data)
	_feature_enabled = bool(data.get("feature_enabled", true))
	if not _feature_enabled:
		_status.text = tr("GALLERY_DISABLED")
		_status.visible = true
		_scroll.visible = false
		_load_more.visible = false
		return
	var batch: Array = data.get("entries", [])
	for row in batch:
		if typeof(row) == TYPE_DICTIONARY:
			_entries.append(GameState.as_dict(row))
	_cursor = str(data.get("next_cursor", ""))
	_load_more.visible = not _cursor.is_empty()
	if _entries.is_empty():
		_status.text = tr("GALLERY_EMPTY")
		_status.visible = true
		_scroll.visible = false
	else:
		_status.visible = false
		_scroll.visible = true
		_rebuild_grid()


func _rebuild_grid() -> void:
	_clear_grid()
	for entry in _entries:
		_grid.add_child(_make_card(entry))


func _clear_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()


func _make_card(entry: Dictionary) -> Control:
	var button := Button.new()
	button.custom_minimum_size = CARD_MIN
	button.flat = true
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	button.add_child(column)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(280, 280)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(portrait)
	var name_label := Label.new()
	name_label.text = str(entry.get("display_name", tr("ANIMA_FALLBACK_NAME")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	var meta := Label.new()
	meta.text = tr("GALLERY_CARD_META") % [
		LocaleManager.element_compact(entry),
		LocaleManager.form_name(int(entry.get("stage", 1))),
	]
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.theme_type_variation = &"MutedLabel"
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(meta)
	var entry_id := str(entry.get("id", ""))
	button.pressed.connect(_open_detail.bind(entry.duplicate(true)))
	call_deferred("_load_card_thumb", entry_id, str(entry.get("thumb_url", "")), portrait)
	return button


func _load_card_thumb(entry_id: String, url: String, target: TextureRect) -> void:
	if not is_instance_valid(target):
		return
	var texture := await _thumb_texture(entry_id, url)
	if is_instance_valid(target) and texture != null:
		target.texture = texture


func _open_detail(entry: Dictionary) -> void:
	_selected = entry
	_detail_name.text = str(entry.get("display_name", tr("ANIMA_FALLBACK_NAME")))
	_detail_meta.text = tr("GALLERY_CARD_META") % [
		LocaleManager.element_compact(entry),
		LocaleManager.form_name(int(entry.get("stage", 1))),
	]
	_detail_portrait.texture = await _thumb_texture(
		str(entry.get("id", "")),
		str(entry.get("thumb_url", "")),
	)
	_detail_sheet.open()


func _on_detail_closed() -> void:
	_selected = {}


func _report_selected() -> void:
	if _selected.is_empty() or _busy:
		return
	var entry_id := str(_selected.get("id", ""))
	set_busy(true)
	var res := await Backend.gallery("report", {"entry_id": entry_id})
	set_busy(false)
	if res.ok:
		toast_requested.emit(tr("GALLERY_REPORTED"), false)
		_detail_sheet.close()
		_entries = _entries.filter(func(row: Dictionary) -> bool:
			return str(row.get("id", "")) != entry_id
		)
		_rebuild_grid()
	else:
		toast_requested.emit(tr("ERROR_" + res.error) if tr("ERROR_" + res.error) != "ERROR_" + res.error else tr("GALLERY_ERROR"), true)


func _hide_selected() -> void:
	if _selected.is_empty() or _busy:
		return
	set_busy(true)
	var entry_id := str(_selected.get("id", ""))
	var res := await Backend.gallery("hide", {"entry_id": entry_id})
	set_busy(false)
	if res.ok:
		toast_requested.emit(tr("GALLERY_HIDDEN"), false)
		_detail_sheet.close()
		_entries = _entries.filter(func(row: Dictionary) -> bool:
			return str(row.get("id", "")) != entry_id
		)
		_rebuild_grid()
	else:
		toast_requested.emit(tr("GALLERY_ERROR"), true)


func _thumb_texture(entry_id: String, url: String) -> Texture2D:
	if entry_id.is_empty() or url.is_empty():
		return null
	if _thumb_cache.has(entry_id):
		var cached: Variant = _thumb_cache[entry_id]
		if cached is Texture2D:
			return cached
	var disk := Backend.gallery_thumb_cache_path(entry_id)
	if FileAccess.file_exists(disk):
		var image := Image.load_from_file(disk)
		if image != null:
			var tex := ImageTexture.create_from_image(image)
			_thumb_cache[entry_id] = tex
			return tex
	var res := await Backend.download_url(url)
	if not res.ok:
		return null
	var stored := Backend.store_gallery_thumb(entry_id, res.bytes)
	if not stored.ok:
		return null
	var loaded := Image.load_from_file(disk)
	if loaded == null:
		return null
	var texture := ImageTexture.create_from_image(loaded)
	_thumb_cache[entry_id] = texture
	return texture
