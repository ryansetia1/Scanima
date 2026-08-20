class_name BottomNav
extends PanelContainer

signal destination_selected(destination: StringName)

const HOME := &"home"
const SCAN := &"scan"
const BATTLE := &"battle"
const COLLECTION := &"collection"
const MENU := &"menu"

const INK_ACTIVE := Color(0.161, 0.714, 0.965)
const INK_IDLE := Color(0.561, 0.612, 0.682)
const INK_UNAVAILABLE := Color(0.561, 0.612, 0.682, 0.4)

## The tab icons are full-colour art, so their state cannot ride on hue the way
## the labels' does — painting cyan over the gold and cream would throw the
## drawing away. They carry state as brightness instead, and the label ink plus
## the selected pill keep saying it in a second and third way.
const ICON_ACTIVE := Color(1.0, 1.0, 1.0)
const ICON_IDLE := Color(1.0, 1.0, 1.0, 0.55)
const ICON_UNAVAILABLE := Color(1.0, 1.0, 1.0, 0.22)

@onready var _buttons: Dictionary = {
	HOME: %HomeNavButton,
	SCAN: %ScanNavButton,
	BATTLE: %BattleNavButton,
	COLLECTION: %CollectionNavButton,
	MENU: %MenuNavButton,
}

var _active: StringName = HOME
var _scan_available := true


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
		_paint(key)


func set_scan_emphasized(emphasized: bool) -> void:
	# The flag is stored even when the tabs are not built yet, so the paint that
	# _ready() runs already reflects it.
	_scan_available = emphasized
	_paint(SCAN)


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


func _paint(key: StringName) -> void:
	var button := _buttons.get(key) as Button
	if button == null:
		return
	var content := button.get_node_or_null(^"Content")
	if content == null:
		return
	var active := key == _active
	var ink := INK_ACTIVE if active else INK_IDLE
	var icon_ink := ICON_ACTIVE if active else ICON_IDLE
	if key == SCAN and not _scan_available:
		ink = INK_UNAVAILABLE
		icon_ink = ICON_UNAVAILABLE
	var icon := content.get_node_or_null(^"Icon") as TextureRect
	if icon != null:
		icon.modulate = icon_ink
	var label := content.get_node_or_null(^"Label") as Label
	if label == null:
		return
	label.add_theme_color_override(&"font_color", ink)
	# ponytail: the design weights the active label heavier (ExtraBold vs
	# SemiBold); a same-colour outline thickens the glyphs without shipping a
	# second FontVariation. Upgrade to a real weight axis if 18px looks muddy.
	label.add_theme_color_override(&"font_outline_color", ink)
	label.add_theme_constant_override(&"outline_size", 2 if active else 0)
