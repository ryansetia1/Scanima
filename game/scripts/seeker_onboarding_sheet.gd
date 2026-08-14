class_name SeekerOnboardingSheet
extends UiBottomSheet

signal submit_requested(seeker_name: String, birth_year: Variant, gender: Variant)

const NAME_PATTERN := "^[A-Za-z][A-Za-z0-9_]{2,15}$"
const FIELD_NAME := &"name"
const FIELD_BIRTH_YEAR := &"birth_year"

@onready var _name: LineEdit = %SeekerName
@onready var _name_label: Label = %NameLabel
@onready var _birth_year: LineEdit = %BirthYear
@onready var _birth_label: Label = %BirthLabel
@onready var _gender: OptionButton = %Gender
@onready var _feedback: Label = %OnboardingFeedback
@onready var _submit: Button = %OnboardingSubmit

var _error_field := &""


func _ready() -> void:
	super._ready()
	_name.max_length = 16
	_birth_year.max_length = 4
	_gender.add_item(tr("SEEKER_GENDER_SKIP"), 0)
	_gender.add_item(tr("SEEKER_GENDER_WOMAN"), 1)
	_gender.add_item(tr("SEEKER_GENDER_MAN"), 2)
	_gender.add_item(tr("SEEKER_GENDER_NON_BINARY"), 3)
	_gender.add_item(tr("SEEKER_GENDER_ANOTHER"), 4)
	_gender.add_item(tr("SEEKER_GENDER_PREFER_NOT"), 5)
	_submit.pressed.connect(_submit_form)
	_name.text_submitted.connect(func(_value: String) -> void: _submit_form())
	_name.text_changed.connect(func(_value: String) -> void: _clear_error_for(FIELD_NAME))
	_birth_year.text_changed.connect(
		func(_value: String) -> void: _clear_error_for(FIELD_BIRTH_YEAR)
	)


func show_for_profile() -> void:
	_clear_error()
	_submit.disabled = false
	open()
	_name.grab_focus()


func set_busy(busy: bool) -> void:
	_submit.disabled = busy
	_name.editable = not busy
	_birth_year.editable = not busy
	_gender.disabled = busy


func show_error(message: String, field: StringName = FIELD_NAME) -> void:
	_clear_error()
	_error_field = field
	_feedback.text = message
	_feedback.visible = true
	set_busy(false)
	if field == FIELD_BIRTH_YEAR:
		_birth_label.theme_type_variation = &"ErrorLabel"
		_birth_year.theme_type_variation = &"ErrorLineEdit"
		_birth_year.grab_focus()
	else:
		_name_label.theme_type_variation = &"ErrorLabel"
		_name.theme_type_variation = &"ErrorLineEdit"
		_name.grab_focus()
	fit_to_content()


static func is_valid_seeker_name(value: String) -> bool:
	return RegEx.create_from_string(NAME_PATTERN).search(value) != null


func _submit_form() -> void:
	var seeker_name := _name.text
	if not is_valid_seeker_name(seeker_name):
		show_error(tr("SEEKER_NAME_INVALID"), FIELD_NAME)
		return
	var year: Variant = null
	var year_text := _birth_year.text.strip_edges()
	if not year_text.is_empty():
		if not year_text.is_valid_int():
			show_error(tr("SEEKER_BIRTH_YEAR_INVALID"), FIELD_BIRTH_YEAR)
			return
		year = year_text.to_int()
	var genders := [
		null,
		"woman",
		"man",
		"non_binary",
		"another_identity",
		"prefer_not_to_say",
	]
	submit_requested.emit(seeker_name, year, genders[_gender.selected])


func _clear_error_for(field: StringName) -> void:
	if _error_field == field:
		_clear_error()
		fit_to_content()


func _clear_error() -> void:
	_error_field = &""
	_feedback.text = ""
	_feedback.visible = false
	_name_label.theme_type_variation = &"SectionLabel"
	_name.theme_type_variation = &""
	_birth_label.theme_type_variation = &"SectionLabel"
	_birth_year.theme_type_variation = &""
