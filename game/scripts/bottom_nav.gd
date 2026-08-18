class_name BottomNav
extends PanelContainer

signal destination_selected(destination: StringName)

const HOME := &"home"
const SCAN := &"scan"
const BATTLE := &"battle"
const COLLECTION := &"collection"
const MENU := &"menu"

@onready var _buttons: Dictionary = {
	HOME: %HomeNavButton,
	SCAN: %ScanNavButton,
	BATTLE: %BattleNavButton,
	COLLECTION: %CollectionNavButton,
	MENU: %MenuNavButton,
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


func set_scan_emphasized(emphasized: bool) -> void:
	var button := (
		_buttons.get(SCAN) as Button
		if not _buttons.is_empty()
		else find_child("ScanNavButton", true, false) as Button
	)
	if button == null:
		return
	button.theme_type_variation = &"ScanTabButton" if emphasized else &"NavTabButton"


func set_battle_badge(visible: bool) -> void:
	%BattleNewBadge.visible = visible


func set_busy(busy: bool, _details_available: bool = true) -> void:
	# Requests continue in the persistent shell, so changing view stays safe.
	for destination: StringName in _buttons:
		(_buttons[destination] as Button).disabled = destination == MENU and busy


func _select(destination: StringName) -> void:
	if destination == MENU:
		set_active(_active)
		destination_selected.emit(destination)
		return
	if destination == _active:
		set_active(destination)
		return
	set_active(destination)
	destination_selected.emit(destination)
