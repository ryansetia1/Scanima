class_name HomeView
extends Control

signal care_requested(action: String)

const CARE_RULES: GDScript = preload("res://scripts/care_rules.gd")

@onready var _identity: Control = %Identity
@onready var _anima_name: Label = %AnimaName
@onready var _anima_meta: Label = %AnimaMeta
@onready var _care_dock: PanelContainer = %CareDock
@onready var _care_summary: Label = %CareSummary
@onready var _need_hunger: ProgressBar = %NeedHunger
@onready var _need_energy: ProgressBar = %NeedEnergy
@onready var _need_hygiene: ProgressBar = %NeedHygiene
@onready var _need_bond: ProgressBar = %NeedBond
@onready var _care_actions: GridContainer = %CareActions
@onready var _feed_button: Button = %FeedButton
@onready var _clean_button: Button = %CleanButton
@onready var _sleep_button: Button = %SleepButton
@onready var _play_button: Button = %PlayButton

var _row: Dictionary = {}


func _ready() -> void:
	_feed_button.pressed.connect(care_requested.emit.bind("feed"))
	_clean_button.pressed.connect(care_requested.emit.bind("clean"))
	_sleep_button.pressed.connect(_request_sleep_toggle)
	_play_button.pressed.connect(care_requested.emit.bind("play"))
	resized.connect(_update_action_columns)
	LocaleManager.locale_changed.connect(_update_action_columns)
	_update_action_columns.call_deferred()


func set_anima(row: Dictionary, busy: bool) -> void:
	_row = row.duplicate(true)
	if _row.is_empty():
		_anima_name.text = tr("HOME_EMPTY_NAME")
		_anima_meta.text = tr("HOME_EMPTY_META")
		_care_dock.visible = false
		_set_buttons_disabled(true)
		return

	_anima_name.text = LocaleManager.display_name(_row)
	_anima_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.element_name(str(_row.get("element", ""))),
		LocaleManager.stage_name(int(_row.get("stage", 1))),
	]
	_identity.visible = true
	update_care(_row, busy)


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
	UiJuice.tween_meter(_need_bond, care["bond"])

	var sleeping := _has_timestamp(_row.get("sleep_started_at"))
	var dormant := _has_timestamp(_row.get("dormant_since"))
	_care_summary.text = tr("HOME_CARE_SUMMARY") % [
		tr("HOME_CARE_SCORE") % LocaleManager.format_integer(int(_row.get("care_score", 0))),
		LocaleManager.care_state(sleeping, dormant),
	]
	_sleep_button.text = tr("CARE_WAKE") if sleeping else tr("CARE_SLEEP")
	_update_action_state(busy)


func set_busy(busy: bool) -> void:
	_update_action_state(busy or typeof(_row.get("care")) != TYPE_DICTIONARY)


func _request_sleep_toggle() -> void:
	care_requested.emit("wake" if _has_timestamp(_row.get("sleep_started_at")) else "sleep")


func _set_buttons_disabled(disabled: bool) -> void:
	_update_action_state(disabled)


func _update_action_state(disabled: bool) -> void:
	var has_care := typeof(_row.get("care")) == TYPE_DICTIONARY
	var care: Dictionary = CARE_RULES.normalized_care(_row.get("care"))
	var sleeping := has_care and _has_timestamp(_row.get("sleep_started_at"))
	_feed_button.visible = not sleeping
	_clean_button.visible = not sleeping
	_play_button.visible = not sleeping
	_sleep_button.visible = true
	_feed_button.disabled = disabled
	_clean_button.disabled = disabled
	_sleep_button.disabled = disabled
	_play_button.disabled = disabled or float(care["bond"]) >= 100.0
	_update_action_columns()


func _update_action_columns(_locale: String = "") -> void:
	if not is_instance_valid(_care_actions):
		return
	if _has_timestamp(_row.get("sleep_started_at")):
		_care_actions.columns = 1
		return
	if _care_actions.size.x <= 0.0:
		return
	var widest := 0.0
	for button in [_feed_button, _clean_button, _sleep_button, _play_button]:
		widest = maxf(widest, button.get_combined_minimum_size().x)
	var four_column_width := widest * 4.0 + _care_actions.get_theme_constant("h_separation") * 3.0
	_care_actions.columns = 2 if four_column_width > _care_actions.size.x else 4


static func _has_timestamp(value: Variant) -> bool:
	return value != null and not str(value).is_empty()
