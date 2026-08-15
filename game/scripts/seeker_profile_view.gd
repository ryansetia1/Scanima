class_name SeekerProfileView
extends Control

signal back_requested
signal help_requested(title: String, body: String)
signal rename_requested
signal trophies_save_requested(trophy_ids: Array[String])

const INFO_ROW := preload("res://scenes/ui/info_value_row.tscn")

@onready var _name: Label = %SeekerProfileName
@onready var _portrait: TextureRect = %SeekerPortrait
@onready var _rows: VBoxContainer = %SeekerRows
@onready var _trophy_section: VBoxContainer = %TrophySection
@onready var _featured_trophies: HBoxContainer = %FeaturedTrophies
@onready var _trophy_empty: Label = %TrophyEmpty
@onready var _trophy_list: ItemList = %TrophyList
@onready var _save_trophies: Button = %SaveTrophies


func _ready() -> void:
	%SeekerProfileBack.pressed.connect(func() -> void: back_requested.emit())
	%RenameSeeker.pressed.connect(func() -> void: rename_requested.emit())
	_trophy_list.multi_selected.connect(_on_trophy_selected)
	_save_trophies.pressed.connect(func() -> void:
		trophies_save_requested.emit(_selected_trophy_ids())
	)


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


func set_trophies(data: Dictionary, featured_textures: Dictionary = {}) -> void:
	_trophy_section.visible = true
	_trophy_list.clear()
	for child in _featured_trophies.get_children():
		child.queue_free()
	var featured_ids: Array[String] = []
	for value in _as_array(data.get("featured")):
		var row := GameState.as_dict(value)
		var trophy := GameState.as_dict(row.get("expedition_trophies"))
		var trophy_id := str(trophy.get("id", ""))
		if trophy_id.is_empty():
			continue
		featured_ids.append(trophy_id)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(120, 120)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = str(trophy.get("display_name", tr("EXPEDITION_TROPHY_UNKNOWN")))
		icon.texture = featured_textures.get(trophy_id) as Texture2D
		_featured_trophies.add_child(icon)
	for value in _as_array(data.get("trophies")):
		var row := GameState.as_dict(value)
		var trophy := GameState.as_dict(row.get("expedition_trophies"))
		var trophy_id := str(trophy.get("id", ""))
		if trophy_id.is_empty():
			continue
		_trophy_list.add_item(str(
			trophy.get("display_name", tr("EXPEDITION_TROPHY_UNKNOWN"))
		))
		var index := _trophy_list.item_count - 1
		_trophy_list.set_item_metadata(index, trophy_id)
		if trophy_id in featured_ids:
			_trophy_list.select(index, false)
	var empty := _trophy_list.item_count == 0
	_trophy_empty.visible = empty
	_trophy_list.visible = not empty
	_save_trophies.visible = not empty
	_save_trophies.disabled = false


func hide_trophies() -> void:
	_trophy_section.visible = false


func set_busy(busy: bool) -> void:
	%SeekerProfileBack.disabled = busy
	%RenameSeeker.disabled = busy
	_save_trophies.disabled = busy


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


func _on_trophy_selected(index: int, selected: bool) -> void:
	if selected and _trophy_list.get_selected_items().size() > 3:
		_trophy_list.deselect(index)


func _selected_trophy_ids() -> Array[String]:
	var result: Array[String] = []
	for index in _trophy_list.get_selected_items():
		var trophy_id := str(_trophy_list.get_item_metadata(index))
		if not trophy_id.is_empty():
			result.append(trophy_id)
	return result


static func _as_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
