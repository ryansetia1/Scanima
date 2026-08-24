class_name ResourceChip
extends PanelContainer

signal pressed

const TEXT_SEPARATION := -4
const ICON_SEPARATION := 8
const INLINE_SEPARATION := 8

@onready var _column: BoxContainer = $Column
@onready var _icon: TextureRect = %Icon
@onready var _value_label: Label = %Value
@onready var _name_label: Label = %Name
@onready var _action_button: Button = %ActionButton


func _ready() -> void:
	_action_button.pressed.connect(_on_action_pressed)
	_action_button.button_down.connect(_on_action_button_down)
	_action_button.button_up.connect(_on_action_button_up)
	_action_button.mouse_entered.connect(_on_action_hover.bind(true))
	_action_button.mouse_exited.connect(_on_action_hover.bind(false))
	_action_button.focus_entered.connect(_on_action_hover.bind(true))
	_action_button.focus_exited.connect(_on_action_hover.bind(false))
	resized.connect(_update_pivot)
	_update_pivot()
	if theme_type_variation == &"GhostChip":
		_value_label.theme_type_variation = &"GhostChipValueLabel"
		_name_label.theme_type_variation = &"GhostChipNameLabel"
		_column.alignment = BoxContainer.ALIGNMENT_END


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_action_button_down() -> void:
	UiJuice.play_button(_action_button)
	_update_pivot()
	var tilt := -0.025 if get_instance_id() % 2 == 0 else 0.025
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.90, 0.90), 0.08) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "rotation", tilt, 0.08)
	tween.tween_property(self, "modulate", Color(1.15, 1.15, 1.15, 1.0), 0.08)


func _on_action_button_up() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.28) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "rotation", 0.0, 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate", Color.WHITE, 0.20)


func _on_action_hover(hovered: bool) -> void:
	if not _action_button.visible or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_update_pivot()
	var target_scale := Vector2(1.05, 1.05) if hovered else Vector2.ONE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", target_scale, 0.16) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(
		self,
		"modulate",
		Color(1.06, 1.06, 1.06, 1.0) if hovered else Color.WHITE,
		0.16
	)


func _on_action_pressed() -> void:
	UiJuice.pop(self, 1.08)
	pressed.emit()


func set_icon(texture: Texture2D) -> void:
	_icon.texture = texture
	_icon.visible = texture != null
	_column.add_theme_constant_override(
		"separation",
		ICON_SEPARATION if texture != null else TEXT_SEPARATION
	)


## Counters read as one phrase — "30 Bits" — while Shop and Bag stack a painted
## icon over a single label. `Column` is a plain `BoxContainer` for exactly this:
## `VBoxContainer` refuses `vertical = false` outright ("Can't change orientation
## of VBoxContainer") and the layout silently stays stacked, so the flip has to
## come from a node that never fixed its axis in the first place.
func set_inline(inline: bool) -> void:
	_column.vertical = not inline
	_column.add_theme_constant_override(
		"separation", INLINE_SEPARATION if inline else TEXT_SEPARATION
	)


func set_value_text(value_text: String) -> void:
	_value_label.text = value_text


func set_name_text(name_text: String) -> void:
	_name_label.text = name_text
	_name_label.visible = not name_text.is_empty()


func set_interactive(interactive: bool, tooltip: String = "") -> void:
	_action_button.visible = interactive
	_action_button.focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	_action_button.tooltip_text = tooltip


func value_label() -> Label:
	return _value_label


## Chip's icon sits centered in the upper part of the column, above Value/Name
## -- the chip's own global rect is noticeably taller (it reserves room for
## that label underneath), so its center lands well below the icon glyph.
## Callers that need to point at the icon itself (not the whole chip) want
## this, not `get_global_rect()`.
func icon_global_rect() -> Rect2:
	return _icon.get_global_rect()
