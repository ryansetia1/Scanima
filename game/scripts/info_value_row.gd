class_name InfoValueRow
extends HBoxContainer

signal help_requested(title: String, body: String)

@onready var _label: Label = %RowLabel
@onready var _help_button: Button = %HelpButton
@onready var _value: Label = %RowValue

var _help_title := ""
var _help_body := ""


func _ready() -> void:
	_help_button.pressed.connect(_show_help)
	UiJuice.install_button(_help_button)


func configure(label_text: String, help_title: String, help_body: String) -> void:
	_label.text = label_text
	_help_title = help_title
	_help_body = help_body
	_help_button.tooltip_text = help_title
	_help_button.visible = not help_body.is_empty()


func set_value_text(value_text: String) -> void:
	_value.text = value_text


func value_label() -> Label:
	return _value


func _show_help() -> void:
	if not _help_body.is_empty():
		help_requested.emit(_help_title, _help_body)
