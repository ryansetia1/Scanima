class_name ShopSheet
extends UiBottomSheet

signal buy_requested(item: Dictionary)
signal use_requested(item: Dictionary)
signal shop_cta_requested

enum Mode { SHOP, BAG, BATTLE }

const CATALOG_VIEWPORT_HEIGHT := 560.0

@onready var _title: Label = %ShopTitle
@onready var _tabs: HBoxContainer = %ShopTabs
@onready var _food_tab: Button = %ShopFoodTab
@onready var _item_tab: Button = %ShopItemTab
@onready var _catalog_scroll: ScrollContainer = %ShopScroll
@onready var _list: VBoxContainer = %ShopList
@onready var _empty: Label = %ShopEmpty
@onready var _cta: Button = %ShopEmptyCta

var _mode := Mode.SHOP
var _tab := "food"
var _catalog: Array = []
var _inventory: Array = []
var _bits := 0
var _busy := false
var _pending_item_id := ""
var _retry_item_id := ""


func _ready() -> void:
	super._ready()
	_food_tab.pressed.connect(_show_tab.bind("food"))
	_item_tab.pressed.connect(_show_tab.bind("item"))
	_cta.pressed.connect(func() -> void: shop_cta_requested.emit())


func set_catalog(catalog: Array, inventory: Array, bits: int) -> void:
	_catalog = catalog.duplicate(true)
	_inventory = inventory.duplicate(true)
	_bits = maxi(0, bits)
	_rebuild()


func set_busy(busy: bool) -> void:
	_busy = busy
	_rebuild()


## Item sedang dibeli: baris itu berlabel "Buying...", dan seluruh tombol Buy
## lain mati sampai round trip selesai -- satu pembelian in-flight per waktu,
## dan sekarang terlihat, bukan cuma diam-diam ditolak.
func set_pending(item_id: String) -> void:
	_pending_item_id = item_id
	if not item_id.is_empty():
		_retry_item_id = ""
	_rebuild()


## Respons pembelian hilang sebelum bisa dikonfirmasi. Hanya item yang membawa
## idempotency key lama yang boleh ditekan; item lain menunggu sampai intent itu
## selesai supaya satu pembelian tidak menimpa pembelian lain.
func set_retry(item_id: String) -> void:
	_pending_item_id = ""
	_retry_item_id = item_id
	if not item_id.is_empty():
		for item in _catalog:
			if str(item.get("id", "")) == item_id:
				_tab = "food" if Catalog.is_food(item) else "item"
				break
	_rebuild()


## Rect global dan tekstur ikon baris SHOP untuk item_id, dipanggil sebelum
## `_rebuild()` mana pun menghapus baris itu -- animasi terbang butuh titik
## berangkat sebelum optimistic purchase mengecat ulang daftarnya.
func icon_snapshot_for(item_id: String) -> Dictionary:
	for row in _list.get_children():
		if str(row.get_meta("item_id", "")) != item_id:
			continue
		# By type, not `get_child(0)`: `_make_row()` happens to add the icon
		# first today, but a badge/overlay added ahead of it later would
		# silently point this at the wrong node without ever erroring.
		for child in row.get_children():
			if child is TextureRect:
				return {"rect": child.get_global_rect(), "texture": child.texture}
		return {}
	return {}


func open_shop(tab: String = "food") -> void:
	_mode = Mode.SHOP
	if _retry_item_id.is_empty():
		_tab = tab if tab == "item" else "food"
	_rebuild()
	_reveal()


func open_bag(tab: String = "food") -> void:
	_mode = Mode.BAG
	_tab = tab if tab == "item" else "food"
	_rebuild()
	_reveal()


func open_battle() -> void:
	_mode = Mode.BATTLE
	_tab = "item"
	_rebuild()
	_reveal()


func is_shop_open() -> bool:
	return visible and _mode == Mode.SHOP


func is_bag_open() -> bool:
	return visible and _mode == Mode.BAG


func prefers_item_tab() -> bool:
	return _mode == Mode.BATTLE or _tab == "item"


func fit_to_content() -> void:
	_fit_catalog_viewport()
	super.fit_to_content()


func _reveal() -> void:
	if visible:
		fit_to_content()
		return
	open()


func _show_tab(tab: String) -> void:
	_tab = tab
	_rebuild()
	fit_to_content()


func _rebuild() -> void:
	_title.text = tr(_title_key())
	_tabs.visible = _mode == Mode.SHOP or _mode == Mode.BAG
	var purchase_locked := (
		_mode == Mode.SHOP
		and (not _pending_item_id.is_empty() or not _retry_item_id.is_empty())
	)
	_food_tab.disabled = _busy or purchase_locked
	_item_tab.disabled = _busy or purchase_locked
	_food_tab.theme_type_variation = &"PrimaryButton" if _tab == "food" else &""
	_item_tab.theme_type_variation = &"PrimaryButton" if _tab == "item" else &""
	_food_tab.self_modulate = Color.WHITE
	_item_tab.self_modulate = Color.WHITE
	for child in _list.get_children():
		child.queue_free()
	var rows := _visible_rows()
	_catalog_scroll.visible = not rows.is_empty()
	_empty.visible = rows.is_empty()
	_cta.visible = rows.is_empty() and _mode == Mode.BAG
	_empty.text = tr(_empty_key())
	_cta.text = tr("SHOP_OPEN")
	for item in rows:
		_list.add_child(_make_row(item))
	call_deferred("fit_to_content")


func _fit_catalog_viewport() -> void:
	if not is_instance_valid(_catalog_scroll):
		return
	if not _catalog_scroll.visible:
		_catalog_scroll.custom_minimum_size.y = 0.0
		return
	# Reset before measuring — sama seperti _fit_scroll_to_host di UiBottomSheet.
	# Kalau tidak di-reset, chrome_h berikutnya sudah mengandung minimum lama
	# sehingga tumbuh terus setiap kali fit dipanggil (bug "terbang ke atas").
	_catalog_scroll.custom_minimum_size.y = 0.0
	# Gunakan sheet_host_size() dikurangi bottom_inset agar konsisten dengan
	# fit_to_content() — raw host_h tanpa inset membuat scroll lebih tinggi
	# dari area yang tersedia setelah BottomNav diperhitungkan.
	var raw_host_h := UiJuice.sheet_host_size(self, panel()).y
	if raw_host_h < 1.0:
		_catalog_scroll.custom_minimum_size.y = CATALOG_VIEWPORT_HEIGHT
		return
	var host_h := maxf(1.0, raw_host_h - bottom_inset)
	var chrome_h := panel().get_combined_minimum_size().y
	_catalog_scroll.custom_minimum_size.y = minf(
		CATALOG_VIEWPORT_HEIGHT,
		maxf(0.0, host_h * max_height_ratio - chrome_h)
	)


func _visible_rows() -> Array[Dictionary]:
	if _mode == Mode.BATTLE:
		return Catalog.owned_rows(_catalog, _inventory, "battle")
	var wanted := "food" if _tab == "food" else "item"
	var owned_only := _mode == Mode.BAG
	var rows: Array[Dictionary] = []
	for value in _catalog:
		var item: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
		if str(item.get("kind", "")) != wanted:
			continue
		var qty := Catalog.quantity_of(_inventory, str(item.get("id", "")))
		if owned_only and qty <= 0:
			continue
		var copy := item.duplicate(true)
		copy["quantity"] = qty
		rows.append(copy)
	return rows


func _make_row(item: Dictionary) -> Control:
	var item_id := str(item.get("id", ""))
	var row := HBoxContainer.new()
	row.set_meta("item_id", item_id)
	row.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = CatalogAtlas.icon_for(item)
	row.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	var name_label := Label.new()
	name_label.theme_type_variation = "SectionLabel"
	name_label.text = tr(str(item.get("name_key", "CATALOG_ITEM")))
	var effect := Label.new()
	effect.theme_type_variation = "MutedLabel"
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.text = _effect_text(item)
	copy.add_child(name_label)
	copy.add_child(effect)
	row.add_child(copy)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	if _mode == Mode.SHOP:
		var buy := Button.new()
		var price := int(item.get("price", 0))
		var is_pending := not _pending_item_id.is_empty() and item_id == _pending_item_id
		var is_retry := not _retry_item_id.is_empty() and item_id == _retry_item_id
		buy.custom_minimum_size = Vector2(148, 96)
		buy.theme_type_variation = "PrimaryButton"
		buy.disabled = (
			_busy
			or not _pending_item_id.is_empty()
			or (not _retry_item_id.is_empty() and not is_retry)
			or (not is_retry and _bits < price)
		)
		buy.text = (
			tr("SHOP_BUYING") if is_pending
			else tr("ACTION_RETRY") if is_retry
			else tr("SHOP_BUY") % LocaleManager.format_integer(price)
		)
		buy.pressed.connect(func() -> void: buy_requested.emit(item))
		actions.add_child(buy)
	elif _can_use(item):
		var use := Button.new()
		use.custom_minimum_size = Vector2(148, 96)
		use.disabled = _busy
		use.text = tr("CARE_FEED") if Catalog.is_food(item) else tr("SHOP_USE")
		use.pressed.connect(func() -> void: use_requested.emit(item))
		actions.add_child(use)
	if actions.get_child_count() > 0:
		row.add_child(actions)
	return row


func _can_use(item: Dictionary) -> bool:
	if _mode == Mode.BATTLE:
		return true
	return Catalog.is_food(item) or Catalog.is_energy(item)


func _title_key() -> String:
	match _mode:
		Mode.BAG:
			return "BAG_TITLE"
		Mode.BATTLE:
			return "SHOP_BATTLE_TITLE"
		_:
			return "SHOP_TITLE"


func _empty_key() -> String:
	match _mode:
		Mode.BAG:
			return "SHOP_FEED_EMPTY" if _tab == "food" else "BAG_ITEMS_EMPTY"
		Mode.BATTLE:
			return "SHOP_BATTLE_EMPTY"
		_:
			return "SHOP_EMPTY"


func _effect_text(item: Dictionary) -> String:
	var qty := int(item.get("quantity", 0))
	var owned := tr("SHOP_OWNED") % LocaleManager.format_integer(qty)
	var effect := str(item.get("effect", ""))
	var value := int(item.get("effect_value", 0))
	var detail := ""
	match effect:
		"hunger":
			detail = tr("SHOP_EFFECT_HUNGER") % LocaleManager.format_integer(value)
		"energy":
			detail = tr("SHOP_EFFECT_ENERGY") % LocaleManager.format_integer(value)
		"heal_hp_pct":
			detail = tr("SHOP_EFFECT_HEAL") % LocaleManager.format_integer(value)
		"buff_atk":
			detail = tr("SHOP_EFFECT_ATK") % LocaleManager.format_integer(value)
		"buff_special":
			detail = tr("SHOP_EFFECT_SPECIAL") % LocaleManager.format_integer(value)
		"buff_guard":
			detail = tr("SHOP_EFFECT_GUARD") % LocaleManager.format_integer(value)
		"buff_spd":
			detail = tr("SHOP_EFFECT_SPD") % LocaleManager.format_integer(value)
		"pp_boost":
			detail = tr("SHOP_EFFECT_PP") % LocaleManager.format_integer(value)
		"phase_shield":
			detail = tr("SHOP_EFFECT_SHIELD") % LocaleManager.format_integer(value)
		_:
			detail = tr("SHOP_EFFECT_GENERIC")
	return "%s · %s" % [detail, owned]
