class_name AtlasView
extends Control

signal back_requested
signal collection_requested
signal synthesis_requested
signal toast_requested(message: String, is_error: bool)

## `x` adalah lantai lebar kolom yang dipakai `_fit_columns()`, `y` tinggi kartu.
const CARD_MIN := Vector2(208, 280)
const CARD_PORTRAIT_HEIGHT := 196.0
const VISIT_CACHE_TTL_MSEC := 60_000
const LOADING_SHIMMER_SEC := 0.72
const DETAIL_IDLE_SEC := 1.6
const DETAIL_IDLE_AMOUNT := 0.045
const SILHOUETTE_SHADER := preload("res://shaders/atlas_silhouette.gdshader")
const LOADING_SHIMMER_SHADER := preload("res://shaders/guard_shimmer.gdshader")
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
const REPORT_CATEGORIES := ["character", "sexual", "gore", "hate", "other"]
const REPORT_CATEGORY_KEYS := {
	"character": "ATLAS_REPORT_CATEGORY_CHARACTER",
	"sexual": "ATLAS_REPORT_CATEGORY_SEXUAL",
	"gore": "ATLAS_REPORT_CATEGORY_GORE",
	"hate": "ATLAS_REPORT_CATEGORY_HATE",
	"other": "ATLAS_REPORT_CATEGORY_OTHER",
}

@onready var _status: Label = %AtlasStatus
@onready var _grid: GridContainer = %AtlasGrid
@onready var _scroll: ScrollContainer = %AtlasScroll
@onready var _load_more: Button = %AtlasLoadMore
@onready var _filters: HBoxContainer = %AtlasFilters
@onready var _chapter: OptionButton = %AtlasChapter
@onready var _detail_sheet: UiBottomSheet = %AtlasDetailSheet
@onready var _report_sheet: UiBottomSheet = %AtlasReportSheet

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
var _report_entry_id := ""
var _report_category_buttons: Dictionary = {}
var _report_sheet_cancel: Button
var _report_sheet_title: Label
var _report_sheet_body: Label
var _detail_owner_cell: PanelContainer
var _detail_discovery_grid: GridContainer
var _detail_values: Dictionary = {}
var _loading_portrait: TextureRect
var _loading_material: ShaderMaterial
var _loading_previous_material: Material
var _loading_shimmer: Tween
var _detail_idle: Tween
var _thumb_cache: Dictionary = {}
var _silhouette_material: ShaderMaterial
var _all_entries_cache: Array[Dictionary] = []
var _all_cache_loaded := false
var _all_cache_complete := false
var _all_cache_at_msec := 0


func _ready() -> void:
	%AtlasCollectionTab.pressed.connect(func() -> void: collection_requested.emit())
	%AtlasSynthesisTab.pressed.connect(func() -> void: synthesis_requested.emit())
	_load_more.pressed.connect(_load_next_page)
	_detail_sheet.dismissed.connect(_on_detail_closed)
	_report_sheet.dismissed.connect(_on_report_sheet_closed)
	_chapter.item_selected.connect(_on_chapter_selected)
	for filter_name: String in FILTERS:
		var button := get_node("%%%s" % FILTER_BUTTONS[filter_name]) as Button
		button.pressed.connect(_select_filter.bind(filter_name))
	var column := _status.get_parent()
	var tabs := column.get_node("CollectionTabs") as HBoxContainer
	column.move_child(_filters, tabs.get_index() + 1)
	column.move_child(_chapter, _filters.get_index() + 1)
	_build_detail_sheet()
	_build_report_sheet()
	_sync_filter_buttons()
	_scroll.resized.connect(_fit_columns)
	_fit_columns()


## Tiga kolom yang dipatok scene meninggalkan sisa lebar kosong di kanan begitu
## layarnya lebih lebar dari basis 720 px. Kolomnya dihitung dari lebar yang
## ada; kartunya sendiri `SIZE_EXPAND_FILL`, jadi sisa yang tidak genap satu
## kolom dibagi rata alih-alih menumpuk di tepi.
func _fit_columns() -> void:
	# Diukur dari ScrollContainer, bukan dari grid-nya sendiri. `AtlasScroll`
	# mematikan scroll horizontal, dan `ScrollContainer` yang begitu mengangkat
	# minimum width anaknya menjadi minimum-nya sendiri. Mengukur `_grid.size.x`
	# karena itu membaca kembali angka yang fungsi ini sendiri tetapkan: kolom
	# naik -> grid menuntut `columns x CARD_MIN.x` -> lebar grid tidak pernah
	# bisa turun lagi saat jendela menyempit, jadi kolomnya terkunci di layar
	# terlebar yang pernah dilihat dan seluruh view melewati tepi layar. Lebar
	# di sini datang dari atas, dan kartunya hanya memesan tinggi.
	# Ruang scrollbar dipesan tanpa syarat, sama seperti `fit_item_grid()`.
	var inner := _scroll.size.x - _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	# Grid kosong tidak punya apa pun untuk dibagi; nilai scene-nya dibiarkan.
	if inner <= 0.0 or _grid.get_child_count() == 0:
		return
	# Dibatasi jumlah kartu: kolom kosong tetap mengambil bagiannya dari lebar,
	# jadi tanpa batas ini empat form di layar lebar berkumpul di kiri. Dengan
	# batas ini kartunya `SIZE_EXPAND_FILL` membagi seluruh lebar rata.
	_grid.columns = mini(
		UiJuice.grid_columns_for(
			inner, CARD_MIN.x, float(_grid.get_theme_constant(&"h_separation"))
		),
		_grid.get_child_count()
	)


func _build_detail_sheet() -> void:
	var slot := _detail_sheet.get_node("%ContentSlot") as VBoxContainer
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	slot.add_child(column)

	_detail_portrait = TextureRect.new()
	_detail_portrait.name = "AtlasDetailPortrait"
	_detail_portrait.custom_minimum_size = Vector2(240, 240)
	_detail_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_detail_portrait)

	_detail_name = Label.new()
	_detail_name.name = "AtlasDetailName"
	_detail_name.theme_type_variation = &"PageTitleLabel"
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_name)
	_detail_meta = Label.new()
	_detail_meta.name = "AtlasDetailIdentity"
	_detail_meta.theme_type_variation = &"BodyLabel"
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_meta)

	var traits := _make_detail_section(column, "AtlasAboutPanel", "DETAILS_TRAITS")
	var traits_grid := GridContainer.new()
	traits_grid.name = "AtlasTraitsGrid"
	traits_grid.columns = 2
	traits_grid.add_theme_constant_override("h_separation", 8)
	traits_grid.add_theme_constant_override("v_separation", 8)
	traits.add_child(traits_grid)
	_add_detail_value(traits_grid, "form", "ATLAS_DETAIL_FORM_LABEL")
	_add_detail_value(traits_grid, "kind", "ATLAS_DETAIL_KIND_LABEL")
	_add_detail_value(traits_grid, "rarity", "DETAILS_RARITY")
	_add_detail_value(traits_grid, "height", "ATLAS_DETAIL_HEIGHT_LABEL")

	var combat := _make_detail_section(column, "AtlasCombatPanel", "DETAILS_ATTRIBUTES")
	var stats_grid := GridContainer.new()
	stats_grid.name = "AtlasStatsGrid"
	stats_grid.columns = 5
	stats_grid.add_theme_constant_override("h_separation", 8)
	combat.add_child(stats_grid)
	for key: String in ["hp", "atk", "def", "spd", "special"]:
		_add_detail_value(stats_grid, key, STAT_KEYS[key], true)
	var moves_grid := GridContainer.new()
	moves_grid.name = "AtlasMovesGrid"
	moves_grid.columns = 2
	moves_grid.add_theme_constant_override("h_separation", 8)
	combat.add_child(moves_grid)
	_add_detail_value(moves_grid, "strike", "DETAILS_STRIKE")
	_add_detail_value(moves_grid, "surge", "DETAILS_SURGE")

	var discovery := _make_detail_section(column, "AtlasDiscoveryPanel", "ATLAS_DETAIL_DISCOVERY")
	_detail_discovery_grid = GridContainer.new()
	_detail_discovery_grid.name = "AtlasDiscoveryGrid"
	_detail_discovery_grid.columns = 2
	_detail_discovery_grid.add_theme_constant_override("h_separation", 8)
	discovery.add_child(_detail_discovery_grid)
	_detail_owner_cell = _add_detail_value(
		_detail_discovery_grid, "owner", "ATLAS_DETAIL_SEEKER_LABEL"
	)
	_add_detail_value(
		_detail_discovery_grid, "encounters", "ATLAS_DETAIL_ENCOUNTERS_LABEL"
	)

	var report_row := HBoxContainer.new()
	report_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(report_row)
	_detail_report = Button.new()
	_detail_report.name = "AtlasReportButton"
	_detail_report.custom_minimum_size = Vector2(180, 96)
	_detail_report.flat = true
	_detail_report.text = tr("ATLAS_REPORT")
	_detail_report.add_theme_color_override("font_color", Color(1, 0.42, 0.52, 0.88))
	_detail_report.add_theme_color_override("font_hover_color", Color(1, 0.72, 0.78, 1))
	_detail_report.add_theme_color_override("font_focus_color", Color(1, 0.72, 0.78, 1))
	_detail_report.add_theme_color_override("font_pressed_color", Color(1, 0.82, 0.4, 1))
	_detail_report.add_theme_font_size_override("font_size", 24)
	_detail_report.pressed.connect(_open_report_sheet)
	report_row.add_child(_detail_report)


func _build_report_sheet() -> void:
	var slot := _report_sheet.get_node("%ContentSlot") as VBoxContainer
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	_report_category_buttons.clear()
	var column := VBoxContainer.new()
	column.name = "AtlasReportSheetColumn"
	column.add_theme_constant_override("separation", 12)
	slot.add_child(column)

	_report_sheet_title = Label.new()
	_report_sheet_title.name = "AtlasReportSheetTitle"
	_report_sheet_title.theme_type_variation = &"PageTitleLabel"
	_report_sheet_title.text = tr("ATLAS_REPORT_SHEET_TITLE")
	_report_sheet_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_sheet_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_report_sheet_title)

	_report_sheet_body = Label.new()
	_report_sheet_body.name = "AtlasReportSheetBody"
	_report_sheet_body.theme_type_variation = &"BodyLabel"
	_report_sheet_body.text = tr("ATLAS_REPORT_SHEET_BODY")
	_report_sheet_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_sheet_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_report_sheet_body)

	for category: String in REPORT_CATEGORIES:
		var button := Button.new()
		button.name = "AtlasReportCategory%s" % category.capitalize()
		button.custom_minimum_size = Vector2(0, 96)
		button.theme_type_variation = &"SecondaryButton"
		button.text = tr(REPORT_CATEGORY_KEYS[category])
		button.pressed.connect(_submit_report.bind(category))
		column.add_child(button)
		_report_category_buttons[category] = button

	_report_sheet_cancel = Button.new()
	_report_sheet_cancel.name = "AtlasReportSheetCancel"
	_report_sheet_cancel.custom_minimum_size = Vector2(0, 72)
	_report_sheet_cancel.flat = true
	_report_sheet_cancel.text = tr("ACTION_CANCEL")
	_report_sheet_cancel.pressed.connect(func() -> void: _report_sheet.close())
	column.add_child(_report_sheet_cancel)


func _make_detail_section(parent: VBoxContainer, node_name: String, title_key: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.theme_type_variation = &"HudSurface"
	parent.add_child(panel)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	panel.add_child(section)
	var title := Label.new()
	title.theme_type_variation = &"SectionLabel"
	title.text = tr(title_key)
	section.add_child(title)
	return section


func _add_detail_value(
	parent: GridContainer, key: String, label_key: String, compact := false
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Atlas%sCell" % key.capitalize()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.theme_type_variation = &"StatValuePanel"
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var name_label := Label.new()
	name_label.theme_type_variation = &"StatNameLabel"
	name_label.text = tr(label_key)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if compact:
		name_label.add_theme_font_size_override("font_size", 19)
	box.add_child(name_label)
	var value_label := Label.new()
	value_label.name = "Atlas%sValue" % key.capitalize()
	value_label.theme_type_variation = &"StatValueLabel"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if compact:
		value_label.add_theme_font_size_override("font_size", 25)
	box.add_child(value_label)
	_detail_values[key] = value_label
	return panel


func begin_visit() -> void:
	_cursor = ""
	_filter = "all"
	_chapter_id = ""
	_selected = {}
	%AtlasAtlasTab.button_pressed = true
	%AtlasCollectionTab.button_pressed = false
	%AtlasSynthesisTab.button_pressed = false
	if _detail_sheet.visible:
		_detail_sheet.close()
	if (
		_all_cache_loaded
		and _all_cache_complete
		and Time.get_ticks_msec() - _all_cache_at_msec <= VISIT_CACHE_TTL_MSEC
	):
		_sync_filter_buttons()
		_project_all_cache()
		return
	_entries.clear()
	_chapters.clear()
	_sync_filter_buttons()
	_chapter.visible = false
	_load_first_page()


func set_synthesis_enabled(enabled: bool) -> void:
	%AtlasSynthesisTab.visible = enabled


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
	for category: String in _report_category_buttons:
		(_report_category_buttons[category] as Button).disabled = busy


func refresh_localized_ui() -> void:
	%AtlasTitle.text = tr("ATLAS_TITLE")
	%AtlasSubtitle.text = tr("ATLAS_SUBTITLE")
	%AtlasCollectionTab.text = tr("COLLECTION_TAB_COLLECTION")
	%AtlasSynthesisTab.text = tr("COLLECTION_TAB_SYNTHESIS")
	%AtlasAtlasTab.text = tr("COLLECTION_TAB_ATLAS")
	_load_more.text = tr("ATLAS_LOAD_MORE")
	for filter_name: String in FILTERS:
		var button := get_node("%%%s" % FILTER_BUTTONS[filter_name]) as Button
		button.text = tr("ATLAS_FILTER_%s" % filter_name.to_upper())
	if is_instance_valid(_detail_report):
		_detail_report.text = tr("ATLAS_REPORT")
	if is_instance_valid(_report_sheet_cancel):
		_report_sheet_title.text = tr("ATLAS_REPORT_SHEET_TITLE")
		_report_sheet_body.text = tr("ATLAS_REPORT_SHEET_BODY")
		for category: String in _report_category_buttons:
			(_report_category_buttons[category] as Button).text = tr(
				REPORT_CATEGORY_KEYS[category]
			)
		_report_sheet_cancel.text = tr("ACTION_CANCEL")
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
	if _filter == "expedition":
		_ensure_default_chapter()
	_sync_filter_buttons()
	if _project_all_cache():
		return
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
	if _project_all_cache():
		return
	await _load_first_page()


func reset_account_context() -> void:
	set_busy(false)
	_clear_card_loading()
	_entries.clear()
	_selected = {}
	_cursor = ""
	_all_entries_cache.clear()
	_all_cache_loaded = false
	_all_cache_complete = false
	_thumb_cache.clear()


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
	var account_epoch := GameState.session_epoch
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
	if not Backend.response_applies(res, account_epoch):
		return
	set_busy(false)
	if not res.ok:
		_status.text = tr("ATLAS_ERROR")
		_status.visible = true
		_scroll.visible = not _entries.is_empty()
		_load_more.visible = not _entries.is_empty() and not _cursor.is_empty()
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
	var next_cursor: Variant = data.get("next_cursor")
	_cursor = (next_cursor as String) if typeof(next_cursor) == TYPE_STRING else ""
	if batch.is_empty():
		_cursor = ""
	if reset_status and _filter == "all":
		_all_entries_cache.assign(_entries)
		_all_cache_loaded = true
		_all_cache_complete = _cursor.is_empty()
		_all_cache_at_msec = Time.get_ticks_msec()
	_present_entries()


func _ensure_default_chapter() -> void:
	if not _chapter_id.is_empty() or _chapters.is_empty():
		return
	_chapter_id = str(_chapters[0].get("id", ""))
	_populate_chapter_picker()


func _project_all_cache() -> bool:
	if not _all_cache_loaded or not _all_cache_complete:
		return false
	_entries.clear()
	for entry in _all_entries_cache:
		var include := _filter == "all"
		if _filter == "scanned" or _filter == "duel":
			include = str(entry.get("discovery_source", "")) == _filter
		elif _filter == "expedition":
			include = (
				str(entry.get("source_kind", "")) == "expedition"
				and (_chapter_id.is_empty() or str(entry.get("chapter_id", "")) == _chapter_id)
			)
		if include:
			_entries.append(entry)
	_cursor = ""
	_present_entries()
	return true


func _present_entries() -> void:
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
	# Jumlah kolom dibatasi jumlah kartu, jadi ia berubah saat isinya berubah —
	# bukan hanya saat layarnya berubah ukuran.
	_fit_columns()


func _clear_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()


func _make_card(entry: Dictionary) -> Control:
	var discovered := bool(entry.get("discovered", false))
	var button := Button.new()
	# Hanya tinggi yang dipesan. `CARD_MIN.x` tetap dipakai, tapi sebagai lantai
	# lebar *kolom* di `_fit_columns()` — memesannya di kartu juga membuat grid
	# menuntut `columns x CARD_MIN.x` lewat ScrollContainer yang scroll
	# horizontalnya mati, dan itu yang mengunci kolomnya.
	button.custom_minimum_size = Vector2(0.0, CARD_MIN.y)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.flat = true
	button.disabled = not discovered
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	button.add_child(column)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(0.0, CARD_PORTRAIT_HEIGHT)
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
	meta.text = LocaleManager.element_compact(entry) if discovered else tr("ATLAS_UNDISCOVERED")
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.theme_type_variation = &"MutedLabel"
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(meta)
	var form_id := str(entry.get("form_id", ""))
	if discovered:
		button.pressed.connect(_open_detail.bind(entry.duplicate(true), portrait))
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


func _set_card_loading(target: TextureRect, loading: bool) -> void:
	_clear_card_loading()
	if not loading or not is_instance_valid(target):
		return
	_loading_portrait = target
	_loading_previous_material = target.material
	_loading_material = ShaderMaterial.new()
	_loading_material.shader = LOADING_SHIMMER_SHADER
	_loading_material.set_shader_parameter("progress", 0.0)
	target.material = _loading_material
	_loading_shimmer = create_tween().set_loops()
	_loading_shimmer.tween_property(
		_loading_material,
		"shader_parameter/progress",
		1.0,
		LOADING_SHIMMER_SEC
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
	_loading_shimmer.tween_callback(func() -> void:
		if _loading_material != null:
			_loading_material.set_shader_parameter("progress", 0.0)
	)


func _clear_card_loading() -> void:
	if _loading_shimmer != null and _loading_shimmer.is_valid():
		_loading_shimmer.kill()
	_loading_shimmer = null
	if (
		is_instance_valid(_loading_portrait)
		and _loading_portrait.material == _loading_material
	):
		_loading_portrait.material = _loading_previous_material
	_loading_portrait = null
	_loading_material = null
	_loading_previous_material = null


func _open_detail(card: Dictionary, portrait: TextureRect) -> void:
	var account_epoch := GameState.session_epoch
	if _busy:
		return
	var form_id := str(card.get("form_id", ""))
	if form_id.is_empty():
		return
	_set_card_loading(portrait, true)
	set_busy(true)
	var res := await Backend.atlas("atlas_detail", {"form_id": form_id})
	if not Backend.response_applies(res, account_epoch):
		return
	_selected = (
		GameState.as_dict(GameState.as_dict(res.data).get("entry"))
		if res.ok
		else {}
	)
	if _selected.is_empty():
		_clear_card_loading()
		set_busy(false)
		toast_requested.emit(tr("ATLAS_DETAIL_ERROR"), true)
		return
	_present_detail(_selected)
	var detail_texture: Texture2D = await _entry_texture(_selected)
	_clear_card_loading()
	set_busy(false)
	_detail_portrait.texture = detail_texture if detail_texture != null else portrait.texture
	await _detail_sheet.open()
	_start_detail_idle()


func _present_detail(entry: Dictionary) -> void:
	_detail_name.text = str(entry.get("display_name", tr("ANIMA_FALLBACK_NAME")))
	_detail_meta.text = tr("ATLAS_DETAIL_IDENTITY") % [
		_stage_name(int(entry.get("stage", 1))),
		LocaleManager.element_compact(entry),
	]
	var subject_key := "ATLAS_SUBJECT_%s" % str(
		entry.get("subject_kind", "object")
	).to_upper()
	_set_detail_value("form", _stage_name(int(entry.get("stage", 1))))
	_set_detail_value("kind", tr(subject_key))
	_set_detail_value(
		"rarity", LocaleManager.format_ratio(int(entry.get("rarity", 1)), 5)
	)
	_set_detail_value(
		"height",
		tr("ATLAS_DETAIL_HEIGHT_VALUE") % LocaleManager.format_integer(
			int(entry.get("body_height_cm", 0))
		)
	)
	var stats := GameState.as_dict(entry.get("base_stats"))
	for key: String in ["hp", "atk", "def", "spd", "special"]:
		_set_detail_value(key, LocaleManager.format_integer(int(stats.get(key, 0))))
	_set_detail_value("strike", LocaleManager.move_name(entry, "strike"))
	_set_detail_value("surge", LocaleManager.move_name(entry, "surge"))
	var owner_value: Variant = entry.get("owner_name")
	var owner_name := (
		(owner_value as String).strip_edges()
		if typeof(owner_value) == TYPE_STRING
		else ""
	)
	_detail_owner_cell.visible = not owner_name.is_empty()
	_detail_discovery_grid.columns = 2 if not owner_name.is_empty() else 1
	_set_detail_value("owner", owner_name)
	_set_detail_value(
		"encounters", LocaleManager.format_integer(int(entry.get("encounter_count", 1)))
	)
	_detail_report.visible = bool(entry.get("can_report", false))


func _set_detail_value(key: String, value: String) -> void:
	var label := _detail_values.get(key) as Label
	if label != null:
		label.text = value


func _stage_name(stage: int) -> String:
	match clampi(stage, 1, 3):
		2:
			return tr("FORM_ADULT")
		3:
			return tr("FORM_EVOLVED")
		_:
			return tr("FORM_HATCHLING")


func _start_detail_idle() -> void:
	_stop_detail_idle()
	if (
		not is_instance_valid(_detail_portrait)
		or _detail_portrait.texture == null
		or not _detail_sheet.is_visible_in_tree()
	):
		return
	_detail_portrait.pivot_offset = Vector2(
		_detail_portrait.size.x * 0.5, _detail_portrait.size.y
	)
	_detail_idle = create_tween().set_loops()
	_detail_idle.tween_property(
		_detail_portrait,
		"scale",
		Vector2(1.0 - DETAIL_IDLE_AMOUNT * 0.5, 1.0 + DETAIL_IDLE_AMOUNT),
		DETAIL_IDLE_SEC * 0.5
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_detail_idle.tween_property(
		_detail_portrait, "scale", Vector2.ONE, DETAIL_IDLE_SEC * 0.5
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _stop_detail_idle() -> void:
	if _detail_idle != null and _detail_idle.is_valid():
		_detail_idle.kill()
	_detail_idle = null
	if is_instance_valid(_detail_portrait):
		_detail_portrait.scale = Vector2.ONE


func _on_detail_closed() -> void:
	_stop_detail_idle()
	_selected = {}


func _open_report_sheet() -> void:
	if _selected.is_empty() or _busy or not bool(_selected.get("can_report", false)):
		return
	var entry_id := str(_selected.get("entry_id", ""))
	if entry_id.is_empty():
		return
	# `_detail_sheet.close()` fires `dismissed` -> `_on_detail_closed()`, which
	# clears `_selected` — the entry id is captured first so the category
	# sheet still knows what it's reporting.
	_report_entry_id = entry_id
	_detail_sheet.close()
	_report_sheet.open()


func _on_report_sheet_closed() -> void:
	_report_entry_id = ""


func _submit_report(category: String) -> void:
	var account_epoch := GameState.session_epoch
	var entry_id := _report_entry_id
	if entry_id.is_empty() or _busy:
		return
	_report_sheet.close()
	set_busy(true)
	var res := await Backend.atlas("report", {"entry_id": entry_id, "category": category})
	if not Backend.response_applies(res, account_epoch):
		return
	set_busy(false)
	if res.ok:
		toast_requested.emit(tr("ATLAS_REPORTED"), false)
		_all_cache_loaded = false
		await _load_first_page()
	else:
		var key := "ERROR_" + str(res.error)
		toast_requested.emit(tr(key) if tr(key) != key else tr("ATLAS_ERROR"), true)


func _entry_texture(entry: Dictionary) -> Texture2D:
	var account_epoch := GameState.session_epoch
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
	if not Backend.response_applies(res, account_epoch):
		return null
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
