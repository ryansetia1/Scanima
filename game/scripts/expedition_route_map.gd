class_name ExpeditionRouteMap
extends Control

signal node_previewed(node: Dictionary)

const NODE_SIZE := Vector2(224.0, 96.0)
const BOSS_NODE_SIZE := Vector2(272.0, 96.0)
const ROW_GAP := 34.0
const MAP_PADDING := Vector2(28.0, 24.0)
const EDGE_WIDTH := 5.0
const EDGE_FUTURE := Color(0.38, 0.48, 0.68, 0.42)
const EDGE_LOCKED := Color(0.25, 0.3, 0.43, 0.2)
const EDGE_PREVIEW := Color(0.278, 0.902, 1.0, 0.95)
const BACKGROUND_TINT := Color(0.008, 0.015, 0.035, 0.24)
const ROUTE_BACKGROUND: Texture2D = preload(
	"res://assets/backgrounds/expedition_sugarworks_top_view_background.png"
)
const MOBILE_THEME := preload("res://themes/mobile_theme.tres")
const SELECTED_ICON_COLORS := {
	"icon_normal_color": "font_color",
	"icon_hover_color": "font_hover_color",
	"icon_pressed_color": "font_pressed_color",
	"icon_focus_color": "font_focus_color",
	"icon_disabled_color": "font_disabled_color",
}
const ICONS := {
	"battle": preload("res://assets/icons/sword.svg"),
	"elite": preload("res://assets/icons/elite-sword.svg"),
	"recovery": preload("res://assets/icons/heart-pulse.svg"),
	"cache": preload("res://assets/icons/treasure-chest.svg"),
	"shop": preload("res://assets/icons/shopping-bag.svg"),
	"mystery": preload("res://assets/icons/help-circle.svg"),
	"boss": preload("res://assets/icons/swords.svg"),
}

var _nodes: Array[Dictionary] = []
var _node_by_id: Dictionary = {}
var _buttons: Dictionary = {}
var _available := PackedStringArray()
var _visited := PackedStringArray()
var _selected_id := ""
var _descendants := PackedStringArray()
var _max_depth := 1
var _busy := false
var _focus_initialized := false


func _ready() -> void:
	resized.connect(_layout_nodes)
	var scroll := get_parent() as ScrollContainer
	if scroll != null:
		scroll.resized.connect(_layout_nodes)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_route(
	map_data: Dictionary,
	available_ids: PackedStringArray,
	visited_ids: PackedStringArray
) -> void:
	_clear_nodes()
	_available = available_ids.duplicate()
	_visited = visited_ids.duplicate()
	_selected_id = ""
	_descendants = PackedStringArray()
	_focus_initialized = false
	for value: Variant in _as_array(map_data.get("nodes")):
		var node := _as_dict(value)
		var node_id := str(node.get("id", ""))
		if node_id.is_empty():
			continue
		_nodes.append(node)
		_node_by_id[node_id] = node
		_max_depth = maxi(_max_depth, int(node.get("depth", 1)))
	_nodes.sort_custom(_sort_nodes)
	custom_minimum_size.y = (
		MAP_PADDING.y * 2.0
		+ NODE_SIZE.y * float(_max_depth)
		+ ROW_GAP * float(maxi(0, _max_depth - 1))
	)
	for node: Dictionary in _nodes:
		_add_node_button(node)
	call_deferred("_layout_nodes")


func clear_preview() -> void:
	_selected_id = ""
	_descendants = PackedStringArray()
	_refresh_button_states()
	queue_redraw()


func set_busy(busy: bool) -> void:
	_busy = busy
	_refresh_button_states()


func selected_node() -> Dictionary:
	return _as_dict(_node_by_id.get(_selected_id, {})).duplicate(true)


func selected_node_id() -> String:
	return _selected_id


func node_count() -> int:
	return _nodes.size()


func edge_count() -> int:
	var count := 0
	for node: Dictionary in _nodes:
		count += _string_array(node.get("next")).size()
	return count


func node_state(node_id: String) -> String:
	if node_id == _selected_id:
		return "selected"
	if node_id in _visited:
		return "visited"
	if node_id in _available:
		return "reachable"
	return "locked"


func node_button(node_id: String) -> Button:
	return _buttons.get(node_id) as Button


func _draw() -> void:
	var background_rect := cover_rect(ROUTE_BACKGROUND.get_size(), size)
	if background_rect.has_area():
		draw_texture_rect(ROUTE_BACKGROUND, background_rect, false)
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_TINT)
	for node: Dictionary in _nodes:
		var from_id := str(node.get("id", ""))
		var from_button := node_button(from_id)
		if from_button == null:
			continue
		for to_id: String in _string_array(node.get("next")):
			var to_button := node_button(to_id)
			if to_button == null:
				continue
			_draw_edge(
				from_button.position + from_button.size * 0.5,
				to_button.position + to_button.size * 0.5,
				_edge_state(from_id, to_id)
			)


static func cover_rect(texture_size: Vector2, target_size: Vector2) -> Rect2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2()
	if target_size.x <= 0.0 or target_size.y <= 0.0:
		return Rect2()
	var scale_factor := maxf(
		target_size.x / texture_size.x,
		target_size.y / texture_size.y
	)
	var draw_size := texture_size * scale_factor
	return Rect2((target_size - draw_size) * 0.5, draw_size)


func _draw_edge(from: Vector2, to: Vector2, state: String) -> void:
	match state:
		"past":
			draw_dashed_line(from, to, EDGE_LOCKED, 3.0, 10.0, true, true)
		"preview":
			draw_line(from, to, EDGE_PREVIEW, EDGE_WIDTH, true)
		"future":
			draw_dashed_line(from, to, EDGE_FUTURE, 4.0, 12.0, true, true)
		_:
			draw_dashed_line(from, to, EDGE_LOCKED, 3.0, 10.0, true, true)


func _edge_state(from_id: String, to_id: String) -> String:
	if from_id in _visited and to_id in _visited:
		return "past"
	if (
		not _selected_id.is_empty()
		and from_id in _descendants
		and to_id in _descendants
	):
		return "preview"
	if _selected_id.is_empty() or from_id in _available or to_id in _available:
		return "future"
	return "locked"


func _add_node_button(node: Dictionary) -> void:
	var node_id := str(node.get("id", ""))
	var kind := str(node.get("kind", ""))
	var button := Button.new()
	button.name = "Route_%s" % node_id.replace("-", "_")
	button.custom_minimum_size = BOSS_NODE_SIZE if kind == "boss" else NODE_SIZE
	button.size = button.custom_minimum_size
	button.icon = ICONS.get(kind) as Texture2D
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 40)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta("node_id", node_id)
	button.set_meta("kind", kind)
	button.pressed.connect(_preview.bind(node_id))
	add_child(button)
	_buttons[node_id] = button
	_apply_button_state(button, node)


func _preview(node_id: String) -> void:
	if node_id not in _available or not _node_by_id.has(node_id):
		return
	_selected_id = node_id
	_descendants = _descendant_ids(node_id)
	_refresh_button_states()
	queue_redraw()
	var button := node_button(node_id)
	if button != null:
		button.grab_focus()
	node_previewed.emit(selected_node())


func _refresh_button_states() -> void:
	for node: Dictionary in _nodes:
		var button := node_button(str(node.get("id", "")))
		if button != null:
			_apply_button_state(button, node)


func _apply_button_state(button: Button, node: Dictionary) -> void:
	var node_id := str(node.get("id", ""))
	var state := node_state(node_id)
	button.disabled = _busy or state in ["visited", "locked"]
	button.theme_type_variation = StringName({
		"selected": "PrimaryButton",
		"visited": "NavButton",
		"reachable": "Button",
		"locked": "NavButton",
	}.get(state, "Button"))
	button.text = tr(_kind_key(str(node.get("kind", ""))))
	button.tooltip_text = button.text
	_sync_selected_icon_contrast(button, state == "selected")


func _sync_selected_icon_contrast(button: Button, selected: bool) -> void:
	for icon_color: String in SELECTED_ICON_COLORS:
		button.remove_theme_color_override(icon_color)
		if selected:
			button.add_theme_color_override(
				icon_color,
				MOBILE_THEME.get_color(SELECTED_ICON_COLORS[icon_color], "PrimaryButton")
			)


func _layout_nodes() -> void:
	if _nodes.is_empty() or size.x <= 0.0:
		return
	var scroll := get_parent() as ScrollContainer
	if scroll != null and custom_minimum_size.y < scroll.size.y:
		custom_minimum_size.y = scroll.size.y
	var by_depth: Dictionary = {}
	for node: Dictionary in _nodes:
		var depth := int(node.get("depth", 1))
		if not by_depth.has(depth):
			by_depth[depth] = []
		(by_depth[depth] as Array).append(node)
	var row_stride := NODE_SIZE.y + ROW_GAP
	if _max_depth > 1:
		row_stride = maxf(
			row_stride,
			(size.y - MAP_PADDING.y * 2.0 - NODE_SIZE.y) / float(_max_depth - 1)
		)
	for depth: int in by_depth:
		var row: Array = by_depth[depth]
		row.sort_custom(_sort_nodes)
		for index: int in row.size():
			var node := _as_dict(row[index])
			var button := node_button(str(node.get("id", "")))
			if button == null:
				continue
			var center_x := size.x * 0.5
			if row.size() > 1:
				center_x = size.x * (0.28 if index == 0 else 0.72)
			var row_from_top := _max_depth - depth
			var center_y := (
				MAP_PADDING.y
				+ button.size.y * 0.5
				+ float(row_from_top) * row_stride
			)
			button.position = Vector2(center_x, center_y) - button.size * 0.5
	_wire_focus_neighbors(by_depth)
	queue_redraw()
	call_deferred("_focus_first_available")


func _wire_focus_neighbors(by_depth: Dictionary) -> void:
	for node: Dictionary in _nodes:
		var button := node_button(str(node.get("id", "")))
		if button == null or button.disabled:
			continue
		var depth := int(node.get("depth", 1))
		var up := _closest_enabled(by_depth.get(depth + 1, []), button.position.x)
		var down := _closest_enabled(by_depth.get(depth - 1, []), button.position.x)
		if up != null:
			button.focus_neighbor_top = up.get_path()
		if down != null:
			button.focus_neighbor_bottom = down.get_path()
		var row: Array = by_depth.get(depth, [])
		var peer := _closest_enabled(row, button.position.x, button)
		if peer != null:
			button.focus_neighbor_left = peer.get_path()
			button.focus_neighbor_right = peer.get_path()


func _focus_first_available() -> void:
	if _focus_initialized:
		return
	for node: Dictionary in _nodes:
		var node_id := str(node.get("id", ""))
		if node_id not in _available:
			continue
		var button := node_button(node_id)
		if button == null:
			continue
		var parent := get_parent()
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(button)
		button.grab_focus()
		_focus_initialized = true
		return


func _closest_enabled(values: Array, x: float, excluded: Button = null) -> Button:
	var closest: Button
	var distance := INF
	for value: Variant in values:
		var candidate := node_button(str(_as_dict(value).get("id", "")))
		if candidate == null or candidate == excluded or candidate.disabled:
			continue
		var next_distance := absf(candidate.position.x - x)
		if next_distance < distance:
			closest = candidate
			distance = next_distance
	return closest


func _descendant_ids(node_id: String) -> PackedStringArray:
	var result := PackedStringArray([node_id])
	var pending := PackedStringArray([node_id])
	while not pending.is_empty():
		var current := pending[0]
		pending.remove_at(0)
		var node := _as_dict(_node_by_id.get(current, {}))
		for next_id: String in _string_array(node.get("next")):
			if next_id in result:
				continue
			result.append(next_id)
			pending.append(next_id)
	return result


func _clear_nodes() -> void:
	for button: Variant in _buttons.values():
		if button is Button:
			(button as Button).free()
	_nodes.clear()
	_node_by_id.clear()
	_buttons.clear()
	_max_depth = 1


static func _sort_nodes(left: Dictionary, right: Dictionary) -> bool:
	var left_depth := int(left.get("depth", 0))
	var right_depth := int(right.get("depth", 0))
	return (
		left_depth < right_depth
		or (left_depth == right_depth and str(left.get("id", "")) < str(right.get("id", "")))
	)


static func _kind_key(kind: String) -> String:
	return str({
		"battle": "EXPEDITION_NODE_BATTLE",
		"elite": "EXPEDITION_NODE_ELITE",
		"recovery": "EXPEDITION_NODE_RECOVERY",
		"cache": "EXPEDITION_NODE_CACHE",
		"shop": "EXPEDITION_NODE_SHOP",
		"mystery": "EXPEDITION_NODE_MYSTERY",
		"boss": "EXPEDITION_NODE_BOSS",
	}.get(kind, "EXPEDITION_NODE_UNKNOWN"))


static func _as_dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _as_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


static func _string_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	for item: Variant in _as_array(value):
		result.append(str(item))
	return result
