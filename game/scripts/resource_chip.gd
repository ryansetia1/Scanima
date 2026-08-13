class_name ResourceChip
extends PanelContainer

signal pressed

@onready var _value_label: Label = %Value
@onready var _name_label: Label = %Name
@onready var _action_button: Button = %ActionButton


func _ready() -> void:
	_action_button.pressed.connect(pressed.emit)
	UiJuice.install_button(_action_button)


func set_value_text(value_text: String) -> void:
	_value_label.text = value_text


func set_name_text(name_text: String) -> void:
	_name_label.text = name_text


func set_interactive(interactive: bool, tooltip: String = "") -> void:
	_action_button.visible = interactive
	_action_button.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	_action_button.tooltip_text = tooltip


func value_label() -> Label:
	return _value_label


func grab_action_focus() -> void:
	if _action_button.visible:
		_action_button.grab_focus()
