class_name TeamRosterList
extends ItemList

## Touch-first multi-pick. `_order` is pick/save order (first tap = slot 1 =
## battle lead). Godot `get_selected_items()` is index-sorted only; callers must
## use `get_chosen_indices_ordered()` for payloads.

signal selection_changed

const SELECTED_BG := Color(0.055, 0.105, 0.2, 0.96)
const SELECTED_BORDER := Color(0.42, 0.9, 0.82, 1.0)
const SELECTED_TEXT := Color(0.9, 0.96, 1.0, 1.0)
const BADGE_INK := Color(0.025, 0.065, 0.13, 1.0)
const TEAM_SIZE := 4

var _order: Array[int] = []


func _ready() -> void:
	# Not SELECT_MULTI. Pressing an already-selected item there sets Godot's
	# `defer_select_single` and returns *before* emitting `item_clicked`, so the
	# tap never reaches `_on_item_clicked`; the release then runs
	# `select(i, true)`, which drops every other item. A deselect tap therefore
	# repainted the list as if that one card were the whole team while `_order`
	# still held all three. SELECT_TOGGLE flips the pressed item on press and
	# always emits, which is also the tap-to-toggle contract this list wants.
	select_mode = SELECT_TOGGLE
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = SELECTED_BG
	selected_style.border_color = SELECTED_BORDER
	selected_style.set_border_width_all(3)
	selected_style.set_corner_radius_all(12)
	add_theme_stylebox_override("selected", selected_style)
	add_theme_stylebox_override("selected_focus", selected_style)
	add_theme_stylebox_override("hovered_selected", selected_style)
	add_theme_stylebox_override("hovered_selected_focus", selected_style)
	# Cursor and hover paint over the icon and label, and on touch the hover band
	# stays behind after the finger lifts, reading as a second selected card.
	add_theme_stylebox_override("cursor", StyleBoxEmpty.new())
	add_theme_stylebox_override("cursor_unfocused", StyleBoxEmpty.new())
	add_theme_stylebox_override("hovered", StyleBoxEmpty.new())
	add_theme_color_override("font_selected_color", SELECTED_TEXT)
	add_theme_color_override("font_hovered_selected_color", SELECTED_TEXT)
	# Not `item_clicked`: it fires on PRESS, so dragging to scroll the roster
	# silently added or dropped whichever Anima the thumb started on. The helper
	# only reports a pick on release, and repaints from `_order` after a drag so
	# the highlight ItemList painted on press does not linger.
	UiJuice.install_item_list_touch_scroll(self, _toggle_index, _apply_chosen)


func set_chosen_order(indices: Array[int]) -> void:
	_order.clear()
	for index in indices:
		if _order.size() >= TEAM_SIZE:
			break
		if index < 0 or index >= item_count or is_item_disabled(index):
			continue
		if index in _order:
			continue
		_order.append(index)
	_apply_chosen()


func get_chosen_indices_ordered() -> Array[int]:
	var result: Array[int] = []
	for index in _order:
		if index >= 0 and index < item_count and not is_item_disabled(index):
			result.append(index)
	return result


func indices_for_anima_ids(anima_ids: Array[String]) -> Array[int]:
	var result: Array[int] = []
	for anima_id in anima_ids:
		if anima_id.is_empty():
			continue
		for index in item_count:
			if is_item_disabled(index):
				continue
			var value: Variant = get_item_metadata(index)
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = value
			if str(row.get("id", "")) == anima_id:
				result.append(index)
				break
	return result


func _draw() -> void:
	# `get_item_rect()` returns content coordinates and does not move when the
	# list scrolls. Subtracting the scroll keeps slot badges attached to cards.
	var scroll := get_v_scroll_bar().value
	var font := get_theme_font("font")
	var badge_font_size := mini(get_theme_font_size("font_size"), 24)
	for slot in _order.size():
		var index := _order[slot]
		if is_item_disabled(index) or not is_selected(index):
			continue
		var item_rect := get_item_rect(index)
		var center := Vector2(item_rect.end.x - 28.0, item_rect.position.y + 26.0 - scroll)
		draw_circle(center, 18.0, SELECTED_BORDER)
		draw_string(
			font,
			Vector2(center.x - 18.0, center.y + badge_font_size * 0.35),
			str(slot + 1),
			HORIZONTAL_ALIGNMENT_CENTER,
			36.0,
			badge_font_size,
			BADGE_INK
		)


func _toggle_index(index: int) -> void:
	if index < 0 or index >= item_count or is_item_disabled(index):
		_apply_chosen()
		return
	if index in _order:
		_order.erase(index)
	elif _order.size() < TEAM_SIZE:
		_order.append(index)
	_apply_chosen()
	selection_changed.emit()


func _apply_chosen() -> void:
	for order_index in range(_order.size() - 1, -1, -1):
		var index := _order[order_index]
		if index < 0 or index >= item_count or is_item_disabled(index):
			_order.remove_at(order_index)
	for index in item_count:
		var keep := index in _order and not is_item_disabled(index)
		if keep and not is_selected(index):
			select(index, false)
		elif not keep and is_selected(index):
			deselect(index)
	queue_redraw()
