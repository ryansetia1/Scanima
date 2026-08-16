class_name HomeView
extends Control

signal care_requested(action: String)
signal care_blocked(message: String)
signal first_scan_requested
signal retry_requested

const CARE_RULES: GDScript = preload("res://scripts/care_rules.gd")

@onready var _identity: VBoxContainer = %Identity
@onready var _anima_name: Label = %AnimaName
@onready var _anima_meta: Label = %AnimaMeta
@onready var _stage_space: Control = %StageSpace
@onready var _stage_footer_space: Control = %StageFooterSpace
@onready var _care_dock: PanelContainer = %CareDock
@onready var _primary_action: Button = %HomePrimaryAction
@onready var _care_summary: Label = %CareSummary
@onready var _need_hunger: ProgressBar = %NeedHunger
@onready var _need_energy: ProgressBar = %NeedEnergy
@onready var _need_hygiene: ProgressBar = %NeedHygiene
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


func _ready() -> void:
	_feed_button.pressed.connect(_request_feed)
	_clean_button.pressed.connect(_request_clean)
	_sleep_button.pressed.connect(_request_sleep_toggle)
	_play_button.pressed.connect(_request_play)
	_primary_action.pressed.connect(_request_primary_action)
	_set_loading_layout(true)


func set_anima(row: Dictionary, busy: bool) -> void:
	_row = row.duplicate(true)
	if _row.is_empty():
		if _shell_state != &"loading" and _shell_state != &"error":
			set_shell_state(&"empty")
		return

	_shell_state = &"ready"
	_anima_name.text = LocaleManager.display_name(_row)
	_anima_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(CARE_RULES.level_from_exp(int(_row.get("care_score", 0)))),
		LocaleManager.element_compact(_row),
	]
	_set_loading_layout(false)
	_identity.visible = true
	_primary_action.visible = false
	update_care(_row, busy)


func set_shell_state(state: StringName) -> void:
	_shell_state = state
	_row = {}
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


func shell_state() -> StringName:
	return _shell_state


func _set_loading_layout(centered: bool) -> void:
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
	_care_summary.text = tr("HOME_CARE_SUMMARY") % [
		exp_label,
		LocaleManager.care_state(sleeping, dormant),
	]
	_sleep_button.text = tr("CARE_WAKE") if sleeping else tr("CARE_SLEEP")
	_play_button.text = tr("CARE_PLAY")
	_update_action_state(busy)


func set_busy(busy: bool) -> void:
	_primary_action.disabled = busy
	_update_action_state(busy or typeof(_row.get("care")) != TYPE_DICTIONARY)


func pulse_progress() -> void:
	if _identity.visible:
		UiJuice.pop(_anima_meta, 1.05)
	if _care_dock.visible:
		UiJuice.pop(_care_summary, 1.08)
		UiJuice.pop(_need_exp, 1.06)


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
