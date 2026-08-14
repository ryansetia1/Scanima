class_name ResourceChip
extends PanelContainer

signal pressed

const TEXT_SEPARATION := -4
const ICON_SEPARATION := 8

@onready var _column: VBoxContainer = $Column
@onready var _icon: TextureRect = %Icon
@onready var _value_label: Label = %Value
@onready var _name_label: Label = %Name
@onready var _action_button: Button = %ActionButton


func _ready() -> void:
	_action_button.pressed.connect(pressed.emit)
	UiJuice.install_button(_action_button)


func set_icon(texture: Texture2D) -> void:
	_icon.texture = texture
	_icon.visible = texture != null
	_column.add_theme_constant_override(
		"separation",
		ICON_SEPARATION if texture != null else TEXT_SEPARATION
	)


func set_value_text(value_text: String) -> void:
	_value_label.text = value_text


func set_name_text(name_text: String) -> void:
	_name_label.text = name_text
	_name_label.visible = not name_text.is_empty()


func set_interactive(interactive: bool, tooltip: String = "") -> void:
	_action_button.visible = interactive
	_action_button.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	_action_button.tooltip_text = tooltip


func value_label() -> Label:
	return _value_label


func grab_action_focus() -> void:
	if _action_button.visible:
		_action_button.grab_focus()
