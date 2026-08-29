class_name SeekerMenuSheet
extends UiBottomSheet

signal account_requested
signal help_requested
signal delete_account_requested
signal music_changed(enabled: bool)
signal chapter_push_changed(enabled: bool)

@onready var _title: Label = %SeekerMenuTitle
@onready var _account: Button = %SeekerAccount
@onready var _music: CheckButton = %MusicEnabled
@onready var _chapter_push: CheckButton = %ChapterPush
@onready var _delete: Button = %DeleteAccount

var _configuring := false


func _ready() -> void:
	super._ready()
	_account.pressed.connect(func() -> void: account_requested.emit())
	%SeekerHelp.pressed.connect(func() -> void: help_requested.emit())
	_delete.pressed.connect(func() -> void: delete_account_requested.emit())
	_music.toggled.connect(_on_music_toggled)
	_chapter_push.toggled.connect(_on_chapter_push_toggled)


func show_menu(
	anonymous: bool,
	push_available: bool = false,
	push_enabled: bool = false,
	music_enabled: bool = true
) -> void:
	_title.text = tr("SETTINGS_TITLE")
	_account.text = tr("SEEKER_SIGN_IN_GOOGLE") if anonymous else tr("SEEKER_SIGN_OUT")
	_delete.visible = not anonymous
	_configuring = true
	_music.button_pressed = music_enabled
	_chapter_push.visible = push_available
	_chapter_push.button_pressed = push_available and push_enabled
	_configuring = false
	open()


func _on_music_toggled(enabled: bool) -> void:
	if not _configuring:
		music_changed.emit(enabled)


func _on_chapter_push_toggled(enabled: bool) -> void:
	if not _configuring:
		chapter_push_changed.emit(enabled)
