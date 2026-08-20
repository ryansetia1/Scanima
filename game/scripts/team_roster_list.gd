class_name TeamRosterList
extends ItemList

## Touch-first multi-pick. Godot's own selection replaces the whole set on a tap
## without Ctrl, so `_chosen` is the authority and its `selection_changed` is the
## only signal callers may count from. Reading `multi_selected` instead reports
## Godot's pre-correction state and desyncs the counter from the checkmarks.

signal selection_changed

const SELECTED_BG := Color(0.055, 0.105, 0.2, 0.96)
const SELECTED_BORDER := Color(0.42, 0.9, 0.82, 1.0)
const SELECTED_TEXT := Color(0.9, 0.96, 1.0, 1.0)
const CHECK_INK := Color(0.025, 0.065, 0.13, 1.0)
const TEAM_SIZE := 4

var _chosen: Dictionary = {}


func _ready() -> void:
	select_mode = SELECT_MULTI
	allow_reselect = true
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
	item_clicked.connect(_on_item_clicked)


func sync_chosen() -> void:
	_chosen.clear()
	for index in get_selected_items():
		_chosen[index] = true
	_apply_chosen()


func _draw() -> void:
	# `get_item_rect()` mengembalikan koordinat konten dan terukur TIDAK ikut
	# bergeser saat list di-scroll, jadi offsetnya dikurangi sendiri; tanpa itu
	# checklist menempel di layar sementara kartunya jalan.
	var scroll := get_v_scroll_bar().value
	for index in item_count:
		if not is_selected(index):
			continue
		var item_rect := get_item_rect(index)
		var center := Vector2(item_rect.end.x - 28.0, item_rect.position.y + 26.0 - scroll)
		draw_circle(center, 18.0, SELECTED_BORDER)
		draw_polyline(
			PackedVector2Array([
				center + Vector2(-8.0, 0.0),
				center + Vector2(-2.0, 6.0),
				center + Vector2(9.0, -7.0),
			]),
			CHECK_INK,
			4.0,
			true
		)


func _on_item_clicked(index: int, _at: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT or is_item_disabled(index):
		_apply_chosen()
		return
	if _chosen.has(index):
		_chosen.erase(index)
	elif _chosen.size() < TEAM_SIZE:
		_chosen[index] = true
	_apply_chosen()
	selection_changed.emit()


func _apply_chosen() -> void:
	for index in item_count:
		var keep := _chosen.has(index) and not is_item_disabled(index)
		if keep and not is_selected(index):
			select(index, false)
		elif not keep and is_selected(index):
			deselect(index)
	queue_redraw()
