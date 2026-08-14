class_name SeekerMenuSheet
extends UiBottomSheet

signal profile_requested
signal gallery_requested
signal account_requested
signal help_requested
signal delete_account_requested
signal reduced_motion_changed(enabled: bool)

@onready var _title: Label = %SeekerMenuTitle
@onready var _account: Button = %SeekerAccount
@onready var _reduced_motion: CheckButton = %ReducedMotion
@onready var _delete: Button = %DeleteAccount

var _configuring := false


func _ready() -> void:
	super._ready()
	%SeekerProfile.pressed.connect(func() -> void: profile_requested.emit())
	%SeekerGallery.pressed.connect(func() -> void: gallery_requested.emit())
	_account.pressed.connect(func() -> void: account_requested.emit())
	%SeekerHelp.pressed.connect(func() -> void: help_requested.emit())
	_delete.pressed.connect(func() -> void: delete_account_requested.emit())
	_reduced_motion.toggled.connect(_on_reduced_motion_toggled)


func show_menu(profile: Dictionary, anonymous: bool, reduced_motion: bool) -> void:
	var raw_name: Variant = profile.get("seeker_name")
	var seeker_name := str(raw_name).strip_edges() if typeof(raw_name) == TYPE_STRING else ""
	_title.text = seeker_name if not seeker_name.is_empty() else tr("SEEKER_MENU_TITLE")
	_account.text = tr("SEEKER_SIGN_IN_GOOGLE") if anonymous else tr("SEEKER_ACCOUNT_LINKED")
	_delete.visible = true
	_configuring = true
	_reduced_motion.button_pressed = reduced_motion
	_configuring = false
	open()


func _on_reduced_motion_toggled(enabled: bool) -> void:
	if not _configuring:
		reduced_motion_changed.emit(enabled)
