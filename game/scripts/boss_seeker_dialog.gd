class_name BossSeekerDialog
extends Control

signal dismissed

var _open := false
var _backdrop: ColorRect
var _portrait: TextureRect
var _speaker: Label
var _line: Label
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 24
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.012, 0.02, 0.05, 0.72)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 16.0
	panel.offset_right = -16.0
	panel.offset_top = -336.0
	panel.offset_bottom = -24.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.theme_type_variation = "HudSurface"
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	_portrait = TextureRect.new()
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
	_hint = Label.new()
	_hint.name = "SeekerContinue"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate = Color(1, 1, 1, 0.72)
	copy.add_child(_hint)


func is_open() -> bool:
	return _open


func present(speaker: String, line: String, portrait: Texture2D = null) -> void:
	if line.strip_edges().is_empty():
		return
	if _open:
		dismiss()
	_speaker.text = speaker
	_line.text = line
	_hint.text = tr("EXPEDITION_SEEKER_CONTINUE")
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	visible = true
	_open = true
	await dismissed


func dismiss() -> void:
	if not _open:
		return
	_open = false
	visible = false
	dismissed.emit()


func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		dismiss()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		accept_event()
		dismiss()
