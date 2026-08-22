class_name SeekerProfileView
extends Control

signal back_requested
signal help_requested(title: String, body: String)
signal rename_requested

const INFO_ROW := preload("res://scenes/ui/info_value_row.tscn")
const TROPHY_CARD_PX := 176.0

@onready var _name: Label = %SeekerProfileName
@onready var _portrait: TextureRect = %SeekerPortrait
@onready var _rows: VBoxContainer = %SeekerRows
@onready var _trophy_section: VBoxContainer = %TrophySection
@onready var _trophy_empty: Label = %TrophyEmpty
@onready var _trophy_grid: GridContainer = %TrophyGrid

## trophy_id -> TextureRect kartunya, supaya art yang menyusul dari disk atau
## jaringan bisa dipasang tanpa membangun ulang grid.
var _trophy_art: Dictionary = {}
var _trophy_ids := PackedStringArray()
var _trophy_skeleton: UiSkeleton


func _ready() -> void:
	%SeekerProfileBack.pressed.connect(func() -> void: back_requested.emit())
	%RenameSeeker.pressed.connect(func() -> void: rename_requested.emit())
	_trophy_skeleton = _build_trophy_skeleton()


func set_profile(profile: Dictionary, portrait: Texture2D) -> void:
	var seeker_name: Variant = profile.get("seeker_name")
	_name.text = (
		seeker_name
		if typeof(seeker_name) == TYPE_STRING and not str(seeker_name).is_empty()
		else tr("SEEKER_UNNAMED")
	)
	_portrait.texture = portrait
	for child in _rows.get_children():
		child.queue_free()
	var xp := maxi(0, int(profile.get("seeker_xp", 0)))
	_add_row("SEEKER_LEVEL", LocaleManager.format_integer(level_from_xp(xp)), "SEEKER_LEVEL_HELP")
	_add_row("SEEKER_EXP", LocaleManager.format_integer(xp), "SEEKER_EXP_HELP")
	_add_row("SEEKER_ANIMA_COUNT", LocaleManager.format_integer(int(profile.get("anima_count", 0))))
	_add_row("SEEKER_SPECIES_COUNT", LocaleManager.format_integer(int(profile.get("species_count", 0))))
	_add_row("SEEKER_VICTORIES", LocaleManager.format_integer(int(profile.get("battle_victories", 0))))
	_add_row("SEEKER_JOINED", _joined_date(str(profile.get("created_at", ""))))


## Setiap Core yang dimiliki tampil sebagai kartu art bernama. Dipanggil dua kali
## per kunjungan — sekali dari cache, sekali dari server — jadi grid hanya
## dibangun ulang kalau daftarnya memang berubah, supaya art yang sudah terpasang
## tidak berkedip.
func set_trophies(rows: Array) -> void:
	_trophy_skeleton.set_loading(false)
	_trophy_section.visible = true
	var trophies := trophy_entries(rows)
	var ids := PackedStringArray()
	for trophy in trophies:
		ids.append(str(trophy.get("id", "")))
	_trophy_empty.visible = ids.is_empty()
	_trophy_grid.visible = not ids.is_empty()
	if ids == _trophy_ids:
		return
	_trophy_ids = ids
	_trophy_art.clear()
	for child in _trophy_grid.get_children():
		# queue_free() sendirian meninggalkan kartu lama di dalam grid sampai akhir
		# frame, jadi jumlah anaknya sempat salah tepat saat kartu baru dipasang.
		_trophy_grid.remove_child(child)
		child.queue_free()
	for trophy in trophies:
		_trophy_grid.add_child(_build_trophy_card(
			str(trophy.get("id", "")),
			str(trophy.get("display_name", tr("EXPEDITION_TROPHY_UNKNOWN")))
		))


func set_trophy_art(trophy_id: String, texture: Texture2D) -> void:
	var card := _trophy_art.get(trophy_id) as TextureRect
	if texture != null and is_instance_valid(card):
		card.texture = texture


func set_trophies_loading(loading: bool) -> void:
	if loading:
		_trophy_section.visible = true
		_trophy_empty.visible = false
		_trophy_grid.visible = false
	_trophy_skeleton.set_loading(loading)


func hide_trophies() -> void:
	_trophy_skeleton.set_loading(false)
	_trophy_section.visible = false


## Baris `trophies` membungkus row embed PostgREST; pemanggil di luar view juga
## membutuhkan bentuk datarnya untuk mengunduh art.
static func trophy_entries(rows: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in rows:
		var trophy := GameState.as_dict(GameState.as_dict(value).get("expedition_trophies"))
		if not str(trophy.get("id", "")).is_empty():
			result.append(trophy)
	return result


func set_busy(busy: bool) -> void:
	%SeekerProfileBack.disabled = busy
	%RenameSeeker.disabled = busy


static func level_from_xp(xp: int) -> int:
	return 1 + int(floor(sqrt(float(maxi(0, xp)) / 5.0)))


func _add_row(label_key: String, value: String, help_key: String = "") -> void:
	var row := INFO_ROW.instantiate() as InfoValueRow
	_rows.add_child(row)
	var help_body := tr(help_key) if not help_key.is_empty() else ""
	row.configure(tr(label_key), tr(label_key), help_body)
	row.set_value_text(value)
	row.help_requested.connect(func(title: String, body: String) -> void:
		help_requested.emit(title, body)
	)


func _joined_date(value: String) -> String:
	var date := Time.get_datetime_dict_from_datetime_string(value, false)
	if date.is_empty():
		return tr("SEEKER_UNKNOWN")
	return "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]


## Tiga slot mengikuti grid 3 kolom dan tinggi kartu 176 px, jadi section-nya
## sudah kelihatan dan layout tidak meloncat ketika Core-nya tiba.
func _build_trophy_skeleton() -> UiSkeleton:
	var skeleton := UiSkeleton.new()
	skeleton.name = "TrophySkeleton"
	skeleton.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for _index in 3:
		var slot := ColorRect.new()
		slot.custom_minimum_size = Vector2(TROPHY_CARD_PX, TROPHY_CARD_PX)
		slot.color = Color(0.18, 0.5, 0.7, 0.72)
		slot.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(slot)
	skeleton.add_child(row)
	_trophy_section.add_child(skeleton)
	_trophy_section.move_child(skeleton, 1)
	return skeleton


## Slot art memakai ukuran tetap sejak kartu dibuat, jadi grid tidak melompat
## ketika PNG-nya menyusul beberapa ratus milidetik kemudian.
func _build_trophy_card(trophy_id: String, display_name: String) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(TROPHY_CARD_PX, TROPHY_CARD_PX)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.add_child(art)
	var label := Label.new()
	label.text = display_name
	label.custom_minimum_size = Vector2(TROPHY_CARD_PX, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(label)
	_trophy_art[trophy_id] = art
	return card
