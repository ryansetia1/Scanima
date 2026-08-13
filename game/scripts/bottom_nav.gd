class_name BottomNav
extends PanelContainer

signal destination_selected(destination: StringName)

const HOME := &"home"
const SCAN := &"scan"
const COLLECTION := &"collection"
const ANIMA := &"anima"

@onready var _buttons: Dictionary = {
	HOME: %HomeNavButton,
	SCAN: %ScanNavButton,
	COLLECTION: %CollectionNavButton,
	ANIMA: %AnimaNavButton,
}

var _active: StringName = HOME


func _ready() -> void:
	for destination: StringName in _buttons:
		var button := _buttons[destination] as Button
		button.pressed.connect(_select.bind(destination))
	set_active(HOME)


func set_active(destination: StringName) -> void:
	if not _buttons.has(destination):
		return
	_active = destination
	for key: StringName in _buttons:
		(_buttons[key] as Button).button_pressed = key == destination


func set_busy(_busy: bool, details_available: bool) -> void:
	# Requests continue in the persistent shell, so changing view stays safe.
	for destination: StringName in _buttons:
		(_buttons[destination] as Button).disabled = false
	(_buttons[ANIMA] as Button).disabled = not details_available


func _select(destination: StringName) -> void:
	if destination == _active:
		set_active(destination)
		return
	set_active(destination)
	destination_selected.emit(destination)
