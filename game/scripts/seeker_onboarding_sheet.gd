class_name SeekerOnboardingSheet
extends UiBottomSheet

signal submit_requested(seeker_name: String, birth_year: Variant, gender: Variant)

@onready var _name: LineEdit = %SeekerName
@onready var _birth_year: LineEdit = %BirthYear
@onready var _gender: OptionButton = %Gender
@onready var _feedback: Label = %OnboardingFeedback
@onready var _submit: Button = %OnboardingSubmit


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


func show_for_profile() -> void:
	_feedback.text = ""
	_submit.disabled = false
	open()
	_name.grab_focus()


func set_busy(busy: bool) -> void:
	_submit.disabled = busy
	_name.editable = not busy
	_birth_year.editable = not busy
	_gender.disabled = busy


func show_error(message: String) -> void:
	_feedback.text = message
	set_busy(false)


func _submit_form() -> void:
	var year: Variant = null
	var year_text := _birth_year.text.strip_edges()
	if not year_text.is_empty():
		if not year_text.is_valid_int():
			show_error(tr("SEEKER_BIRTH_YEAR_INVALID"))
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
	submit_requested.emit(_name.text.strip_edges(), year, genders[_gender.selected])
