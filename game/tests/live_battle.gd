extends SceneTree

## Jalur Battle client sungguhan terhadap produksi. Nol model call dan nol Core:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##     --script res://tests/live_battle.gd
##
## Memakai akun uji live_scan yang sama agar tidak menumpuk anonymous user.
## Menjalankan resume, ketiga action, replay idempoten, forfeit, dan cross-owner.

const PATH_UJI := "user://live_scan_state.json"
const DIR_UJI := "user://live_scan_animas"
const PATH_UJI_BARU := "user://live_battle_state.json"
const DIR_UJI_BARU := "user://live_battle_animas"

var GameState: Node
var Backend: Node


func _initialize() -> void:
	await process_frame
	GameState = get_root().get_node("GameState")
	Backend = get_root().get_node("Backend")
	var fresh := OS.get_cmdline_user_args().has("--fresh-test-session")
	GameState.path_state = PATH_UJI_BARU if fresh else PATH_UJI
	GameState.dir_animas = DIR_UJI_BARU if fresh else DIR_UJI
	if fresh:
		# --script memuat autoload default lebih dulu; jangan menyalin sesi pemain
		# utama ke file uji baru ketika file target belum ada.
		GameState.session = {}
		GameState.pending_scan = {}
		GameState.pending_care = {}
		GameState.pending_battle = {}
		GameState.last_anima = {}
		GameState.profile = {}
	GameState.load_state()

	var ok := await _run()
	if ok:
		print("live_battle: OK")
		quit(0)
	else:
		printerr("live_battle: GAGAL")
		quit(1)


func _run() -> bool:
	print("1. sesi dan Anima eligible")
	var auth: Dictionary = await Backend.ensure_session()
	if not auth.ok:
		return _fail("sign-in gagal: %s" % auth.error)
	print("  pemain %s" % GameState.uid())
	var profile_res: Dictionary = await Backend.fetch_profile()
	if not profile_res.ok:
		return _fail("profil gagal: %s" % profile_res.error)
	var cores_before := int(GameState.profile.get("genesis_cores", -1))
	var roster_res: Dictionary = await Backend.fetch_animas()
	if not roster_res.ok or typeof(roster_res.data) != TYPE_ARRAY:
		return _fail("roster gagal: %s" % roster_res.error)
	var player: Dictionary = {}
	for value in roster_res.data:
		var row: Dictionary = GameState.as_dict(value)
		if (
			str(row.get("status", "")) == "ready"
			and not _has_timestamp(row.get("sleep_started_at"))
			and not _has_timestamp(row.get("dormant_since"))
		):
			player = row
			break
	if player.is_empty():
		return _fail("akun live_scan tidak punya Anima awake yang eligible")
	print("  %s" % str(player.get("nickname", "Anima")))

	print("2. status reward harian")
	var status: Dictionary = await Backend.battle_anima("status")
	var daily_reward: Dictionary = GameState.as_dict(status.data)
	if (
		not status.ok
		or int(daily_reward.get("limit", 0)) < 1
		or str(daily_reward.get("server_now", "")).is_empty()
		or str(daily_reward.get("reset_at", "")).is_empty()
	):
		return _fail("status reward harian tidak sah: %s" % str(status))

	print("3. payload invalid ditolak")
	var invalid: Dictionary = await Backend.battle_anima("turn", {"action": "strike"})
	if invalid.ok or invalid.code != 400 or invalid.error != "INVALID_SESSION_ID":
		return _fail("payload invalid tidak ditolak tepat: %s" % str(invalid))

	print("4. start dan resume")
	var start: Dictionary = await Backend.battle_anima("start", {"anima_id": str(player.get("id", ""))})
	if not start.ok:
		return _fail("start gagal: %s" % start.error)
	var session: Dictionary = GameState.as_dict(start.data)
	var session_id := str(session.get("id", ""))
	var bot: Dictionary = GameState.as_dict(session.get("bot_snapshot"))
	if session_id.is_empty() or bot.has("owner_id") or bot.has("nickname"):
		return _fail("session atau anonimitas bot tidak sah")
	GameState.remember_battle(
		session_id,
		int(session.get("turn_number", 1)),
		int(session.get("version", 1))
	)
	var resumed: Dictionary = await Backend.battle_anima("resume", {"session_id": session_id})
	if not resumed.ok or str(GameState.as_dict(resumed.data).get("id", "")) != session_id:
		return _fail("resume tidak mengembalikan session yang sama")

	print("5. Strike, Guard, Surge dan replay")
	var replay_checked := false
	for action in ["strike", "guard", "surge"]:
		if str(session.get("status", "")) != "active":
			var restarted: Dictionary = await Backend.battle_anima(
				"start",
				{"anima_id": str(player.get("id", ""))}
			)
			if not restarted.ok:
				return _fail("start ulang untuk %s gagal: %s" % [action, restarted.error])
			session = GameState.as_dict(restarted.data)
			GameState.remember_battle(
				str(session.get("id", "")),
				int(session.get("turn_number", 1)),
				int(session.get("version", 1))
			)
		var pending: Dictionary = GameState.begin_battle_action(
			str(session.get("id", "")),
			int(session.get("turn_number", 1)),
			int(session.get("version", 1)),
			action
		)
		var payload := {
			"session_id": pending.get("session_id"),
			"expected_turn": pending.get("expected_turn"),
			"expected_version": pending.get("expected_version"),
			"action": pending.get("action"),
			"idempotency_key": pending.get("idempotency_key"),
		}
		var turn: Dictionary = await Backend.battle_anima("turn", payload)
		if not turn.ok:
			return _fail("%s gagal: %s" % [action, turn.error])
		var data: Dictionary = GameState.as_dict(turn.data)
		var next_session: Dictionary = GameState.as_dict(data.get("session"))
		if (
			int(next_session.get("turn_number", 0)) != int(session.get("turn_number", 0)) + 1
			or int(next_session.get("version", 0)) != int(session.get("version", 0)) + 1
		):
			return _fail("%s tidak menaikkan turn/version tepat sekali" % action)
		if not replay_checked:
			var replay: Dictionary = await Backend.battle_anima("turn", payload)
			var replay_data: Dictionary = GameState.as_dict(replay.data)
			if not replay.ok or not bool(replay_data.get("replayed", false)):
				return _fail("retry key yang sama tidak masuk replay")
			if GameState.as_dict(replay_data.get("session")) != next_session:
				return _fail("replay mengubah state Battle")
			replay_checked = true
		GameState.confirm_battle_response(next_session)
		session = next_session
		print("  %s -> turn %d" % [action, int(session.get("turn_number", 0))])

	print("6. forfeit dan cross-owner")
	if str(session.get("status", "")) == "active":
		var forfeited: Dictionary = await Backend.battle_anima(
			"forfeit",
			{"session_id": str(session.get("id", ""))}
		)
		if not forfeited.ok or str(GameState.as_dict(forfeited.data).get("status", "")) != "forfeited":
			return _fail("forfeit gagal")
	GameState.finish_battle()
	var foreign_id := str(bot.get("anima_id", ""))
	if not foreign_id.is_empty():
		var foreign: Dictionary = await Backend.battle_anima("start", {"anima_id": foreign_id})
		if foreign.ok or foreign.error != "ANIMA_NOT_FOUND":
			return _fail("cross-owner start tidak ditolak")

	var final_profile: Dictionary = await Backend.fetch_profile()
	if not final_profile.ok or int(GameState.profile.get("genesis_cores", -2)) != cores_before:
		return _fail("Battle mengubah Genesis Core")
	return true


static func _has_timestamp(value: Variant) -> bool:
	return value != null and not str(value).is_empty()


func _fail(message: String) -> bool:
	printerr("  %s" % message)
	GameState.finish_battle()
	return false
