class_name UiModal
extends Control

signal confirmed(text: String)
signal canceled

enum Mode {
	INFO,
	CONFIRM,
	INPUT,
}

@onready var _panel: PanelContainer = %ModalPanel
@onready var _title: Label = %ModalTitle
@onready var _body: Label = %ModalBody
@onready var _input: LineEdit = %ModalInput
@onready var _cancel_button: Button = %CancelButton
@onready var _primary_button: Button = %PrimaryButton
@onready var _dismiss_button: Button = %DismissButton

var _mode := Mode.INFO
var _busy := false


func _ready() -> void:
	_dismiss_button.pressed.connect(_cancel)
	_cancel_button.pressed.connect(_cancel)
	_primary_button.pressed.connect(_submit)
	_input.text_submitted.connect(func(_text: String) -> void: _submit())
	UiJuice.install_buttons(self)


func open_info(
	title_text: String,
	body_text: String,
	close_text: String
) -> void:
	_configure(Mode.INFO, title_text, body_text, close_text, "", false)
	_show_modal(_primary_button)


func open_confirm(
	title_text: String,
	body_text: String,
	confirm_text: String,
	cancel_text: String,
	destructive: bool = false
) -> void:
	_configure(
		Mode.CONFIRM,
		title_text,
		body_text,
		confirm_text,
		cancel_text,
		destructive
	)
	_show_modal(_cancel_button)


func open_input(
	title_text: String,
	body_text: String,
	initial_text: String,
	confirm_text: String,
	cancel_text: String,
	placeholder_text: String,
	max_length: int = 32
) -> void:
	_configure(Mode.INPUT, title_text, body_text, confirm_text, cancel_text, false)
	_input.max_length = max_length
	_input.placeholder_text = placeholder_text
	_input.text = initial_text
	_show_modal(_input)


func set_busy(busy: bool) -> void:
	_busy = busy
	_primary_button.disabled = busy
	_cancel_button.disabled = busy
	_dismiss_button.disabled = busy
	_input.editable = not busy


func close() -> void:
	if visible:
		UiJuice.hide_overlay(self, _panel)


func input_text() -> String:
	return _input.text


func _configure(
	mode: Mode,
	title_text: String,
	body_text: String,
	primary_text: String,
	cancel_text: String,
	destructive: bool
) -> void:
	_mode = mode
	set_busy(false)
	_title.text = title_text
	_body.text = body_text
	_body.visible = not body_text.is_empty()
	_input.visible = mode == Mode.INPUT
	_cancel_button.visible = mode != Mode.INFO
	_cancel_button.text = cancel_text
	_primary_button.text = primary_text
	_primary_button.theme_type_variation = &"DangerButton" if destructive else &"PrimaryButton"


func _show_modal(focus_target: Control) -> void:
	UiJuice.show_overlay(self, _panel)
	_focus_after_layout(focus_target)


func _focus_after_layout(target: Control) -> void:
	await get_tree().process_frame
	if not visible or not is_instance_valid(target):
		return
	target.grab_focus()
	if target == _input:
		_input.select_all()


func _submit() -> void:
	if _busy:
		return
	var text := _input.text if _mode == Mode.INPUT else ""
	close()
	confirmed.emit(text)


func _cancel() -> void:
	if _busy:
		return
	close()
	canceled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
