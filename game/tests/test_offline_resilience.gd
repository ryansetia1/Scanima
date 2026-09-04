extends SceneTree

## Deterministic airplane-mode contract without touching production services:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##       --script res://tests/test_offline_resilience.gd
##
## Port 1 refuses locally, so the transport check needs no internet. The UI
## checks use the real Home, Battle, Shop, and Scan shell code.

const DEAD_ENDPOINT := "http://127.0.0.1:1/"

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	await process_frame
	await _test_mid_game_disconnect()
	await _test_loading_disconnect()
	await _test_save_disconnect()
	_finish()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s (got %s, expected %s)" % [message, str(actual), str(expected)])


func _test_mid_game_disconnect() -> void:
	print("1. internet drops during a Battle turn")
	var backend := get_root().get_node("Backend")
	var result: Dictionary = await backend._send(
		HTTPClient.METHOD_POST,
		DEAD_ENDPOINT,
		PackedStringArray(["content-type: application/json"]),
		PackedByteArray(),
		0.25
	)
	_check(
		not bool(result.get("ok", false)) and bool(result.get("transport", false)),
		"a refused connection is classified as transport failure"
	)
	_check_eq(
		backend.get_script().turn_retries("turn"),
		2,
		"a Battle turn gets two bounded transport retries"
	)

	var packed := load("res://scenes/ui/battle_view.tscn") as PackedScene
	var battle := packed.instantiate()
	get_root().add_child(battle)
	battle.set_session({
		"id": "offline-test",
		"status": "active",
		"turn_number": 1,
		"version": 1,
		"player_snapshot": {"id": "player", "name": "Velumi", "stage": 1},
		"bot_snapshot": {"id": "bot", "name": "Echo Warden", "stage": 1},
		"state": {
			"player": {"hp": 100, "max_hp": 100, "momentum": 3, "spd": 20},
			"bot": {"hp": 100, "max_hp": 100, "momentum": 3, "spd": 20},
		},
	})
	battle.set_error("CONNECTION_LOST")
	var retry := battle.find_child("BattleRetryButton", true, false) as Button
	var title := battle.find_child("BattleResultTitle", true, false) as Label
	_check(
		retry != null and retry.is_visible_in_tree() and retry.text == tr("ACTION_RETRY"),
		"an exhausted Battle retry exposes a custom Retry action"
	)
	_check(
		title != null and title.text == tr("BATTLE_ERROR_TITLE"),
		"an exhausted Battle retry shows an in-game error instead of a blank screen"
	)
	battle.queue_free()
	await process_frame


func _test_loading_disconnect() -> void:
	print("2. internet drops while Home is loading")
	var packed := load("res://scenes/ui/home_view.tscn") as PackedScene
	var home := packed.instantiate()
	get_root().add_child(home)
	home.set_shell_state(&"error")
	var title := home.find_child("AnimaName", true, false) as Label
	var body := home.find_child("AnimaMeta", true, false) as Label
	var retry := home.find_child("HomePrimaryAction", true, false) as Button
	var retried := [false]
	home.retry_requested.connect(func() -> void: retried[0] = true)
	retry.pressed.emit()
	_check(
		title.text == tr("HOME_ERROR_NAME") and body.text == tr("HOME_ERROR_META"),
		"offline boot shows the custom habitat error"
	)
	_check(
		retry.visible and retry.text == tr("ACTION_RETRY") and retried[0],
		"offline boot offers a working Retry action"
	)
	home.queue_free()
	await process_frame


func _test_save_disconnect() -> void:
	print("3. internet drops while a server-authoritative save is pending")
	var packed := load("res://scenes/ui/shop_sheet.tscn") as PackedScene
	var shop := packed.instantiate()
	get_root().add_child(shop)
	shop.set_catalog([{
		"id": "pulse_cell",
		"kind": "item",
		"use_type": "care",
		"name_key": "CATALOG_PULSE_CELL",
		"price": 8,
		"effect": "energy",
		"effect_value": 20,
		"sprite_sheet": "item",
		"sprite_index": 0,
	}], [], 20)
	shop.open_shop("item")
	var retried_item := [""]
	shop.buy_requested.connect(
		func(item: Dictionary) -> void: retried_item[0] = str(item.get("id", ""))
	)
	await process_frame
	_check(
		shop.has_method("set_retry"),
		"a lost purchase response leaves an explicit retry state"
	)
	if shop.has_method("set_retry"):
		shop.call("set_retry", "pulse_cell")
		await process_frame
		var retry: Button = null
		for node in shop.find_children("*", "Button", true, false):
			var button := node as Button
			if button != null and button.text == tr("ACTION_RETRY"):
				retry = button
				break
		_check(
			retry != null and not retry.disabled,
			"the exact pending purchase remains tappable as Retry"
		)
		if retry != null:
			retry.pressed.emit()
		_check_eq(
			retried_item[0],
			"pulse_cell",
			"the purchase Retry emits the original pending item"
		)
	shop.queue_free()

	packed = load("res://scenes/ui/scan_view.tscn") as PackedScene
	var scan := packed.instantiate()
	get_root().add_child(scan)
	scan.set_cores(0)
	scan.set_retry_pending(true)
	var scan_retry := scan.find_child("ScanButton", true, false) as Button
	_check(
		scan_retry.text == tr("ACTION_RETRY")
		and is_equal_approx(scan_retry.self_modulate.a, 1.0),
		"a saved Scan keeps Retry lit even if its Core may already be debited"
	)
	scan.queue_free()

	var flow_source := FileAccess.get_file_as_string("res://scripts/scan_flow.gd")
	var flow_script := load("res://scripts/scan_flow.gd") as GDScript
	_check(
		bool(flow_script.call(
			"care_intent_matches",
			{"anima_id": "a", "action": "feed", "item_id": "food"},
			"a", "feed", "food"
		))
		and not bool(flow_script.call(
			"care_intent_matches",
			{"anima_id": "a", "action": "feed", "item_id": "food"},
			"a", "feed", "other"
		)),
		"Care retry accepts only the exact durable intent"
	)
	var care_start := flow_source.find("func _commit_care(")
	var care_end := flow_source.find("\n\nfunc optimistic_care(", care_start)
	var care_body := (
		flow_source.substr(care_start, care_end - care_start)
		if care_start >= 0 and care_end > care_start
		else ""
	)
	_check(
		care_body.find("care_intent_matches(") >= 0,
		"repeating the same Care action retries its durable intent"
	)

	var buy_start := flow_source.find("func _buy_catalog_item(")
	var buy_end := flow_source.find("\n\nfunc _apply_optimistic_purchase(", buy_start)
	var buy_body := (
		flow_source.substr(buy_start, buy_end - buy_start)
		if buy_start >= 0 and buy_end > buy_start
		else ""
	)
	var pending_at := buy_body.find("GameState.pending_purchase.duplicate(true)")
	var retry_send_at := buy_body.find("await _send_pending_purchase", pending_at)
	var begin_at := buy_body.find("GameState.begin_purchase")
	_check(
		pending_at >= 0 and retry_send_at > pending_at and retry_send_at < begin_at,
		"tapping the pending Shop item resends its existing idempotency key"
	)

	var create_start := flow_source.find("func _handle_create_result(")
	var create_end := flow_source.find("\n\nfunc ", create_start)
	var create_body := (
		flow_source.substr(create_start, create_end - create_start)
		if create_start >= 0 and create_end > create_start
		else ""
	)
	_check(
		bool(flow_script.call(
			"create_result_needs_retry",
			{"ok": false, "code": 0, "transport": true}
		))
		and bool(flow_script.call(
			"create_result_needs_retry",
			{"ok": false, "code": 503}
		))
		and not bool(flow_script.call(
			"create_result_needs_retry",
			{"ok": false, "code": 400}
		))
		and create_body.find("create_result_needs_retry(res)") >= 0
		and create_body.find("set_retry_pending(true)") >= 0,
		"transport/5xx keeps the paid Scan intent while 4xx stays terminal"
	)
	var switch_start := flow_source.find("func _switch_destination(")
	var switch_end := flow_source.find("\n\nfunc ", switch_start)
	var switch_body := flow_source.substr(switch_start, switch_end - switch_start)
	var header_start := flow_source.find("func _refresh_header(")
	var header_end := flow_source.find("\n\nfunc ", header_start)
	var header_body := flow_source.substr(header_start, header_end - header_start)
	_check(
		switch_body.find("not GameState.pending_scan.is_empty()") >= 0
		and header_body.find("not GameState.pending_scan.is_empty()") >= 0,
		"a saved Scan remains available in the bottom navigation"
	)
	await process_frame


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("test_offline_resilience: OK (%d checks)" % _checks)
		quit(0)
		return
	printerr(
		"test_offline_resilience: FAILED %d of %d checks"
		% [_failures.size(), _checks]
	)
	for failure in _failures:
		printerr("  - %s" % failure)
	quit(1)
