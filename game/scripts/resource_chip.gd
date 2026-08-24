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
	_action_button.pressed.connect(pressed.emit)
	UiJuice.install_button(_action_button)


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
