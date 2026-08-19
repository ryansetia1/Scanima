class_name ExpeditionController
extends Node

signal item_picker_requested
signal inventory_refresh_requested
signal authority_refresh_requested
signal reward_presented(reward: Dictionary, encounter: Dictionary)
signal announcements_changed(announcements: Dictionary)

## Dipancarkan saat response request yang dikirim lewat `_dispatch()` tiba. Turn
## disimulasikan lokal lebih dulu supaya animasi mulai di frame yang sama dengan
## tap, sementara request-nya jalan berbarengan; sinyal ini yang menyatukan
## keduanya lagi. Hub memakainya untuk mengirim dua request sekaligus.
signal _request_settled

## Dipancarkan saat preload art run selesai, supaya enter node yang mendahuluinya
## menunggu unduhan yang sama alih-alih memulai unduhan kedua.
signal _preload_settled

const BOSS_SEEKER_SHEET := preload("res://scripts/boss_seeker_sheet.gd")

## Hanya operasi yang memang menggantikan seluruh konteks layar memakai panel
## loading. Masuk node, pilihan node, checkpoint, Shop, dan mulai zona
## mempertahankan peta/panel yang sedang dibaca pemain dan cukup meredupkan
## tombolnya lewat `set_busy` — menimpanya dengan layar loading membuat setiap
## langkah Expedition terasa seperti memuat ulang layar.
const CONTEXT_LOADING := {
	"start_run": "EXPEDITION_STARTING_RUN",
	"abandon": "EXPEDITION_ABANDONING",
}

var _view: ExpeditionView
var _battle_view: BattleView
var _roster: Array = []
var _team: Dictionary = {}
var _chapters: Array = []
var _run: Dictionary = {}
var _encounter: Dictionary = {}
var _art_cache: Dictionary = {}
var _chapter_manifest: Dictionary = {}
var _chapter_manifest_version := ""
var _busy := false
var _catalog_available := false
var _request_result: Dictionary = {}
var _request_in_flight := false
var _preload_running := false


func configure(view: ExpeditionView, battle_view: BattleView) -> void:
	_view = view
	_battle_view = battle_view
	_view.back_requested.connect(close)
	_view.chapter_requested.connect(_load_chapter)
	_view.save_team_requested.connect(_save_team)
	_view.start_run_requested.connect(_start_run)
	_view.start_zone_requested.connect(_start_zone)
	_view.checkpoint_choice_requested.connect(_choose_checkpoint)
	_view.enter_node_requested.connect(_enter_node)
	_view.choice_requested.connect(_choose)
	_view.refresh_shop_requested.connect(_refresh_shop)
	_view.action_requested.connect(_request_turn)
	_view.item_picker_requested.connect(item_picker_requested.emit)
	_view.combat_continue_requested.connect(_continue_after_combat)
	_view.complete_requested.connect(_leave_complete)


func forfeit() -> void:
	await _forfeit()


func abandon() -> void:
	await _abandon()


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


func encounter_kind() -> String:
	return str(_encounter.get("kind", ""))


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
	# Katalog dan Team tidak bergantung satu sama lain, jadi hub menunggu satu
	# round trip alih-alih dua. Sesi disegarkan lebih dulu: `Backend` belum punya
	# guard refresh in-flight, jadi dua request paralel yang sama-sama menemukan
	# token nyaris kedaluwarsa akan memakai refresh token yang sama dua kali.
	await Backend.ensure_session()
	_dispatch("team", {})
	var chapters_res := await Backend.expedition("chapters")
	var team_res := await _await_dispatch()
	if not chapters_res.ok:
		_view.set_error(chapters_res.error)
		_set_busy(false)
		return
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
	var res := await Backend.expedition("chapter", {"chapter_version_id": version_id})
	if res.ok:
		var data := GameState.as_dict(res.data)
		# Manifest chapter membawa roster lawan dan art zona; menyimpannya di sini
		# yang membuat preload run bisa menyiapkan lawan sebelum node dibuka.
		_chapter_manifest = GameState.as_dict(data.get("manifest"))
		_chapter_manifest_version = version_id
		_view.set_chapter_detail(data)
		announcements_changed.emit(GameState.as_dict(data.get("announcements")))
	else:
		_view.set_error(res.error)
	_set_busy(false)


func _save_team(anima_ids: Array[String]) -> void:
	if _busy or anima_ids.size() != 4:
		return
	_set_busy(true)
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


func _choose_checkpoint(option_id: String) -> void:
	if _busy or option_id not in ["recover", "power_up"]:
		return
	var pending := GameState.begin_expedition_operation("checkpoint_choice", {
		"option_id": option_id,
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
	_view.show_retreat_banner()
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


## Simulasi turn dari state encounter authoritative yang sudah ada di client.
## Kosong kalau state-nya belum lengkap, aksinya ditolak aturan, Switch-nya
## memanggil anggota yang sheet-nya belum ada di arena, Boss membuka ace-nya,
## atau turn itu menutup encounter Boss.
# ponytail: Item dan Boss ace selalu menunggu server. Item ikut lewat karena
# controller ini tidak memegang katalog Shop; upgrade dengan mengoper katalog
# dari scan_flow kalau item Expedition terasa lambat.
func _predict_turn(pending: Dictionary) -> Dictionary:
	var state := GameState.as_dict(_encounter.get("state"))
	if state.is_empty() or str(state.get("status", "")) != "active":
		return {}
	if int(state.get("turn", 0)) != int(pending.get("expected_turn", -1)):
		return {}
	var outcome := TeamSim.resolve_team_turn(
		state,
		str(pending.get("action", "")),
		str(pending.get("idempotency_key", "")),
		str(pending.get("item_id", "")),
		pending.get("switch_to_slot", null)
	)
	if not bool(outcome.get("ok", false)):
		return {}
	var next_state := GameState.as_dict(outcome["state"])
	# Turn penutup Boss membawa baris terakhir Seeker, ringkasan hadiah, dan
	# reveal Trophy first-clear. Ketiganya dibaca dari reward authoritative, jadi
	# menebaknya hanya menampilkan angka lama sebelum server memperbaikinya.
	if (
		str(_encounter.get("kind", "")) == "boss"
		and str(next_state.get("status", "active")) != "active"
	):
		return {}
	var events: Array = outcome["events"]
	for value in events:
		if str(GameState.as_dict(value).get("type", "")) == "final_ace":
			return {}
	for anima_id in TeamSim.switch_targets(events, next_state):
		if not _art_cache.has(anima_id):
			return {}
	var encounter := _encounter.duplicate(true)
	encounter["state"] = outcome["state"]
	encounter["turn_number"] = int(next_state.get("turn", encounter.get("turn_number", 1)))
	encounter["status"] = str(next_state.get("status", "active"))
	return {"encounter": encounter, "events": events}


## Ringkasan turn seperti yang dilihat pemain. HP Expedition hidup di dalam roster,
## jadi event-nya yang membawa angka itu.
static func _turn_outcome_digest(state: Dictionary, events: Array) -> String:
	var parts := PackedStringArray([
		str(state.get("status", "")),
		str(int(float(state.get("turn", 0)))),
	])
	for value in events:
		var event := GameState.as_dict(value)
		parts.append(
			"%s/%s/%d/%d"
			% [
				str(event.get("type", "")),
				str(event.get("actor", "")),
				int(float(event.get("damage", 0))),
				int(float(event.get("target_hp", -1))),
			]
		)
	return "|".join(parts)


static func _turn_outcome_matches(
	predicted: Dictionary, next_encounter: Dictionary, events: Array
) -> bool:
	if predicted.is_empty():
		return false
	var predicted_encounter: Dictionary = predicted["encounter"]
	return (
		_turn_outcome_digest(GameState.as_dict(predicted_encounter.get("state")), predicted["events"])
		== _turn_outcome_digest(GameState.as_dict(next_encounter.get("state")), events)
	)


## Mengirim satu request tanpa menahan pemanggilnya. Setiap `_dispatch()` wajib
## dipasangkan dengan tepat satu `_await_dispatch()` sesudahnya.
func _dispatch(operation: String, payload: Dictionary) -> void:
	_request_in_flight = true
	_request_result = await Backend.expedition(operation, payload)
	_request_in_flight = false
	_request_settled.emit()


func _await_dispatch() -> Dictionary:
	if _request_in_flight:
		await _request_settled
	return _request_result


func _submit_pending(pending: Dictionary) -> void:
	if pending.is_empty():
		return
	var operation := str(pending.get("operation", ""))
	if operation == "turn":
		_view.begin_combat_action(str(pending.get("action", "")))
	elif CONTEXT_LOADING.has(operation):
		_view.set_loading(str(CONTEXT_LOADING[operation]))
	_set_busy(true)
	var predicted := _predict_turn(pending) if operation == "turn" else {}
	_dispatch(operation, operation_payload(pending))
	if not predicted.is_empty():
		await _view.play_combat_events(
			predicted["events"],
			predicted["encounter"],
			await _attach_seeker_art(_art_cache.duplicate())
		)
		# play_events melepas tombolnya sendiri. Turn berikutnya baru boleh dikirim
		# setelah server memberi version-nya, jadi redupkan lagi kalau masih terbang.
		_view.set_busy(_request_in_flight)
	var res := await _await_dispatch()
	if not res.ok:
		# Turn yang tidak sampai ke server tidak boleh meninggalkan arena di masa
		# depan: `_encounter` masih memegang state authoritative terakhir.
		if not predicted.is_empty() and not _encounter.is_empty():
			_view.set_combat_encounter(_encounter, _art_cache.duplicate())
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
	var zone_reward_changed := _zone_reward_changed(_run, next_run)
	var turn_reward: Dictionary = {}
	if next_run.is_empty():
		_view.set_error("EXPEDITION_RUN_NOT_FOUND")
		_set_busy(false)
		return
	if operation == "turn":
		turn_reward = GameState.as_dict(data.get("reward"))
		if zone_reward_changed:
			var zone_reward := GameState.as_dict(next_run.get("last_zone_reward"))
			turn_reward["zone_bits"] = int(zone_reward.get("bits", 0))
			turn_reward["zone_scheduled_bits"] = int(zone_reward.get("scheduled_bits", 0))
		next_encounter["last_reward"] = turn_reward
		var events := _array(data.get("events"))
		if _turn_outcome_matches(predicted, next_encounter, events):
			# Animasinya sudah jalan dari simulasi lokal; ini tinggal memasang row
			# authoritative supaya version/reward-nya yang dipakai turn berikutnya.
			_view.set_combat_encounter(next_encounter, _art_cache.duplicate())
		else:
			var art := _art_cache.duplicate()
			for value in events:
				if str(GameState.as_dict(value).get("type", "")) == "switch":
					art = await _prepare_active_art(next_encounter, false)
					break
			art = await _attach_seeker_art(art)
			art = await _attach_trophy_art(turn_reward, str(data.get("asset_base_url", "")), art)
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
	var encounter_rewarded := (
		operation == "turn" and not GameState.as_dict(data.get("reward")).is_empty()
	)
	var zone_bits_awarded := zone_reward_changed and int(
		GameState.as_dict(next_run.get("last_zone_reward")).get("bits", 0)
	) > 0
	if encounter_rewarded:
		reward_presented.emit(turn_reward, next_encounter)
	elif zone_bits_awarded:
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
	if _encounter.is_empty():
		# Tanpa await: pemain sudah bisa membaca peta sementara art-nya turun.
		_preload_run_art()


## Art yang dibutuhkan encounter berikutnya sudah dapat diketahui dari payload run
## — art zona, roster pemain, dan Boss Seeker semuanya ada di sana — jadi ia diunduh
## selama pemain membaca peta, bukan saat ia menekan node. Lawan ikut kalau manifest
## chapter sudah ada dari layar detail.
# ponytail: cache hanya di memori proses (art chapter publik tetap diunduh ulang
# tiap sesi app), dan `_prepare_active_art` menunggu seluruh task ini kalau pemain
# menekan node lebih cepat daripada unduhannya — paling banyak satu grup lawan
# ekstra. Upgrade: cache disk ber-key path aset chapter yang immutable kalau
# kuota seluler jadi keluhan.
func _preload_run_art() -> void:
	if _preload_running or _run.is_empty() or not _encounter.is_empty():
		return
	_preload_running = true
	await _load_arena_background(_encounter)
	for value in _array(_run.get("party_state")):
		await _cache_member_art(GameState.as_dict(value))
	await _attach_seeker_art({})
	for value in _zone_opponent_snapshots():
		await _cache_member_art(GameState.as_dict(value))
	_preload_running = false
	_preload_settled.emit()


## Roster lawan zona berjalan, dibaca dari manifest chapter yang sudah diambil layar
## detail. Resume dingin tidak memegang manifest itu, jadi ia mengembalikan kosong
## dan lawan tetap diunduh saat node dibuka.
func _zone_opponent_snapshots() -> Array:
	if (
		_chapter_manifest.is_empty()
		or _chapter_manifest_version != str(_run.get("chapter_version_id", ""))
	):
		return []
	var zones := _array(_chapter_manifest.get("zones"))
	var zone := int(_run.get("zone", 1))
	if zone < 1 or zone > zones.size():
		return []
	var wanted: Array[String] = []
	var pools := GameState.as_dict(GameState.as_dict(zones[zone - 1]).get("node_pools"))
	for kind in ["battle", "elite"]:
		for value in _array(pools.get(kind)):
			var group_id := str(GameState.as_dict(value).get("opponent_id", ""))
			if not group_id.is_empty() and not group_id in wanted:
				wanted.append(group_id)
	if zone == zones.size():
		var boss_id := str(GameState.as_dict(_chapter_manifest.get("boss")).get("opponent_id", ""))
		if not boss_id.is_empty() and not boss_id in wanted:
			wanted.append(boss_id)
	var result: Array = []
	for value in _array(_chapter_manifest.get("opponents")):
		var group := GameState.as_dict(value)
		if str(group.get("id", "")) in wanted:
			result.append_array(_array(group.get("roster")))
	return result


func _cache_member_art(snapshot: Dictionary) -> void:
	var anima_id := str(snapshot.get("anima_id", ""))
	if anima_id.is_empty() or _art_cache.has(anima_id):
		return
	var loaded := await _load_art(snapshot)
	if bool(loaded.get("ok", false)):
		_art_cache[anima_id] = loaded


func _prepare_active_art(encounter: Dictionary, include_background: bool = true) -> Dictionary:
	var result: Dictionary = {}
	if _preload_running:
		await _preload_settled
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
			if not _art_cache.has(anima_id):
				await _cache_member_art(_snapshot(snapshots, anima_id))
			if not _art_cache.has(anima_id):
				if slot == active_slot:
					return {}
				continue
			result[anima_id] = _art_cache[anima_id]
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


## Art Trophy hanya ikut pada reward first-clear, jadi ia diunduh sekali saat
## reward-nya tiba — bukan disiapkan bersama roster setiap encounter.
func _attach_trophy_art(
	reward: Dictionary,
	asset_base_url: String,
	art: Dictionary
) -> Dictionary:
	var trophy := GameState.as_dict(reward.get("trophy"))
	if trophy.is_empty():
		return art
	if _art_cache.get("trophy") is Texture2D:
		art["trophy"] = _art_cache["trophy"]
		return art
	var base := asset_base_url
	if base.is_empty():
		base = str(_run.get("asset_base_url", ""))
	var url := str(trophy.get("art_url", "")).strip_edges()
	if url.is_empty():
		var path := str(trophy.get("art_path", "")).strip_edges()
		if base.is_empty() or path.is_empty() or path.contains(".."):
			return art
		url = "%s/%s" % [base.rstrip("/"), path]
	var download := await Backend.download_url(url)
	if not download.ok:
		return art
	var image := Image.new()
	if image.load_png_from_buffer(download.bytes) != OK:
		return art
	var texture := ImageTexture.create_from_image(image)
	_art_cache["trophy"] = texture
	art["trophy"] = texture
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
	if image.generate_mipmaps() != OK:
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
	# Anggota tim adalah Anima pemain sendiri, jadi sheet-nya biasanya sudah ada di
	# cache disk milik Home/Collection. Kunci cache-nya anima_id + stage, jadi hasil
	# evolusi tetap mendapat art barunya.
	var anima_id := str(snapshot.get("anima_id", ""))
	var stage := int(snapshot.get("stage", 1))
	if not anima_id.is_empty() and GameState.has_sprite_for_anima(anima_id, stage):
		var cached := AnimaLoader.load_from_manifest(
			GameState.manifest_path_for_anima(anima_id, stage)
		)
		if bool(cached.get("ok", false)):
			return cached
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


static func _zone_reward_changed(previous_run: Dictionary, next_run: Dictionary) -> bool:
	var previous := GameState.as_dict(previous_run.get("last_zone_reward"))
	var current := GameState.as_dict(next_run.get("last_zone_reward"))
	return not current.is_empty() and (
		int(previous.get("zone", 0)) != int(current.get("zone", 0))
		or int(previous.get("bits", -1)) != int(current.get("bits", -1))
	)


func _set_busy(busy: bool) -> void:
	_busy = busy
	if _view != null:
		_view.set_busy(busy)


static func operation_payload(pending: Dictionary) -> Dictionary:
	var operation := str(pending.get("operation", ""))
	var payload := {"idempotency_key": str(pending.get("idempotency_key", ""))}
	if operation == "start_run":
		payload["chapter_version_id"] = str(pending.get("chapter_version_id", ""))
		payload["team_id"] = str(pending.get("team_id", ""))
		return payload
	payload["run_id"] = str(pending.get("run_id", ""))
	if operation in ["start_zone", "checkpoint_choice", "enter_node", "choose", "refresh_shop"]:
		payload["expected_version"] = int(pending.get("run_version", 1))
	if operation == "start_zone":
		payload["team_id"] = str(pending.get("team_id", ""))
	if operation == "enter_node":
		payload["node_id"] = str(pending.get("node_id", ""))
	if operation in ["checkpoint_choice", "choose"]:
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
