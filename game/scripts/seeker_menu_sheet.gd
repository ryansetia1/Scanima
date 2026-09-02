class_name SeekerMenuSheet
extends UiBottomSheet

signal help_requested
signal music_changed(enabled: bool)
signal chapter_push_changed(enabled: bool)

@onready var _title: Label = %SeekerMenuTitle
@onready var _music: CheckButton = %MusicEnabled
@onready var _chapter_push: CheckButton = %ChapterPush

var _configuring := false


func _ready() -> void:
	super._ready()
	%SeekerHelp.pressed.connect(func() -> void: help_requested.emit())
	_music.toggled.connect(_on_music_toggled)
	_chapter_push.toggled.connect(_on_chapter_push_toggled)


## Sengaja tanpa aksi akun: Sign in with Google / Sign Out dan Delete Account
## hidup di Seeker Profile bersama identitasnya. Yang tersisa di sini murni
## preference perangkat.
func show_menu(
	push_available: bool = false,
	push_enabled: bool = false,
	music_enabled: bool = true
) -> void:
	_title.text = tr("SETTINGS_TITLE")
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
