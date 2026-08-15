class_name ExpeditionController
extends Node

signal item_picker_requested
signal inventory_refresh_requested
signal authority_refresh_requested
signal announcements_changed(announcements: Dictionary)

const BOSS_SEEKER_SHEET := preload("res://scripts/boss_seeker_sheet.gd")

var _view: ExpeditionView
var _battle_view: BattleView
var _roster: Array = []
var _team: Dictionary = {}
var _chapters: Array = []
var _run: Dictionary = {}
var _encounter: Dictionary = {}
var _art_cache: Dictionary = {}
var _busy := false
var _catalog_available := false


func configure(view: ExpeditionView, battle_view: BattleView) -> void:
	_view = view
	_battle_view = battle_view
	_view.back_requested.connect(close)
	_view.chapter_requested.connect(_load_chapter)
	_view.save_team_requested.connect(_save_team)
	_view.start_run_requested.connect(_start_run)
	_view.start_zone_requested.connect(_start_zone)
	_view.enter_node_requested.connect(_enter_node)
	_view.choice_requested.connect(_choose)
	_view.refresh_shop_requested.connect(_refresh_shop)
	_view.abandon_requested.connect(_abandon)
	_view.action_requested.connect(_request_turn)
	_view.item_picker_requested.connect(item_picker_requested.emit)
	_view.forfeit_requested.connect(_forfeit)
	_view.combat_continue_requested.connect(_continue_after_combat)
	_view.complete_requested.connect(_leave_complete)


func set_roster(roster: Array) -> void:
	_roster = roster.duplicate(true)


func discover() -> void:
	var pending := not GameState.pending_expedition.is_empty()
	_battle_view.set_expedition_pending(pending)
	var res := await Backend.expedition("chapters")
	if res.ok:
		var chapters := _array(GameState.as_dict(res.data).get("chapters"))
		_catalog_available = not chapters.is_empty()
		GameState.set_expedition_available(_catalog_available)
		_battle_view.set_expedition_available(_catalog_available or pending)
		return
	if str(res.error) == "FEATURE_DISABLED":
		_catalog_available = false
		GameState.set_expedition_available(false)
		_battle_view.set_expedition_available(pending)


func open() -> void:
	if _busy:
		return
	_battle_view.show_expedition_mode()
	if not GameState.pending_expedition.is_empty():
		await resume_pending()
	else:
		await _load_hub()


func close() -> void:
	if _busy or _view.has_active_encounter():
		return
	_battle_view.set_expedition_pending(not GameState.pending_expedition.is_empty())
	_battle_view.show_duel_mode()


func handle_back() -> bool:
	return _view.handle_back() if _view != null else false


func has_active_encounter() -> bool:
	return _view != null and _view.has_active_encounter()


func use_item(item_id: String) -> bool:
	if _busy or _encounter.is_empty() or str(_encounter.get("status", "")) != "active":
		return false
	var pending := GameState.begin_expedition_operation("turn", {
		"action": "item",
		"item_id": item_id,
		"switch_to_slot": -1,
	})
	await _submit_pending(pending)
	return true


func resume_pending() -> void:
	if _busy:
		return
	_set_busy(true)
	_view.set_loading("EXPEDITION_RESUMING")
	var pending := GameState.pending_expedition.duplicate(true)
	var payload := {}
	var run_id := str(pending.get("run_id", ""))
	if not run_id.is_empty():
		payload["run_id"] = run_id
	var res := await Backend.expedition("resume", payload)
	if not res.ok:
		if res.error == "EXPEDITION_RUN_NOT_FOUND":
			_set_busy(false)
			await _finish_to_hub()
			return
		_view.set_error(res.error)
		_set_busy(false)
		return
	if res.data == null:
		_set_busy(false)
		await _finish_to_hub()
		return
	var data := GameState.as_dict(res.data)
	_run = GameState.as_dict(data.get("run"))
	_encounter = GameState.as_dict(data.get("encounter"))
	var should_replay := _pending_matches(pending)
	if should_replay:
		_set_busy(false)
		await _submit_pending(pending)
		return
	GameState.confirm_expedition_response(_run, _encounter)
	_battle_view.set_expedition_pending(not GameState.pending_expedition.is_empty())
	await _present()
	_set_busy(false)


func _load_hub() -> void:
	_set_busy(true)
	_view.set_loading()
	var chapters_res := await Backend.expedition("chapters")
	if not chapters_res.ok:
		_view.set_error(chapters_res.error)
		_set_busy(false)
		return
	var team_res := await Backend.expedition("team")
	if not team_res.ok:
		_view.set_error(team_res.error)
		_set_busy(false)
		return
	_chapters = _array(GameState.as_dict(chapters_res.data).get("chapters"))
	_team = GameState.as_dict(GameState.as_dict(team_res.data).get("team"))
	_battle_view.set_expedition_pending(not GameState.pending_expedition.is_empty())
	_view.set_builder(_roster, _team)
	_view.set_catalog(_chapters, _team)
	_set_busy(false)


func _finish_to_hub() -> void:
	GameState.finish_expedition()
	_battle_view.set_expedition_pending(false)
	await discover()
	if _catalog_available:
		await _load_hub()
	else:
		_battle_view.show_duel_mode()


func _load_chapter(version_id: String) -> void:
	if _busy or version_id.is_empty():
		return
	_set_busy(true)
	_view.set_loading("EXPEDITION_LOADING_CHAPTER")
	var res := await Backend.expedition("chapter", {"chapter_version_id": version_id})
	if res.ok:
		var data := GameState.as_dict(res.data)
		_view.set_chapter_detail(data)
		announcements_changed.emit(GameState.as_dict(data.get("announcements")))
	else:
		_view.set_error(res.error)
	_set_busy(false)


func _save_team(anima_ids: Array[String]) -> void:
	if _busy or anima_ids.size() != 4:
		return
	_set_busy(true)
	_view.set_loading("EXPEDITION_SAVING_TEAM")
	var res := await Backend.expedition("save_team", {"anima_ids": anima_ids})
	if res.ok:
		_team = GameState.as_dict(GameState.as_dict(res.data).get("team"))
		_view.set_team(_team)
		_view.set_catalog(_chapters, _team)
	else:
		_view.set_error(res.error)
	_set_busy(false)


func _start_run(version_id: String, team_id: String) -> void:
	if _busy:
		return
	GameState.finish_expedition()
	GameState.pending_expedition = {
		"run_id": "",
		"run_version": 1,
		"encounter_id": "",
		"expected_turn": 1,
		"expected_version": 1,
		"operation": "",
		"idempotency_key": "",
	}
	var pending := GameState.begin_expedition_operation("start_run", {
		"chapter_version_id": version_id,
		"team_id": team_id,
	})
	await _submit_pending(pending)


func _start_zone(_run_id: String, team_id: String) -> void:
	if _busy or _run.is_empty():
		return
	var pending := GameState.begin_expedition_operation("start_zone", {
		"team_id": team_id,
	})
	await _submit_pending(pending)


func _enter_node(node_id: String) -> void:
	if _busy or node_id.is_empty():
		return
	var pending := GameState.begin_expedition_operation("enter_node", {"node_id": node_id})
	await _submit_pending(pending)


func _choose(option_id: String, target_slot: int) -> void:
	if _busy or option_id.is_empty():
		return
	var pending := GameState.begin_expedition_operation("choose", {
		"option_id": option_id,
		"target_slot": target_slot,
	})
	await _submit_pending(pending)


func _refresh_shop() -> void:
	if _busy:
		return
	await _submit_pending(GameState.begin_expedition_operation("refresh_shop"))


func _abandon() -> void:
	if _busy:
		return
	await _submit_pending(GameState.begin_expedition_operation("abandon"))


func _request_turn(action: String, switch_to_slot: int) -> void:
	if _busy or _encounter.is_empty() or str(_encounter.get("status", "")) != "active":
		return
	var pending := GameState.begin_expedition_operation("turn", {
		"action": action,
		"item_id": "",
		"switch_to_slot": switch_to_slot,
	})
	await _submit_pending(pending)


func _forfeit() -> void:
	if _busy or _encounter.is_empty():
		return
	_set_busy(true)
	var res := await Backend.expedition("forfeit", {
		"encounter_id": str(_encounter.get("id", "")),
	})
	if res.ok:
		var data := GameState.as_dict(res.data)
		_run = GameState.as_dict(data.get("run"))
		_encounter = GameState.as_dict(data.get("encounter"))
		GameState.confirm_expedition_response(_run, _encounter)
		await _present()
	else:
		_view.set_error(res.error)
	_set_busy(false)


func _continue_after_combat() -> void:
	if str(_run.get("status", "")) in ["complete", "abandoned"]:
		if str(_run.get("status", "")) == "complete":
			GameState.finish_expedition()
			_battle_view.set_expedition_pending(false)
			await discover()
			_view.set_run(_run)
		else:
			await _finish_to_hub()
		return
	_encounter = {}
	GameState.remember_expedition(_run)
	_view.set_run(_run)


func _leave_complete() -> void:
	if _catalog_available:
		await _load_hub()
	else:
		close()


func _submit_pending(pending: Dictionary) -> void:
	if pending.is_empty():
		return
	var operation := str(pending.get("operation", ""))
	if operation == "turn":
		_view.begin_combat_action(str(pending.get("action", "")))
	else:
		_view.set_loading(_loading_key(operation))
	_set_busy(true)
	var res := await Backend.expedition(operation, operation_payload(pending))
	if not res.ok:
		if should_resume_error(res.error):
			_set_busy(false)
			await resume_pending()
			return
		_view.set_error(res.error)
		_set_busy(false)
		return
	var data := GameState.as_dict(res.data)
	var next_run := GameState.as_dict(data.get("run"))
	var next_encounter := GameState.as_dict(data.get("encounter"))
	if next_run.is_empty():
		_view.set_error("EXPEDITION_RUN_NOT_FOUND")
		_set_busy(false)
		return
	if operation == "turn":
		next_encounter["last_reward"] = GameState.as_dict(data.get("reward"))
		var events := _array(data.get("events"))
		var art := _art_cache.duplicate()
		for value in events:
			if str(GameState.as_dict(value).get("type", "")) == "switch":
				art = await _prepare_active_art(next_encounter, false)
				break
		art = await _attach_seeker_art(art)
		await _view.play_combat_events(events, next_encounter, art)
	_run = next_run
	_encounter = next_encounter
	GameState.confirm_expedition_response(_run, _encounter)
	if operation != "turn":
		await _present()
	if operation == "start_run" and str(_run.get("status", "")) == "checkpoint":
		_set_busy(false)
		await _start_zone(str(_run.get("id", "")), str(pending.get("team_id", "")))
		return
	if operation == "abandon":
		_set_busy(false)
		await _finish_to_hub()
		return
	if operation == "turn" and str(pending.get("action", "")) == "item":
		inventory_refresh_requested.emit()
	if operation == "turn" and not GameState.as_dict(data.get("reward")).is_empty():
		authority_refresh_requested.emit()
	_battle_view.set_expedition_pending(not GameState.pending_expedition.is_empty())
	_set_busy(false)


func _present() -> void:
	if _run.is_empty():
		await _load_hub()
		return
	var art: Dictionary = {}
	if not _encounter.is_empty():
		art = await _prepare_active_art(_encounter)
		if art.is_empty():
			_view.set_error("TEAM_ART_NOT_READY")
			return
	art = await _attach_seeker_art(art)
	_view.set_run(_run, _encounter, art)


func _prepare_active_art(encounter: Dictionary, include_background: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var state := GameState.as_dict(encounter.get("state"))
	for side in ["player", "opponent"]:
		var party := GameState.as_dict(state.get(side))
		var roster := _array(party.get("roster"))
		var active_slot := int(party.get("active_slot", 0))
		if active_slot < 0 or active_slot >= roster.size():
			return {}
		var snapshots := _array(
			encounter.get("player_snapshot" if side == "player" else "opponent_snapshot")
		)
		for slot in roster.size():
			var member := GameState.as_dict(roster[slot])
			var anima_id := str(member.get("anima_id", ""))
			if anima_id.is_empty():
				if slot == active_slot:
					return {}
				continue
			if _art_cache.has(anima_id):
				result[anima_id] = _art_cache[anima_id]
				continue
			var snapshot := _snapshot(snapshots, anima_id)
			var loaded := await _load_art(snapshot)
			if not bool(loaded.get("ok", false)):
				if slot == active_slot:
					return {}
				continue
			_art_cache[anima_id] = loaded
			result[anima_id] = loaded
	if include_background:
		var background := await _load_arena_background(encounter)
		if background != null:
			result["arena_background"] = background
	elif _art_cache.get("arena_background") is Texture2D:
		result["arena_background"] = _art_cache["arena_background"]
	return result


func _attach_seeker_art(art: Dictionary) -> Dictionary:
	var seeker := GameState.as_dict(_encounter.get("boss_seeker"))
	if seeker.is_empty():
		seeker = GameState.as_dict(_run.get("boss_seeker"))
	if seeker.is_empty():
		return art
	if _art_cache.has("boss_seeker"):
		art["boss_seeker"] = _art_cache["boss_seeker"]
		return art
	var loaded := await _load_seeker_art(seeker)
	if bool(loaded.get("ok", false)):
		_art_cache["boss_seeker"] = loaded
		art["boss_seeker"] = loaded
	return art


func _load_seeker_art(seeker: Dictionary) -> Dictionary:
	var url := str(seeker.get("sheet_url", "")).strip_edges()
	if url.is_empty():
		var base := str(_run.get("asset_base_url", "")).rstrip("/")
		var path := str(seeker.get("sheet_path", "")).strip_edges()
		if not base.is_empty() and not path.is_empty() and not path.contains(".."):
			url = "%s/%s" % [base, path]
	var manifest := GameState.as_dict(seeker.get("manifest"))
	if url.is_empty() or manifest.is_empty():
		return {"ok": false}
	var download := await Backend.download_url(url)
	if not download.ok:
		return {"ok": false}
	var image := Image.new()
	if image.load_png_from_buffer(download.bytes) != OK:
		return {"ok": false}
	return BOSS_SEEKER_SHEET.build(ImageTexture.create_from_image(image), manifest)


func _load_arena_background(encounter: Dictionary) -> Texture2D:
	var url := str(_run.get("arena_background_url", encounter.get("arena_background_url", "")))
	if url.is_empty():
		return null
	if _art_cache.get(url) is Texture2D:
		return _art_cache[url]
	var download := await Backend.download_url(url)
	if not download.ok:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(download.bytes) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_art_cache[url] = texture
	return texture


func _load_art(snapshot: Dictionary) -> Dictionary:
	if str(snapshot.get("system_asset", "")) == "placeholder":
		var placeholder := PlaceholderSheet.build()
		return AnimaLoader.build(
			ImageTexture.create_from_image(placeholder["image"]),
			placeholder["manifest"]
		)
	var sheet_url := str(snapshot.get("sheet_url", ""))
	var manifest := GameState.as_dict(snapshot.get("manifest"))
	if sheet_url.is_empty() or manifest.is_empty():
		return {"ok": false}
	var download := await Backend.download_url(sheet_url)
	if not download.ok:
		return {"ok": false}
	var image := Image.new()
	if image.load_png_from_buffer(download.bytes) != OK:
		return {"ok": false}
	return AnimaLoader.build(ImageTexture.create_from_image(image), manifest)


func _pending_matches(pending: Dictionary) -> bool:
	return pending_matches(pending, _run, _encounter)


static func pending_matches(
	pending: Dictionary,
	run: Dictionary,
	encounter: Dictionary
) -> bool:
	var operation := str(pending.get("operation", ""))
	if operation.is_empty():
		return false
	if operation == "start_run":
		return run.is_empty()
	if operation == "turn":
		return (
			str(encounter.get("status", "")) == "active"
			and int(encounter.get("turn_number", 0)) == int(pending.get("expected_turn", -1))
			and int(encounter.get("version", 0)) == int(pending.get("expected_version", -1))
		)
	return int(run.get("version", 0)) == int(pending.get("run_version", -1))


static func should_resume_error(error_code: String) -> bool:
	return error_code in [
		"STALE_EXPEDITION",
		"STALE_EXPEDITION_ENCOUNTER",
		"EXPEDITION_ENCOUNTER_FINISHED",
		"EXPEDITION_ENCOUNTER_EXPIRED",
	]


func _set_busy(busy: bool) -> void:
	_busy = busy
	if _view != null:
		_view.set_busy(busy)


func _loading_key(operation: String) -> String:
	return str({
		"start_run": "EXPEDITION_STARTING_RUN",
		"start_zone": "EXPEDITION_STARTING_ZONE",
		"enter_node": "EXPEDITION_ENTERING_NODE",
		"choose": "EXPEDITION_CHOOSING",
		"refresh_shop": "EXPEDITION_REFRESHING_SHOP",
		"abandon": "EXPEDITION_ABANDONING",
	}.get(operation, "EXPEDITION_LOADING"))


static func operation_payload(pending: Dictionary) -> Dictionary:
	var operation := str(pending.get("operation", ""))
	var payload := {"idempotency_key": str(pending.get("idempotency_key", ""))}
	if operation == "start_run":
		payload["chapter_version_id"] = str(pending.get("chapter_version_id", ""))
		payload["team_id"] = str(pending.get("team_id", ""))
		return payload
	payload["run_id"] = str(pending.get("run_id", ""))
	if operation in ["start_zone", "enter_node", "choose", "refresh_shop"]:
		payload["expected_version"] = int(pending.get("run_version", 1))
	if operation == "start_zone":
		payload["team_id"] = str(pending.get("team_id", ""))
	if operation == "enter_node":
		payload["node_id"] = str(pending.get("node_id", ""))
	if operation == "choose":
		payload["option_id"] = str(pending.get("option_id", ""))
		var target_slot := int(pending.get("target_slot", -1))
		if target_slot >= 0:
			payload["target_slot"] = target_slot
	if operation == "turn":
		payload = {
			"encounter_id": str(pending.get("encounter_id", "")),
			"expected_turn": int(pending.get("expected_turn", 1)),
			"expected_version": int(pending.get("expected_version", 1)),
			"action": str(pending.get("action", "")),
			"idempotency_key": str(pending.get("idempotency_key", "")),
		}
		if str(pending.get("action", "")) == "item":
			payload["item_id"] = str(pending.get("item_id", ""))
		if str(pending.get("action", "")) == "switch":
			payload["switch_to_slot"] = int(pending.get("switch_to_slot", -1))
	return payload


static func _snapshot(snapshots: Array, anima_id: String) -> Dictionary:
	for value in snapshots:
		var row := GameState.as_dict(value)
		if str(row.get("anima_id", "")) == anima_id:
			return row
	return {}


static func _array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
