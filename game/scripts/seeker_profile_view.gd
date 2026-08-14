class_name SeekerProfileView
extends Control

signal back_requested
signal help_requested(title: String, body: String)
signal rename_requested

const INFO_ROW := preload("res://scenes/ui/info_value_row.tscn")

@onready var _name: Label = %SeekerProfileName
@onready var _portrait: TextureRect = %SeekerPortrait
@onready var _rows: VBoxContainer = %SeekerRows


func _ready() -> void:
	%SeekerProfileBack.pressed.connect(func() -> void: back_requested.emit())
	%RenameSeeker.pressed.connect(func() -> void: rename_requested.emit())


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
