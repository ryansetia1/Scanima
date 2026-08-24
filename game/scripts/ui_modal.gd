class_name UiModal
extends Control

signal confirmed(text: String)
signal choice_selected(choice: String)
signal canceled

enum Mode {
	INFO,
	CONFIRM,
	INPUT,
	CHOICE,
}

const BODY_SCROLL_MAX_RATIO := 0.42
const BODY_SCROLL_MIN_PX := 96.0

@onready var _panel: PanelContainer = %ModalPanel
@onready var _title: Label = %ModalTitle
@onready var _portrait: TextureRect = %ModalPortrait
@onready var _hero: Label = %ModalHero
@onready var _body: Label = %ModalBody
@onready var _input: LineEdit = %ModalInput
@onready var _cancel_button: Button = %CancelButton
@onready var _primary_button: Button = %PrimaryButton
@onready var _choice_cancel_button: Button = %ChoiceCancelButton
@onready var _dismiss_button: Button = %DismissButton

var _mode := Mode.INFO
var _busy := false
var _dismissible := true
var _portrait_tween: Tween
var _body_scroll: ScrollContainer
var _fit_revision := 0


func _ready() -> void:
	z_index = 20
	_install_body_scroll()
	get_viewport().size_changed.connect(_request_fit_body_scroll)
	_dismiss_button.pressed.connect(_cancel)
	_cancel_button.pressed.connect(_on_cancel_button_pressed)
	_primary_button.pressed.connect(_submit)
	_choice_cancel_button.pressed.connect(_cancel)
	_input.text_submitted.connect(func(_text: String) -> void: _submit())
	UiJuice.install_buttons(self)


## `hero_text` is the one line that outranks the title: the Level Up dialog puts
## the new `Lv. N` there. Every other dialog leaves it empty and the slot hides.
func open_info(
	title_text: String,
	body_text: String,
	close_text: String,
	hero_text: String = "",
	dismissible: bool = true
) -> void:
	_configure(
		Mode.INFO, title_text, body_text, close_text, "", false, hero_text, dismissible
	)
	_show_modal(_primary_button)


func open_result(
	title_text: String,
	body_text: String,
	close_text: String,
	hero_text: String,
	portrait: Texture2D,
	dismissible: bool = true
) -> void:
	_configure(
		Mode.INFO, title_text, body_text, close_text, "", false, hero_text, dismissible
	)
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_show_modal(_primary_button)
	if _portrait.visible:
		_animate_result_portrait()


func open_result_choice(
	title_text: String,
	body_text: String,
	primary_text: String,
	secondary_text: String,
	hero_text: String,
	portrait: Texture2D,
	dismissible: bool = false
) -> void:
	_configure(
		Mode.CHOICE,
		title_text,
		body_text,
		primary_text,
		secondary_text,
		false,
		hero_text,
		dismissible
	)
	_choice_cancel_button.visible = false
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_show_modal(_primary_button)
	if _portrait.visible:
		_animate_result_portrait()


func open_confirm(
	title_text: String,
	body_text: String,
	confirm_text: String,
	cancel_text: String,
	destructive: bool = false,
	dismissible: bool = true
) -> void:
	_configure(
		Mode.CONFIRM,
		title_text,
		body_text,
		confirm_text,
		cancel_text,
		destructive,
		"",
		dismissible
	)
	_show_modal(_cancel_button)


func open_choice(
	title_text: String,
	body_text: String,
	primary_text: String,
	secondary_text: String,
	cancel_text: String
) -> void:
	_configure(Mode.CHOICE, title_text, body_text, primary_text, secondary_text, false)
	_choice_cancel_button.text = cancel_text
	_show_modal(_primary_button)


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
	_choice_cancel_button.disabled = busy
	_dismiss_button.disabled = busy or not _dismissible
	_input.editable = not busy


func close() -> void:
	_stop_portrait_tween()
	if visible:
		UiJuice.hide_overlay(self, _panel)


func request_cancel() -> void:
	_cancel()


func input_text() -> String:
	return _input.text


func _configure(
	mode: Mode,
	title_text: String,
	body_text: String,
	primary_text: String,
	cancel_text: String,
	destructive: bool,
	hero_text: String = "",
	dismissible: bool = true
) -> void:
	_mode = mode
	_dismissible = dismissible
	set_busy(false)
	_title.text = title_text
	_stop_portrait_tween()
	_portrait.texture = null
	_portrait.visible = false
	_portrait.scale = Vector2.ONE
	_portrait.rotation = 0.0
	_portrait.modulate = Color.WHITE
	_hero.text = hero_text
	_hero.visible = not hero_text.is_empty()
	_body.text = body_text
	_body.visible = not body_text.is_empty()
	_body_scroll.visible = _body.visible
	_request_fit_body_scroll()
	_input.visible = mode == Mode.INPUT
	_cancel_button.visible = mode != Mode.INFO
	_choice_cancel_button.visible = mode == Mode.CHOICE
	_cancel_button.text = cancel_text
	_primary_button.text = primary_text
	_primary_button.theme_type_variation = &"DangerButton" if destructive else &"PrimaryButton"


func _show_modal(focus_target: Control) -> void:
	UiJuice.show_overlay(self, _panel)
	_request_fit_body_scroll()
	_focus_after_layout(focus_target)


## `call_deferred` alone fires before the Label's autowrap has resolved against
## its real width on a fresh text value, so the very first open of a dialog
## with new/longer body text can measure too many wrapped lines and lock in a
## too-tall scroll height that nothing re-triggers afterward -- a reopen with
## text Godot already wrapped once reads back correctly. Waiting a full frame
## lets layout settle first, same fix as the toast's `_relayout_toast_after_minimum_update`.
func _request_fit_body_scroll() -> void:
	_fit_revision += 1
	var revision := _fit_revision
	_fit_body_scroll_after_layout(revision)


func _fit_body_scroll_after_layout(revision: int) -> void:
	await get_tree().process_frame
	if revision == _fit_revision:
		_fit_body_scroll()


func _install_body_scroll() -> void:
	var column := _body.get_parent()
	var body_index := _body.get_index()
	column.remove_child(_body)
	_body_scroll = ScrollContainer.new()
	_body_scroll.name = "ModalBodyScroll"
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.follow_focus = true
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_body_scroll)
	column.move_child(_body_scroll, body_index)
	_body_scroll.add_child(_body)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _fit_body_scroll() -> void:
	if not is_instance_valid(_body_scroll):
		return
	if not _body.visible:
		_body_scroll.custom_minimum_size.y = 0.0
		return
	var max_height := maxf(BODY_SCROLL_MIN_PX, get_viewport_rect().size.y * BODY_SCROLL_MAX_RATIO)
	var natural_height := _body.get_combined_minimum_size().y
	_body_scroll.custom_minimum_size.y = minf(natural_height, max_height)


func _animate_result_portrait() -> void:
	await get_tree().process_frame
	if not visible or not is_instance_valid(_portrait) or _portrait.texture == null:
		return
	_stop_portrait_tween()
	_portrait.pivot_offset = _portrait.size * 0.5
	_portrait.scale = Vector2(0.52, 0.52)
	_portrait.rotation = -0.055
	_portrait.modulate = Color(0.72, 0.92, 1.08, 0.0)
	_portrait_tween = create_tween().set_parallel(true)
	_portrait_tween.tween_property(_portrait, "modulate", Color.WHITE, 0.24) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_portrait_tween.tween_property(_portrait, "scale", Vector2(1.08, 1.08), 0.38) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_portrait_tween.tween_property(_portrait, "rotation", 0.0, 0.30) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_portrait_tween.chain().tween_property(_portrait, "scale", Vector2.ONE, 0.14) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _stop_portrait_tween() -> void:
	if _portrait_tween != null and _portrait_tween.is_valid():
		_portrait_tween.kill()
	_portrait_tween = null


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
	if _mode == Mode.CHOICE:
		_submit_choice("primary")
		return
	var text := _input.text if _mode == Mode.INPUT else ""
	close()
	confirmed.emit(text)


func _on_cancel_button_pressed() -> void:
	if _mode == Mode.CHOICE:
		_submit_choice("secondary")
		return
	if _busy:
		return
	# A locked outcome still exposes its explicit Close button; only backdrop and
	# Android Back are blocked by `_dismissible`.
	close()
	canceled.emit()


func _submit_choice(choice: String) -> void:
	if _busy:
		return
	close()
	choice_selected.emit(choice)


func _cancel() -> void:
	if _busy or not _dismissible:
		return
	close()
	canceled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
