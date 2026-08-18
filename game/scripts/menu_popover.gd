class_name MenuPopover
extends Control

signal profile_requested
signal atlas_requested
signal settings_requested

@onready var _panel: PanelContainer = %MenuPanel
@onready var _profile: Button = %MenuProfile
@onready var _atlas: Button = %MenuAtlas
@onready var _settings: Button = %MenuSettings


func _ready() -> void:
	%MenuBackdrop.pressed.connect(close)
	_profile.pressed.connect(_choose_profile)
	_atlas.pressed.connect(_choose_atlas)
	_settings.pressed.connect(_choose_settings)
	refresh_localized_ui()


func show_menu() -> void:
	visible = true
	position = Vector2.ZERO
	size = get_viewport_rect().size
	UiJuice.pop(_panel, 1.025)
	_profile.grab_focus()


func close() -> void:
	visible = false


func refresh_localized_ui() -> void:
	_profile.text = tr("MENU_SEEKER_PROFILE")
	_atlas.text = tr("MENU_ANIMA_ATLAS")
	_settings.text = tr("MENU_SETTINGS")


func _choose_profile() -> void:
	close()
	profile_requested.emit()


func _choose_atlas() -> void:
	close()
	atlas_requested.emit()


func _choose_settings() -> void:
	close()
	settings_requested.emit()
