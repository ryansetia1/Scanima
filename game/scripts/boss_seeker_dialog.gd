class_name BossSeekerDialog
extends Control

signal opened
signal dismissed

const PANEL_STYLE: StyleBox = preload("res://themes/toast/toast_panel_general.tres")

var _open := false
var _backdrop: ColorRect
var _panel: PanelContainer
var _portrait: TextureRect
var _speaker: Label
var _line: Label
var _continue: Button
var _external_continue := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 24
	_backdrop = ColorRect.new()
	_backdrop.name = "SeekerDim"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.012, 0.02, 0.05, 0.0)
	_backdrop.visible = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_panel = PanelContainer.new()
	_panel.name = "SeekerPanel"
	_panel.anchor_top = 0.4
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.4
	_panel.offset_left = 16.0
	_panel.offset_top = -156.0
	_panel.offset_right = -16.0
	_panel.offset_bottom = 156.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.theme_type_variation = "BattleEventPlate"
	_panel.add_theme_stylebox_override("panel", PANEL_STYLE)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)
	_portrait = TextureRect.new()
	_portrait.name = "SeekerPortrait"
	_portrait.custom_minimum_size = Vector2(160, 160)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 10)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(copy)
	_speaker = Label.new()
	_speaker.name = "SeekerName"
	_speaker.theme_type_variation = "HeaderLabel"
	_speaker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_speaker)
	_line = Label.new()
	_line.name = "SeekerLine"
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(_line)
	_continue = Button.new()
	_continue.name = "SeekerContinue"
	_continue.custom_minimum_size = Vector2(0, 96)
	_continue.theme_type_variation = "PrimaryButton"
	_continue.pressed.connect(dismiss)
	_continue.visible = not _external_continue
	copy.add_child(_continue)


func is_open() -> bool:
	return _open


func configure_external_continue(enabled: bool) -> void:
	_external_continue = enabled
	if is_instance_valid(_continue):
		_continue.visible = not enabled


func present(speaker: String, line: String, portrait: Texture2D = null) -> void:
	if line.strip_edges().is_empty():
		return
	if _open:
		dismiss()
	_speaker.text = speaker
	_line.text = line
	_continue.text = tr("BATTLE_SEEKER_CONTINUE")
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	visible = true
	_open = true
	opened.emit()
	if not _external_continue:
		_continue.grab_focus()
	await dismissed


func dismiss() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_continue.release_focus()
	dismissed.emit()


func _gui_input(event: InputEvent) -> void:
	if not _open or _external_continue:
		return
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		dismiss()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		accept_event()
		dismiss()
