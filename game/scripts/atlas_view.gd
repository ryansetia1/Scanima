class_name AtlasView
extends Control

signal back_requested
signal toast_requested(message: String, is_error: bool)

const CARD_MIN := Vector2(300, 360)
const SILHOUETTE_SHADER := preload("res://shaders/atlas_silhouette.gdshader")
const FILTERS := ["all", "scanned", "expedition", "duel"]
const FILTER_BUTTONS := {
	"all": "AtlasAll",
	"scanned": "AtlasScanned",
	"expedition": "AtlasExpedition",
	"duel": "AtlasDuel",
}
const STAT_KEYS := {
	"hp": "STAT_HP",
	"atk": "STAT_ATK",
	"def": "STAT_DEF",
	"spd": "STAT_SPD",
	"special": "STAT_SPECIAL",
}

@onready var _status: Label = %AtlasStatus
@onready var _grid: GridContainer = %AtlasGrid
@onready var _scroll: ScrollContainer = %AtlasScroll
@onready var _load_more: Button = %AtlasLoadMore
@onready var _filters: HBoxContainer = %AtlasFilters
@onready var _chapter: OptionButton = %AtlasChapter
@onready var _detail_sheet: UiBottomSheet = %AtlasDetailSheet

var _entries: Array[Dictionary] = []
var _chapters: Array[Dictionary] = []
var _cursor := ""
var _filter := "all"
var _chapter_id := ""
var _busy := false
var _selected: Dictionary = {}
var _detail_portrait: TextureRect
var _detail_name: Label
var _detail_meta: Label
var _detail_report: Button
var _thumb_cache: Dictionary = {}
var _silhouette_material: ShaderMaterial


func _ready() -> void:
	%AtlasBack.pressed.connect(func() -> void: back_requested.emit())
	_load_more.pressed.connect(_load_next_page)
	_detail_sheet.dismissed.connect(_on_detail_closed)
	_chapter.item_selected.connect(_on_chapter_selected)
	for filter_name: String in FILTERS:
		var button := get_node("%%%s" % FILTER_BUTTONS[filter_name]) as Button
		button.pressed.connect(_select_filter.bind(filter_name))
	var column := _status.get_parent()
	column.move_child(_filters, 1)
	column.move_child(_chapter, 2)
	_build_detail_sheet()
	_sync_filter_buttons()


func _build_detail_sheet() -> void:
	var slot := _detail_sheet.get_node("%ContentSlot") as VBoxContainer
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	slot.add_child(column)
	_detail_portrait = TextureRect.new()
	_detail_portrait.custom_minimum_size = Vector2(288, 288)
	_detail_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_detail_portrait)
	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"PageTitleLabel"
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_name)
	_detail_meta = Label.new()
	_detail_meta.theme_type_variation = &"BodyLabel"
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_meta)
	_detail_report = Button.new()
	_detail_report.custom_minimum_size.y = 96
	_detail_report.text = tr("ATLAS_REPORT")
	_detail_report.pressed.connect(_report_selected)
	column.add_child(_detail_report)


func begin_visit() -> void:
	_entries.clear()
	_chapters.clear()
	_cursor = ""
	_filter = "all"
	_chapter_id = ""
	_selected = {}
	_sync_filter_buttons()
	_chapter.visible = false
	if _detail_sheet.visible:
		_detail_sheet.close()
	_load_first_page()


func show_demo(rows: Array[Dictionary], texture: Texture2D) -> void:
	set_busy(false)
	_cursor = ""
	_entries.assign(rows)
	_chapters.clear()
	_filter = "all"
	_chapter_id = ""
	_selected = {}
	_sync_filter_buttons()
	_chapter.visible = false
	for row: Dictionary in rows:
		_thumb_cache[str(row.get("form_id", ""))] = texture
	_rebuild_grid()
	_status.text = tr("ATLAS_DEMO_STATUS") % rows.size()


func set_busy(busy: bool) -> void:
	_busy = busy
	_load_more.disabled = busy
	_chapter.disabled = busy
	for filter_name: String in FILTERS:
		(get_node("%%%s" % FILTER_BUTTONS[filter_name]) as Button).disabled = busy
	if is_instance_valid(_detail_report):
		_detail_report.disabled = busy


func refresh_localized_ui() -> void:
	%AtlasBack.text = tr("ACTION_BACK")
	_load_more.text = tr("ATLAS_LOAD_MORE")
	for filter_name: String in FILTERS:
		var button := get_node("%%%s" % FILTER_BUTTONS[filter_name]) as Button
		button.text = tr("ATLAS_FILTER_%s" % filter_name.to_upper())
	if is_instance_valid(_detail_report):
		_detail_report.text = tr("ATLAS_REPORT")
	_populate_chapter_picker()
	if not _entries.is_empty():
		_rebuild_grid()


func is_detail_open() -> bool:
	return _detail_sheet.visible


func close_detail() -> void:
	if _detail_sheet.visible:
		_detail_sheet.close()


func _select_filter(filter_name: String) -> void:
	if _busy or filter_name == _filter or filter_name not in FILTERS:
		return
	_filter = filter_name
	if _filter != "expedition":
		_chapter_id = ""
	_sync_filter_buttons()
	await _load_first_page()


func _sync_filter_buttons() -> void:
	for filter_name: String in FILTERS:
		var button := get_node_or_null("%%%s" % FILTER_BUTTONS[filter_name]) as Button
		if button != null:
			button.button_pressed = filter_name == _filter
	if is_instance_valid(_chapter):
		_chapter.visible = _filter == "expedition" and not _chapters.is_empty()


func _on_chapter_selected(index: int) -> void:
	if _busy or index < 0 or index >= _chapter.item_count:
		return
	var next_id := str(_chapter.get_item_metadata(index))
	if next_id == _chapter_id:
		return
	_chapter_id = next_id
	await _load_first_page()


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
		_status.text = tr("ATLAS_LOADING")
		_status.visible = true
		_scroll.visible = false
	var payload := {
		"filter": _filter,
		"cursor": _cursor if not reset_status else "",
		"limit": 24,
	}
	if _filter == "expedition" and not _chapter_id.is_empty():
		payload["chapter_id"] = _chapter_id
	var res := await Backend.atlas("atlas_list", payload)
	set_busy(false)
	if not res.ok:
		_status.text = tr("ATLAS_ERROR")
		_status.visible = true
		_scroll.visible = false
		_load_more.visible = false
		return
	var data := GameState.as_dict(res.data)
	if not bool(data.get("feature_enabled", true)):
		_status.text = tr("ATLAS_DISABLED")
		_status.visible = true
		_scroll.visible = false
		_load_more.visible = false
		return
	_read_chapters(data.get("chapters", []))
	if _filter == "expedition" and _chapter_id.is_empty() and not _chapters.is_empty():
		_chapter_id = str(_chapters[0].get("id", ""))
		_populate_chapter_picker()
		await _load_first_page()
		return
	var batch: Array = data.get("entries", [])
	for row in batch:
		if typeof(row) == TYPE_DICTIONARY:
			_entries.append(GameState.as_dict(row))
	_cursor = str(data.get("next_cursor", ""))
	_load_more.visible = not _cursor.is_empty()
	if _entries.is_empty():
		_status.text = tr("ATLAS_EMPTY")
		_status.visible = true
		_scroll.visible = false
	else:
		_status.visible = false
		_scroll.visible = true
		_rebuild_grid()


func _read_chapters(value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	_chapters.clear()
	for row in value as Array:
		if typeof(row) == TYPE_DICTIONARY:
			_chapters.append(GameState.as_dict(row))
	_populate_chapter_picker()


func _populate_chapter_picker() -> void:
	if not is_instance_valid(_chapter):
		return
	_chapter.clear()
	var selected := -1
	for row in _chapters:
		var slug := str(row.get("slug", ""))
		var title := slug.replace("-", " ").capitalize()
		var index := _chapter.item_count
		_chapter.add_item(tr("ATLAS_CHAPTER_OPTION") % [
			title,
			LocaleManager.format_integer(int(row.get("discovered", 0))),
			LocaleManager.format_integer(int(row.get("total", 0))),
		])
		_chapter.set_item_metadata(index, str(row.get("id", "")))
		if str(row.get("id", "")) == _chapter_id:
			selected = index
	if selected >= 0:
		_chapter.select(selected)
	_chapter.visible = _filter == "expedition" and _chapter.item_count > 0


func _rebuild_grid() -> void:
	_clear_grid()
	for entry in _entries:
		_grid.add_child(_make_card(entry))


func _clear_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()


func _make_card(entry: Dictionary) -> Control:
	var discovered := bool(entry.get("discovered", false))
	var button := Button.new()
	button.custom_minimum_size = CARD_MIN
	button.flat = true
	button.disabled = not discovered
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	button.add_child(column)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(280, 280)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not discovered:
		portrait.material = _get_silhouette_material()
	column.add_child(portrait)
	var name_label := Label.new()
	name_label.text = str(entry.get("display_name", "???")) if discovered else "???"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	var meta := Label.new()
	meta.text = (
		tr("ATLAS_CARD_META") % [
			_atlas_element_label(entry),
			_stage_name(int(entry.get("stage", 1))),
		]
		if discovered
		else tr("ATLAS_UNDISCOVERED")
	)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.theme_type_variation = &"MutedLabel"
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(meta)
	var form_id := str(entry.get("form_id", ""))
	if discovered:
		button.pressed.connect(_open_detail.bind(entry.duplicate(true)))
	call_deferred("_load_card_art", entry.duplicate(true), portrait)
	button.tooltip_text = tr("ATLAS_CARD_OPEN") if discovered else tr("ATLAS_UNDISCOVERED")
	button.set_meta("form_id", form_id)
	return button


func _get_silhouette_material() -> ShaderMaterial:
	if _silhouette_material == null:
		_silhouette_material = ShaderMaterial.new()
		_silhouette_material.shader = SILHOUETTE_SHADER
	return _silhouette_material


func _load_card_art(entry: Dictionary, target: TextureRect) -> void:
	if not is_instance_valid(target):
		return
	var texture := await _entry_texture(entry)
	if is_instance_valid(target) and texture != null:
		target.texture = texture


func _open_detail(card: Dictionary) -> void:
	if _busy:
		return
	var form_id := str(card.get("form_id", ""))
	if form_id.is_empty():
		return
	set_busy(true)
	var res := await Backend.atlas("atlas_detail", {"form_id": form_id})
	set_busy(false)
	if not res.ok:
		toast_requested.emit(tr("ATLAS_DETAIL_ERROR"), true)
		return
	_selected = GameState.as_dict(GameState.as_dict(res.data).get("entry"))
	if _selected.is_empty():
		toast_requested.emit(tr("ATLAS_DETAIL_ERROR"), true)
		return
	_detail_name.text = str(_selected.get("display_name", tr("ANIMA_FALLBACK_NAME")))
	_detail_meta.text = _detail_copy(_selected)
	_detail_report.visible = bool(_selected.get("can_report", false))
	_detail_portrait.texture = await _entry_texture(_selected)
	_detail_sheet.open()


func _detail_copy(entry: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(tr("ATLAS_DETAIL_FORM") % _stage_name(int(entry.get("stage", 1))))
	lines.append(tr("ATLAS_DETAIL_ELEMENTS") % _atlas_element_label(entry))
	var subject_key := "ATLAS_SUBJECT_%s" % str(entry.get("subject_kind", "object")).to_upper()
	lines.append(tr("ATLAS_DETAIL_TRAITS") % [
		tr(subject_key),
		LocaleManager.format_ratio(int(entry.get("rarity", 1)), 5),
	])
	lines.append(tr("ATLAS_DETAIL_HEIGHT") % LocaleManager.format_integer(int(entry.get("body_height_cm", 0))))
	var stats := GameState.as_dict(entry.get("base_stats"))
	var stat_parts: Array[String] = []
	for key: String in ["hp", "atk", "def", "spd", "special"]:
		stat_parts.append("%s %s" % [tr(STAT_KEYS[key]), LocaleManager.format_integer(int(stats.get(key, 0)))])
	lines.append(tr("ATLAS_DETAIL_ATTRIBUTES") % " · ".join(stat_parts))
	lines.append(tr("ATLAS_DETAIL_ATTACK") % LocaleManager.move_name(entry, "strike"))
	lines.append(tr("ATLAS_DETAIL_SPECIAL") % LocaleManager.move_name(entry, "surge"))
	var owner_name := str(entry.get("owner_name", ""))
	if not owner_name.is_empty():
		lines.append(tr("ATLAS_DETAIL_OWNER") % owner_name)
	lines.append(tr("ATLAS_DETAIL_ENCOUNTERS") % LocaleManager.format_integer(int(entry.get("encounter_count", 1))))
	return "\n\n".join(lines)


func _stage_name(stage: int) -> String:
	match clampi(stage, 1, 3):
		2:
			return tr("FORM_ADULT")
		3:
			return tr("FORM_EVOLVED")
		_:
			return tr("FORM_HATCHLING")


func _atlas_element_label(entry: Dictionary) -> String:
	var display := entry.duplicate()
	display["typing_version"] = 2 if not str(entry.get("secondary_element", "")).is_empty() else 1
	return LocaleManager.element_compact(display)


func _on_detail_closed() -> void:
	_selected = {}


func _report_selected() -> void:
	if _selected.is_empty() or _busy or not bool(_selected.get("can_report", false)):
		return
	var entry_id := str(_selected.get("entry_id", ""))
	if entry_id.is_empty():
		return
	set_busy(true)
	var res := await Backend.atlas("report", {"entry_id": entry_id})
	set_busy(false)
	if res.ok:
		toast_requested.emit(tr("ATLAS_REPORTED"), false)
		_detail_sheet.close()
		await _load_first_page()
	else:
		var key := "ERROR_" + str(res.error)
		toast_requested.emit(tr(key) if tr(key) != key else tr("ATLAS_ERROR"), true)


func _entry_texture(entry: Dictionary) -> Texture2D:
	var form_id := str(entry.get("form_id", ""))
	if form_id.is_empty():
		return null
	if _thumb_cache.has(form_id):
		var cached: Variant = _thumb_cache[form_id]
		if cached is Texture2D:
			return cached
	var disk := Backend.atlas_thumb_cache_path(form_id)
	if FileAccess.file_exists(disk):
		var cached_image := Image.load_from_file(disk)
		if cached_image != null:
			var cached_texture := ImageTexture.create_from_image(cached_image)
			_thumb_cache[form_id] = cached_texture
			return cached_texture
	var thumb_url := str(entry.get("thumb_url", ""))
	var sheet_url := str(entry.get("sheet_url", ""))
	var url := thumb_url if not thumb_url.is_empty() else sheet_url
	if url.is_empty():
		return null
	var res := await Backend.download_url(url)
	if not res.ok or res.bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(res.bytes) != OK:
		return null
	if thumb_url.is_empty():
		image = _crop_idle(image, GameState.as_dict(entry.get("card_manifest", entry.get("manifest", {}))))
	image.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var stored := Backend.store_atlas_thumb(form_id, image.save_png_to_buffer())
	if not stored.ok:
		return null
	var texture := ImageTexture.create_from_image(image)
	_thumb_cache[form_id] = texture
	return texture


static func _crop_idle(image: Image, manifest: Dictionary) -> Image:
	var idle := GameState.as_dict(GameState.as_dict(manifest.get("poses")).get("idle"))
	var region: Array = idle.get("region", [])
	if region.size() != 4:
		return image
	var rect := Rect2i(
		int(region[0]), int(region[1]),
		int(region[2]), int(region[3])
	)
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	if rect.size.x <= 0 or rect.size.y <= 0 or not bounds.encloses(rect):
		return image
	return image.get_region(rect)
