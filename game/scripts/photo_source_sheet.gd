class_name PhotoSourceSheet
extends UiBottomSheet

signal camera_requested
signal gallery_requested

@onready var _title: Label = %PhotoSourceTitle
@onready var _hint: Label = %PhotoSourceHint
@onready var _camera_button: Button = %PhotoSourceCamera
@onready var _gallery_button: Button = %PhotoSourceGallery


func _ready() -> void:
	super._ready()
	_camera_button.pressed.connect(_on_camera)
	_gallery_button.pressed.connect(_on_gallery)
	refresh_localized_ui()


func refresh_localized_ui() -> void:
	_title.text = tr("PHOTO_SOURCE_TITLE")
	_hint.text = tr("PHOTO_SOURCE_HINT")
	_camera_button.text = tr("PHOTO_SOURCE_CAMERA")
	_gallery_button.text = tr("PHOTO_SOURCE_GALLERY")


func open_chooser() -> void:
	refresh_localized_ui()
	open()


func _on_camera() -> void:
	close()
	camera_requested.emit()


func _on_gallery() -> void:
	close()
	gallery_requested.emit()
