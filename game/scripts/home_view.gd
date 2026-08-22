class_name HomeView
extends Control

signal care_requested(action: String)
signal care_blocked(message: String)
signal first_scan_requested
signal retry_requested

const CARE_RULES: GDScript = preload("res://scripts/care_rules.gd")

## Needs read as bars at rest. The exact number is one tap away, and the three
## reveal together with a short stagger so a single gesture answers "how is my
## companion doing" instead of one chip at a time.
const VALUE_STAGGER := 0.06

## The hold runs from the tap, so the 0,5 s reveal is part of it and the numbers
## sit fully lit for about three seconds before letting themselves out.
const VALUE_HOLD := 3.5
const CONTROLS_MAX_HEIGHT_RATIO := 0.44
const CONTROLS_MIN_HEIGHT_PX := 180.0

@onready var _identity_row: HBoxContainer = %IdentityRow
@onready var _identity: VBoxContainer = %Identity
@onready var _chip_gutter: Control = %ChipGutter
@onready var _anima_name: Label = %AnimaName
@onready var _anima_meta: Label = %AnimaMeta
@onready var _stage_space: Control = %StageSpace
@onready var _stage_footer_space: Control = %StageFooterSpace
@onready var _controls_scroll: ScrollContainer = %HomeControlsScroll
@onready var _controls_content: VBoxContainer = %HomeControlsContent
@onready var _care_dock: PanelContainer = %CareDock
@onready var _primary_action: Button = %HomePrimaryAction
@onready var _care_summary: Label = %CareSummary
@onready var _need_hunger: ProgressBar = %NeedHunger
@onready var _need_energy: ProgressBar = %NeedEnergy
@onready var _need_hygiene: ProgressBar = %NeedHygiene
@onready var _hunger_value: Label = %HungerValue
@onready var _energy_value: Label = %EnergyValue
@onready var _hygiene_value: Label = %HygieneValue
@onready var _hunger_chip: PanelContainer = %HungerChip
@onready var _energy_chip: PanelContainer = %EnergyChip
@onready var _hygiene_chip: PanelContainer = %HygieneChip
@onready var _need_exp: ProgressBar = %NeedExp
@onready var _care_actions: GridContainer = %CareActions
@onready var _feed_button: Button = %FeedButton
@onready var _clean_button: Button = %CleanButton
@onready var _sleep_button: Button = %SleepButton
@onready var _play_button: Button = %PlayButton

var _row: Dictionary = {}
var _shell_state := &"loading"
var _values_shown := false
var _values_toggled_frame := -1
var _values_token := 0


func _ready() -> void:
	resized.connect(_fit_controls_scroll)
	_feed_button.pressed.connect(_request_feed)
	_clean_button.pressed.connect(_request_clean)
	_sleep_button.pressed.connect(_request_sleep_toggle)
	_play_button.pressed.connect(_request_play)
	_primary_action.pressed.connect(_request_primary_action)
	for chip in _need_chips():
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.gui_input.connect(_on_need_chip_input)
		# The whole chip is the target, so nothing inside it may answer input.
		# ProgressBar defaults to STOP and ate every tap that landed on the bar
		# itself; Label defaults to IGNORE, which is why only the caption row
		# ever responded. Sweeping the subtree keeps the next child honest too.
		for inner in chip.find_children("*", "Control", true, false):
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label in _value_labels():
		label.modulate.a = 0.0
	_set_loading_layout(true)
	_fit_controls_scroll.call_deferred()


func _fit_controls_scroll() -> void:
	var natural_height := _controls_content.get_combined_minimum_size().y
	var max_height := maxf(CONTROLS_MIN_HEIGHT_PX, size.y * CONTROLS_MAX_HEIGHT_RATIO)
	_controls_scroll.custom_minimum_size.y = minf(natural_height, max_height)
	_controls_scroll.visible = natural_height > 0.0


func set_anima(row: Dictionary, busy: bool) -> void:
	_row = row.duplicate(true)
	if _row.is_empty():
		if _shell_state != &"loading" and _shell_state != &"error":
			set_shell_state(&"empty")
		return

	_shell_state = &"ready"
	_set_headline_wrapping(false)
	_anima_name.text = LocaleManager.display_name(_row)
	_anima_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(CARE_RULES.level_from_exp(int(_row.get("care_score", 0)))),
		LocaleManager.element_compact(_row),
	]
	_set_loading_layout(false)
	_identity.visible = true
	_primary_action.visible = false
	update_care(_row, busy)
	_fit_controls_scroll.call_deferred()


func set_shell_state(state: StringName) -> void:
	_shell_state = state
	_row = {}
	_set_headline_wrapping(true)
	_care_dock.visible = false
	_set_buttons_disabled(true)
	_identity.visible = true
	_primary_action.visible = state == &"empty" or state == &"error"
	_set_loading_layout(state == &"loading")
	match state:
		&"error":
			_anima_name.text = tr("HOME_ERROR_NAME")
			_anima_meta.text = tr("HOME_ERROR_META")
			_primary_action.text = tr("ACTION_RETRY")
		&"empty":
			_anima_name.text = tr("HOME_EMPTY_NAME")
			_anima_meta.text = tr("HOME_EMPTY_META")
			_primary_action.text = tr("HOME_EMPTY_CTA")
		_:
			_anima_name.text = tr("HOME_LOADING_NAME")
			_anima_meta.text = tr("HOME_LOADING_META")
	_fit_controls_scroll.call_deferred()


func shell_state() -> StringName:
	return _shell_state


func set_chip_gutter(width: float) -> void:
	_chip_gutter.custom_minimum_size.x = maxf(width, 0.0)


# A nickname stays on one line next to the chips, but loading, empty, and error
# headlines are sentences that no longer fit that width. Autowrap and ellipsis
# trimming must move together: together they make Label height-aware, the row
# only reserves one line, and the headline then renders empty.
func _set_headline_wrapping(multiline: bool) -> void:
	_anima_name.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART if multiline else TextServer.AUTOWRAP_OFF
	)
	_anima_name.text_overrun_behavior = (
		TextServer.OVERRUN_NO_TRIMMING if multiline else TextServer.OVERRUN_TRIM_ELLIPSIS
	)


func _set_loading_layout(centered: bool) -> void:
	_identity_row.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL if centered else Control.SIZE_SHRINK_BEGIN
	)
	_identity.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL if centered else Control.SIZE_SHRINK_BEGIN
	)
	_identity.alignment = (
		BoxContainer.ALIGNMENT_CENTER if centered else BoxContainer.ALIGNMENT_BEGIN
	)
	_stage_space.visible = not centered
	_stage_footer_space.visible = not centered


func update_care(row: Dictionary, busy: bool) -> void:
	_row = row.duplicate(true)
	var has_care := typeof(_row.get("care")) == TYPE_DICTIONARY
	var reveal := has_care and not _care_dock.visible
	_care_dock.visible = has_care
	if not has_care:
		_set_buttons_disabled(true)
		return
	if reveal:
		UiJuice.reveal(_care_dock)

	var care: Dictionary = CARE_RULES.normalized_care(_row.get("care"))
	UiJuice.tween_meter(_need_hunger, care["hunger"])
	UiJuice.tween_meter(_need_energy, care["energy"])
	UiJuice.tween_meter(_need_hygiene, care["hygiene"])
	_hunger_value.text = LocaleManager.format_percent(care["hunger"])
	_energy_value.text = LocaleManager.format_percent(care["energy"])
	_hygiene_value.text = LocaleManager.format_percent(care["hygiene"])
	_set_need_alert(_hunger_chip, CARE_RULES.need_is_low(care, "hunger"))
	_set_need_alert(_energy_chip, CARE_RULES.need_is_low(care, "energy"))
	_set_need_alert(_hygiene_chip, CARE_RULES.need_is_low(care, "hygiene"))
	var total_exp := int(_row.get("care_score", 0))
	UiJuice.tween_meter(_need_exp, CARE_RULES.exp_progress(total_exp))

	var sleeping := _has_timestamp(_row.get("sleep_started_at"))
	var dormant := _has_timestamp(_row.get("dormant_since"))
	var level: int = CARE_RULES.level_from_exp(total_exp)
	var exp_label: String = tr("HOME_LEVEL_MAX") % LocaleManager.format_integer(level)
	if level < CARE_RULES.LEVEL_CAP:
		exp_label = tr("HOME_LEVEL_EXP") % [
			LocaleManager.format_integer(level),
			LocaleManager.format_integer(CARE_RULES.exp_into_level(total_exp)),
			LocaleManager.format_integer(CARE_RULES.exp_to_next_level(level)),
		]
	# Active is the resting state, so naming it is noise on every single refresh.
	# Sleeping and Dormant stay: they are what explains the collapsed action row.
	_care_summary.text = exp_label
	if sleeping or dormant:
		_care_summary.text = tr("HOME_CARE_SUMMARY") % [
			exp_label,
			LocaleManager.care_state(sleeping, dormant),
		]
	_sleep_button.text = tr("CARE_WAKE") if sleeping else tr("CARE_SLEEP")
	_play_button.text = tr("CARE_PLAY")
	_update_action_state(busy)
	_restart_value_hold()
	_fit_controls_scroll.call_deferred()


func set_busy(busy: bool) -> void:
	_primary_action.disabled = busy
	_update_action_state(busy or typeof(_row.get("care")) != TYPE_DICTIONARY)


func pulse_progress() -> void:
	if _identity.visible:
		UiJuice.pop(_anima_meta, 1.05)
	if _care_dock.visible:
		UiJuice.pop(_care_summary, 1.08)
		UiJuice.pop(_need_exp, 1.06)


func _on_need_chip_input(event: InputEvent) -> void:
	if not _is_tap(event):
		return
	# Touch emulation hands the same finger over twice, as a screen touch and as
	# a synthetic mouse press. A toggle that runs twice reads as a dead tap.
	var frame := Engine.get_process_frames()
	if frame == _values_toggled_frame:
		return
	_values_toggled_frame = frame
	set_need_values_shown(not _values_shown)


func set_need_values_shown(shown: bool) -> void:
	_values_shown = shown
	var labels := _value_labels()
	for index in labels.size():
		var delay := VALUE_STAGGER * float(index)
		if shown:
			UiJuice.reveal(labels[index], delay)
		else:
			UiJuice.dismiss(labels[index], delay)
	_restart_value_hold()


## The numbers leave the same way they arrived instead of waiting for a second
## tap. Bumping the token here is what cancels an earlier hold, so hiding early
## or revealing again never leaves a stale timer to snuff the next reveal. A care
## refresh restarts it: tapping Feed with a second left should still let the
## player watch Hunger climb.
func _restart_value_hold() -> void:
	_values_token += 1
	if not _values_shown or not is_inside_tree():
		return
	var token := _values_token
	await get_tree().create_timer(VALUE_HOLD).timeout
	if not is_instance_valid(self) or token != _values_token or not _values_shown:
		return
	set_need_values_shown(false)


func need_values_shown() -> bool:
	return _values_shown


func _value_labels() -> Array[Label]:
	var labels: Array[Label] = [_hunger_value, _hygiene_value, _energy_value]
	return labels


func _need_chips() -> Array[PanelContainer]:
	var chips: Array[PanelContainer] = [_hunger_chip, _hygiene_chip, _energy_chip]
	return chips


static func _is_tap(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
	)


func _request_feed() -> void:
	if CARE_RULES.need_is_full(_row.get("care"), "hunger"):
		care_blocked.emit(tr("ERROR_NEED_FULL"))
		return
	care_requested.emit("feed")


func _request_clean() -> void:
	if CARE_RULES.need_is_full(_row.get("care"), "hygiene"):
		care_blocked.emit(tr("ERROR_NEED_FULL"))
		return
	care_requested.emit("clean")


func _request_play() -> void:
	if _play_capped():
		care_blocked.emit(tr("ERROR_PLAY_CAPPED"))
		return
	care_requested.emit("play")


func _request_sleep_toggle() -> void:
	care_requested.emit("wake" if _has_timestamp(_row.get("sleep_started_at")) else "sleep")


func _request_primary_action() -> void:
	if _shell_state == &"error":
		retry_requested.emit()
	elif _shell_state == &"empty":
		first_scan_requested.emit()


func _set_buttons_disabled(disabled: bool) -> void:
	_update_action_state(disabled)


func _update_action_state(disabled: bool) -> void:
	var has_care := typeof(_row.get("care")) == TYPE_DICTIONARY
	var sleeping := has_care and _has_timestamp(_row.get("sleep_started_at"))
	_feed_button.visible = not sleeping
	_clean_button.visible = not sleeping
	_play_button.visible = not sleeping
	_sleep_button.visible = true
	_feed_button.disabled = disabled
	_clean_button.disabled = disabled
	_sleep_button.disabled = disabled
	# Godot ignores pressed on disabled buttons, so full needs and the daily cap
	# only dim the action. Tap still reaches the handler and toasts.
	_play_button.disabled = disabled
	_feed_button.self_modulate = (
		Color(1, 1, 1, 0.42) if not disabled and CARE_RULES.need_is_full(_row.get("care"), "hunger") else Color.WHITE
	)
	_clean_button.self_modulate = (
		Color(1, 1, 1, 0.42) if not disabled and CARE_RULES.need_is_full(_row.get("care"), "hygiene") else Color.WHITE
	)
	_play_button.self_modulate = (
		Color(1, 1, 1, 0.42) if not disabled and _play_capped() else Color.WHITE
	)
	if is_instance_valid(_care_actions):
		_care_actions.columns = 1 if sleeping else 4


func _play_capped() -> bool:
	return CARE_RULES.play_exp_remaining(_row) <= 0


static func _set_need_alert(chip: PanelContainer, low: bool) -> void:
	chip.theme_type_variation = &"NeedChipLow" if low else &"NeedChip"


static func _has_timestamp(value: Variant) -> bool:
	return value != null and not str(value).is_empty()
