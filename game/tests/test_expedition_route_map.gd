extends SceneTree

var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error("FAIL: %s" % message)
		quit(1)


func _run() -> void:
	await process_frame
	var route_script: GDScript = load("res://scripts/expedition_route_map.gd")
	var icons := route_script.get_script_constant_map().get("ICONS", {}) as Dictionary
	_check(icons.get("battle") != icons.get("elite"), "Elite and Battle use distinct icons")
	var route := route_script.new() as Control
	root.add_child(route)
	route.size = Vector2(720, 700)
	route.set_route(_map_fixture(), PackedStringArray(["n1", "n2"]), PackedStringArray())
	await process_frame
	await process_frame

	_check(route.node_count() == 5, "route renders every graph node")
	_check(route.edge_count() == 6, "route renders the complete graph topology")
	_check(route.node_state("n1") == "reachable", "entry node is reachable")
	_check(route.node_state("n3") == "locked", "future node remains locked")
	route.set_busy(true)
	_check((route.node_button("n1") as Button).disabled, "busy overlay locks route previews")
	route.set_busy(false)
	_check(not (route.node_button("n1") as Button).disabled, "route unlocks after busy overlay")
	for node_id: String in ["n1", "n2", "n3", "n4", "boss"]:
		var button := route.node_button(node_id) as Button
		_check(button != null, "%s button exists" % node_id)
		_check(button.custom_minimum_size.y >= 96.0, "%s touch target is at least 96 px" % node_id)
		_check(button.icon != null, "%s has a node icon" % node_id)
		_check(button.expand_icon, "%s expands its icon for mobile readability" % node_id)
		_check(not button.text.contains("\n"), "%s omits redundant route-state text" % node_id)
		_check(button.tooltip_text == button.text, "%s tooltip only names its node kind" % node_id)

	var previewed := {"id": ""}
	route.node_previewed.connect(func(node: Dictionary) -> void:
		previewed["id"] = str(node.get("id", ""))
	)
	_check(
		(route.node_button("n1") as Button).get_signal_connection_list("pressed").size() == 1,
		"route button owns one preview callback"
	)
	(route.node_button("n1") as Button).pressed.emit()
	_check(str(previewed["id"]) == "n1", "tap previews a reachable node")
	_check(route.selected_node_id() == "n1", "selected route is retained for confirmation")
	_check(
		not (route.node_button("n1") as Button).focus_neighbor_right.is_empty(),
		"reachable row has controller focus navigation"
	)
	route.set_route(
		_map_fixture(),
		PackedStringArray(["n3", "n4"]),
		PackedStringArray(["n1"])
	)
	await process_frame
	await process_frame
	_check(route.node_state("n1") == "visited", "cleared node is marked visited")
	_check((route.node_button("n1") as Button).disabled, "visited node cannot be entered again")
	_check(route.node_state("n3") == "reachable", "server-authorized next node becomes reachable")
	route.visible = false

	var view_scene: PackedScene = load("res://scenes/ui/expedition_view.tscn")
	var view := view_scene.instantiate() as Control
	root.add_child(view)
	view.visible = true
	var entered := {"id": ""}
	view.enter_node_requested.connect(func(node_id: String) -> void:
		entered["id"] = node_id
	)
	view.set_run(_run_fixture())
	await process_frame
	await process_frame
	var view_route := view.get_node("%ExpeditionRouteMap")
	_check(
		view_route.size.y >= (view_route.get_parent() as Control).size.y,
		"route canvas fills the scroll viewport (%s/%s)" % [
			view_route.size.y,
			(view_route.get_parent() as Control).size.y,
		]
	)
	_check(
		(view_route.node_button("n1") as Button).position.y > view_route.size.y * 0.65,
		"entry row uses the lower route canvas"
	)
	var selected_button := view_route.node_button("n1") as Button
	var map_primary := view.get_node("%ExpeditionMapPrimary") as Button
	var abandon := view.get_node("%ExpeditionAbandon") as Button
	var party_meta := view.get_node("%ExpeditionPartyMeta") as Label
	_check(not party_meta.visible, "full-health party details stay hidden on the route map")
	_check(not (view.get_node("%Subtitle") as Label).visible, "active map hides redundant subtitle copy")
	_check(
		selected_button.focus_neighbor_bottom == abandon.get_path(),
		"controller can reach Abandon before previewing a route"
	)
	selected_button.pressed.emit()
	_check(str(entered["id"]).is_empty(), "node preview does not commit server entry")
	_check(
		selected_button.focus_neighbor_bottom == map_primary.get_path(),
		"controller can move from the previewed node to Enter Node"
	)
	_check(
		map_primary.focus_neighbor_top == selected_button.get_path(),
		"controller can return from Enter Node to the previewed node"
	)
	_check(
		map_primary.focus_neighbor_bottom == abandon.get_path()
		and abandon.focus_neighbor_top == map_primary.get_path(),
		"controller can move between Enter Node and Abandon"
	)
	_check(
		party_meta.visible
		and party_meta.text.contains("Battle")
		and not party_meta.text.contains("A 40/40")
		and not party_meta.text.contains("Enter Node"),
		"route preview shows node detail without party or instruction clutter"
	)
	view_route.size.y += 1.0
	await process_frame
	await process_frame
	_check(
		selected_button.focus_neighbor_bottom == map_primary.get_path(),
		"resize keeps the preview-to-Enter Node focus path"
	)
	_check(
		root.gui_get_focus_owner() == selected_button,
		"resize does not steal focus from the previewed node"
	)
	map_primary.pressed.emit()
	_check(str(entered["id"]) == "n1", "Enter Node explicitly commits the previewed node")
	var map_meta := view.get_node("%ExpeditionMapMeta") as Label
	_check(
		map_meta.text.contains("10/60")
		and not map_meta.text.contains("Expedition Bits")
		and not map_meta.text.contains("today"),
		"map displays authoritative Bits in compact copy"
	)
	_check(
		map_meta.autowrap_mode != TextServer.AUTOWRAP_OFF,
		"long Expedition Bits status wraps on narrow screens"
	)
	await _save_screenshot_if_requested()

	var legacy := _run_fixture()
	legacy.erase("daily_bits")
	legacy.erase("visited_node_ids")
	view.set_run(legacy)
	await process_frame
	_check(view_route.node_count() == 5, "legacy payload without reward fields still renders")

	var damaged := _run_fixture()
	var damaged_party := damaged.get("party_state") as Array
	var damaged_member := damaged_party[0] as Dictionary
	damaged_member["hp"] = 20
	view.set_run(damaged)
	await process_frame
	_check(
		party_meta.visible
		and party_meta.text.contains("hurt")
		and not party_meta.text.contains("/"),
		"damaged party uses one contextual health summary instead of four readouts"
	)

	view.free()
	route.free()
	print("test_expedition_route_map: %s checks passed" % _checks)
	quit()


func _save_screenshot_if_requested() -> void:
	var prefix := "--screenshot="
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with(prefix):
			continue
		await process_frame
		await process_frame
		var path := argument.trim_prefix(prefix)
		var error := root.get_texture().get_image().save_png(path)
		_check(error == OK, "route screenshot is saved")
		print("route screenshot: %s" % path)


func _run_fixture() -> Dictionary:
	return {
		"id": "route-test-run",
		"chapter_version_id": "route-test-version",
		"team_id": "route-test-team",
		"status": "active",
		"zone": 2,
		"zone_attempt": 1,
		"version": 4,
		"zone_map": _map_fixture(),
		"available_node_ids": ["n1", "n2"],
		"visited_node_ids": [],
		"nodes_completed": 0,
		"supplies": 4,
		"daily_bits": {
			"bits_earned": 10,
			"bits_limit": 60,
			"bits_remaining": 50,
		},
		"party_state": [
			{"name": "A", "hp": 40, "max_hp": 40},
			{"name": "B", "hp": 42, "max_hp": 42},
			{"name": "C", "hp": 44, "max_hp": 44},
			{"name": "D", "hp": 46, "max_hp": 46},
		],
	}


func _map_fixture() -> Dictionary:
	return {
		"zone": 2,
		"entry": ["n1", "n2"],
		"nodes": [
			{"id": "n1", "depth": 1, "kind": "battle", "next": ["n3", "n4"]},
			{"id": "n2", "depth": 1, "kind": "mystery", "next": ["n3", "n4"]},
			{"id": "n3", "depth": 2, "kind": "cache", "next": ["boss"]},
			{"id": "n4", "depth": 2, "kind": "recovery", "next": ["boss"]},
			{"id": "boss", "depth": 3, "kind": "boss", "next": []},
		],
	}
