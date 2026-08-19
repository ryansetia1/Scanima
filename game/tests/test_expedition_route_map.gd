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
	var constants := route_script.get_script_constant_map()
	var icons := constants.get("ICONS", {}) as Dictionary
	var mobile_theme := constants.get("MOBILE_THEME") as Theme
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
	(route.node_button("n3") as Button).pressed.emit()
	_check(
		str(route.call("_edge_state", "n1", "n3")) != "preview",
		"preview does not highlight the incoming path behind a selected node"
	)
	_check(
		str(route.call("_edge_state", "n3", "boss")) == "preview",
		"preview still highlights paths forward from the selected node"
	)
	route.set_route(
		_map_fixture(),
		PackedStringArray(["boss"]),
		PackedStringArray(["n1", "n3"])
	)
	await process_frame
	await process_frame
	_check(
		str(route.call("_edge_state", "n1", "n3")) == "past",
		"completed path uses the dim past-edge style instead of a highlight"
	)
	route.visible = false

	var view_scene: PackedScene = load("res://scenes/ui/expedition_view.tscn")
	var view := view_scene.instantiate() as Control
	view.theme = mobile_theme
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
	var map_scroll := view_route.get_parent() as ScrollContainer
	var route_size_before: Vector2 = view_route.size
	var node_position_before: Vector2 = selected_button.position
	var scroll_before: int = map_scroll.scroll_vertical
	_check(
		party_meta.visible and party_meta.text.is_empty(),
		"full-health party reserves an empty preview row without clutter"
	)
	_check(not (view.get_node("%Subtitle") as Label).visible, "active map hides redundant subtitle copy")
	_check(
		selected_button.focus_neighbor_bottom == abandon.get_path(),
		"controller can reach Abandon before previewing a route"
	)
	selected_button.pressed.emit()
	await process_frame
	await process_frame
	_check(str(entered["id"]).is_empty(), "node preview does not commit server entry")
	_check(
		view_route.size.is_equal_approx(route_size_before)
		and selected_button.position.is_equal_approx(node_position_before)
		and map_scroll.scroll_vertical == scroll_before,
		"selecting a node keeps route geometry and scroll fixed"
	)
	_check(
		selected_button.get_theme_color("icon_normal_color")
		== mobile_theme.get_color("font_color", "PrimaryButton"),
		"selected icon uses canonical dark on-primary contrast"
	)
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
	var advanced := _run_fixture()
	advanced["available_node_ids"] = ["boss"]
	advanced["visited_node_ids"] = ["n1", "n3"]
	advanced["nodes_completed"] = 2
	view.set_run(advanced)
	await process_frame
	await process_frame
	await _save_screenshot_if_requested()

	var shop_run := _run_fixture()
	shop_run["current_node_id"] = "shop-1"
	shop_run["pending_node"] = {
		"id": "shop-1",
		"kind": "shop",
		"next": ["boss"],
		"options": [{
			"id": "buy-token",
			"cost_supplies": 2,
			"effect": {"type": "supplies", "value": 1},
		}],
	}
	var chosen := {"id": "", "slot": -2}
	view.choice_requested.connect(func(option_id: String, target_slot: int) -> void:
		chosen["id"] = option_id
		chosen["slot"] = target_slot
	)
	view.set_run(shop_run)
	await process_frame
	await process_frame
	var choice_buttons := view.get_node("%ExpeditionChoiceButtons") as VBoxContainer
	var skip_button := choice_buttons.get_child(choice_buttons.get_child_count() - 1) as Button
	_check(skip_button.text == tr("EXPEDITION_SKIP_SHOP"), "Trail Shop exposes a localized skip action")
	_check(skip_button.custom_minimum_size.y >= 96.0, "Skip Shop has a touch-safe target")
	await _save_screenshot_if_requested("--shop-screenshot=")
	view.set_busy(true)
	_check(skip_button.disabled, "busy Trail Shop locks Skip Shop")
	view.set_busy(false)
	skip_button.pressed.emit()
	_check(
		str(chosen["id"]) == "shop-skip" and int(chosen["slot"]) == -1,
		"Skip Shop emits the reserved no-purchase choice"
	)

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

	_check_turn_prediction()
	_check_instant_flow()

	view.free()
	route.free()
	print("test_expedition_route_map: %s checks passed" % _checks)
	quit()


## Jalur local-first Expedition: turn dianimasikan dari simulasi lokal, lalu hasil
## server dibandingkan lewat ringkasan yang sama. Rumus combat-nya sendiri sudah
## dijaga test_battle_sim_parity.
func _check_turn_prediction() -> void:
	var member := {
		"element": "spark",
		"level": 5,
		"base_stats": {"hp": 60, "atk": 40, "def": 30, "spd": 35, "special": 38},
	}
	# Dimuat saat runtime: menyebut ExpeditionController langsung membuat skrip ini
	# ikut dikompilasi sebelum autoload GameState terdaftar sebagai global.
	var controller_script: GDScript = load("res://scripts/expedition_controller.gd")
	var controller: Node = controller_script.new()
	var encounter := {
		"id": "predict-encounter",
		"turn_number": 1,
		"status": "active",
		"state": TeamSim.create_team_state(
			[member, member], [member, member], "predict-expedition-seed"
		)["state"],
	}
	controller.set("_encounter", encounter)
	var predicted: Dictionary = controller.call(
		"_predict_turn", {"expected_turn": 1, "action": "guard", "idempotency_key": "key-a"}
	)
	_check(
		not predicted.is_empty() and int(predicted["encounter"]["turn_number"]) == 2,
		"Expedition animates a plain action from the local simulation"
	)
	_check(
		(controller.call("_predict_turn", {
			"expected_turn": 7, "action": "guard", "idempotency_key": "key-a",
		}) as Dictionary).is_empty(),
		"a stale Expedition turn falls back to the server instead of animating a guess"
	)
	_check(
		(controller.call("_predict_turn", {
			"expected_turn": 1, "action": "item", "item_id": "revive-kit",
			"idempotency_key": "key-b",
		}) as Dictionary).is_empty(),
		"Expedition items wait for the server because the controller holds no Shop catalog"
	)

	var server_encounter: Dictionary = predicted["encounter"].duplicate(true)
	_check(
		controller_script._turn_outcome_matches(
			predicted, server_encounter, predicted["events"]
		),
		"an identical server turn reuses the animation already played"
	)
	server_encounter["state"]["turn"] = 9
	_check(
		not controller_script._turn_outcome_matches(
			predicted, server_encounter, predicted["events"]
		),
		"a divergent server turn replays the authoritative event log"
	)

	var switch_request := {
		"expected_turn": 1, "action": "switch", "switch_to_slot": 1,
		"idempotency_key": "key-c",
	}
	_check(
		(controller.call("_predict_turn", switch_request) as Dictionary).is_empty(),
		"a Switch whose incoming sheet is missing still waits for the server"
	)
	controller.set("_art_cache", {"party-a": {"ok": true}, "party-b": {"ok": true}})
	controller.set("_encounter", {
		"id": "predict-switch",
		"turn_number": 1,
		"status": "active",
		"state": TeamSim.create_team_state(
			[
				{"anima_id": "party-a"}.merged(member),
				{"anima_id": "party-b"}.merged(member),
			],
			[member, member],
			"predict-switch-seed"
		)["state"],
	})
	var switched: Dictionary = controller.call("_predict_turn", switch_request)
	_check(
		not switched.is_empty()
		and int(switched["encounter"]["state"]["player"]["active_slot"]) == 1,
		"a Switch into a cached sheet animates without waiting for the server"
	)

	var finisher := {"expected_turn": 1, "action": "strike", "idempotency_key": "key-d"}
	var last_hit: Dictionary = {
		"id": "predict-finisher",
		"turn_number": 1,
		"status": "active",
		"state": TeamSim.create_team_state([member], [member], "predict-finisher-seed")["state"],
	}
	last_hit["state"]["opponent"]["roster"][0]["hp"] = 1
	controller.set("_encounter", last_hit)
	_check(
		not (controller.call("_predict_turn", finisher) as Dictionary).is_empty(),
		"a regular encounter still animates the turn that wins it"
	)
	last_hit["kind"] = "boss"
	controller.set("_encounter", last_hit)
	_check(
		(controller.call("_predict_turn", finisher) as Dictionary).is_empty(),
		"the turn that finishes a Boss waits for the reward that carries the Trophy"
	)
	controller.free()


## Setiap langkah di dalam run harus terasa instan: hanya operasi yang memang
## menggantikan seluruh layar boleh memakai panel loading, dan art encounter
## berikutnya diunduh dari payload run selama pemain membaca peta. Preload yang
## memilih zona atau chapter yang salah tidak terlihat di layar — ia cuma
## mengembalikan loading yang seharusnya sudah hilang.
func _check_instant_flow() -> void:
	var controller_script: GDScript = load("res://scripts/expedition_controller.gd")
	var context_loading := controller_script.get_script_constant_map().get(
		"CONTEXT_LOADING", {}
	) as Dictionary
	for operation: String in ["enter_node", "start_zone", "checkpoint_choice", "choose", "refresh_shop"]:
		_check(
			not context_loading.has(operation),
			"%s keeps the map or choice panel instead of a loading screen" % operation
		)
	_check(
		context_loading.has("start_run") and context_loading.has("abandon"),
		"operations that replace the whole screen still announce themselves"
	)
	var source := FileAccess.get_file_as_string("res://scripts/expedition_controller.gd")
	_check(
		source.find("GameState.has_sprite_for_anima(anima_id, stage)") >= 0,
		"team members reuse the cached sheet on disk instead of downloading it again"
	)

	var controller: Node = controller_script.new()
	controller.set("_chapter_manifest", _manifest_fixture())
	controller.set("_chapter_manifest_version", "route-test-version")
	controller.set("_run", _run_fixture())
	var zone_two: Array = controller.call("_zone_opponent_snapshots")
	_check(
		zone_two.size() == 1 and str(zone_two[0].get("anima_id", "")) == "mid-a",
		"the preload only fetches the opponents the running zone can spawn"
	)
	var boss_run := _run_fixture()
	boss_run["zone"] = 3
	controller.set("_run", boss_run)
	var zone_three: Array = controller.call("_zone_opponent_snapshots")
	var ids := PackedStringArray()
	for value in zone_three:
		ids.append(str((value as Dictionary).get("anima_id", "")))
	_check(
		ids.has("late-a") and ids.has("boss-a"),
		"the final zone also preloads the Boss roster"
	)
	controller.set("_chapter_manifest_version", "another-chapter")
	_check(
		(controller.call("_zone_opponent_snapshots") as Array).is_empty(),
		"a manifest from another chapter never preloads the wrong art"
	)
	controller.free()


func _manifest_fixture() -> Dictionary:
	return {
		"boss": {"opponent_id": "group-boss"},
		"opponents": [
			{"id": "group-early", "roster": [{"anima_id": "early-a"}]},
			{"id": "group-mid", "roster": [{"anima_id": "mid-a"}]},
			{"id": "group-late", "roster": [{"anima_id": "late-a"}]},
			{"id": "group-boss", "roster": [{"anima_id": "boss-a"}]},
		],
		"zones": [
			{"id": "zone-1", "node_pools": {"battle": [{"opponent_id": "group-early"}]}},
			{"id": "zone-2", "node_pools": {"battle": [{"opponent_id": "group-mid"}]}},
			{"id": "zone-3", "node_pools": {"battle": [{"opponent_id": "group-late"}]}},
		],
	}


func _save_screenshot_if_requested(prefix: String = "--screenshot=") -> void:
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
