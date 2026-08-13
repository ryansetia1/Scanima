class_name UiBottomSheet
extends Control

signal opened
signal dismissed

@export var panel_path: NodePath = ^"Bottom/Panel"
@export var dismiss_button_path: NodePath = ^"DismissButton"

@onready var _panel: Control = get_node(panel_path) as Control
@onready var _dismiss_button: Button = get_node(dismiss_button_path) as Button


func _ready() -> void:
	_dismiss_button.pressed.connect(close)
	UiJuice.install_button(_dismiss_button)


func open() -> void:
	UiJuice.show_bottom_sheet(self, _panel)
	opened.emit()


func close() -> void:
	if not visible:
		return
	UiJuice.hide_bottom_sheet(self, _panel)
	dismissed.emit()


func panel() -> Control:
	return _panel
