extends Node

signal auth_started(mode: String)
signal auth_succeeded(mode: String, profile: Dictionary)
signal auth_failed(error: String)
signal existing_account_required
signal recovery_finished
signal oauth_idle

const DEEPLINK_SCRIPT := preload("res://addons/DeeplinkPlugin/Deeplink.gd")
const CALLBACK_BASE := "scanima://auth/callback"
const OAUTH_TIMEOUT_SEC := 600

var _deeplink: Node
var _recovery_pending := false
var _startup_pending := true
var _cold_start_checked := true
var _oauth_in_flight := false
var _queued_deeplink_url := ""


func _ready() -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		_cold_start_checked = false
		_deeplink = DEEPLINK_SCRIPT.new()
		_deeplink.set("scheme", "scanima")
		_deeplink.set("host", "auth")
		_deeplink.set("path_prefix", "/callback")
		add_child(_deeplink)
		_deeplink.connect("deeplink_received", _on_deeplink_received)
	_recovery_pending = (
		not GameState.pending_account_switch.is_empty()
		or (not GameState.pending_oauth.is_empty() and not GameState.is_anonymous())
	)
	call_deferred("_run_startup_auth")


func start_google_transfer() -> Dictionary:
	if _oauth_in_flight:
		return {"ok": false, "error": "ACCOUNT_SWITCH_BLOCKED"}
	if not GameState.is_anonymous():
		return {"ok": false, "error": "ACCOUNT_ALREADY_LINKED"}
	_cancel_stale_oauth()
	if GameState.account_switch_blocked():
		return {"ok": false, "error": "ACCOUNT_SWITCH_BLOCKED"}
	return await _start("transfer")


func start_google_separate() -> Dictionary:
	if _oauth_in_flight:
		return {"ok": false, "error": "ACCOUNT_SWITCH_BLOCKED"}
	if not GameState.is_anonymous():
		return {"ok": false, "error": "ACCOUNT_ALREADY_LINKED"}
	_cancel_stale_oauth()
	if GameState.account_switch_blocked():
		return {"ok": false, "error": "ACCOUNT_SWITCH_BLOCKED"}
	if not GameState.remember_device_guest():
		return {"ok": false, "error": "DEVICE_GUEST_SAVE_FAILED"}
	return await _start("separate")


## Compatibility untuk pemanggil build lama; UI baru memakai nama produk di atas.
func start_google_link() -> Dictionary:
	return await start_google_transfer()


func start_google_restore() -> Dictionary:
	return await start_google_separate()


func cancel() -> void:
	if _oauth_in_flight:
		return
	GameState.cancel_oauth()
	auth_failed.emit("OAUTH_CANCELLED")


func recover_pending() -> void:
	if GameState.pending_oauth.is_empty() or not GameState.is_anonymous():
		return
	var started_at := int(GameState.pending_oauth.get("started_at", 0))
	if started_at <= 0 or int(Time.get_unix_time_from_system()) - started_at > OAUTH_TIMEOUT_SEC:
		GameState.cancel_oauth()


func ensure_recovered() -> void:
	if _startup_pending:
		await recovery_finished
	while _oauth_in_flight:
		await oauth_idle


func _run_startup_auth() -> void:
	if _recovery_pending:
		await _recover_persisted_auth()
	else:
		recover_pending()
	_recovery_pending = false
	if not _cold_start_checked:
		await _consume_cold_start_link()
	_startup_pending = false
	recovery_finished.emit()


func _recover_persisted_auth() -> void:
	if not GameState.pending_account_switch.is_empty():
		await _recover_account_switch()
	elif not GameState.pending_oauth.is_empty() and not GameState.is_anonymous():
		var mode := normalized_mode(str(GameState.pending_oauth.get("mode", "")))
		if mode == "transfer":
			GameState.mark_device_guest_transferred()
			GameState.finish_oauth()
		elif mode == "separate":
			GameState.discard_guest_local_state(true)
			GameState.finish_oauth()
		else:
			GameState.finish_oauth()


func _recover_account_switch() -> void:
	var guest := GameState.device_guest_session()
	if guest.is_empty():
		if GameState.is_anonymous() and GameState.remember_device_guest():
			GameState.finish_account_switch()
		else:
			GameState.finish_account_switch()
			auth_failed.emit("DEVICE_GUEST_RECOVERY_FAILED")
		return
	if GameState.is_anonymous() and GameState.uid() == str(guest.get("uid", "")):
		GameState.discard_guest_local_state()
		GameState.finish_account_switch()
		return
	if not GameState.is_anonymous():
		await Backend.sign_out_local()
	if not GameState.activate_stored_session(guest):
		GameState.finish_account_switch()
		auth_failed.emit("DEVICE_GUEST_RECOVERY_FAILED")
		return
	GameState.discard_guest_local_state()
	GameState.finish_account_switch()


func handle_callback_url(url: String) -> void:
	if GameState.pending_oauth.is_empty():
		return
	if not url.begins_with(CALLBACK_BASE):
		return

	var params := parse_callback_params(url)
	var expected_state := str(GameState.pending_oauth.get("state", ""))
	if expected_state.is_empty() or str(params.get("state", "")) != expected_state:
		GameState.cancel_oauth()
		auth_failed.emit("OAUTH_STATE_MISMATCH")
		return

	var callback_error := str(params.get("error", ""))
	if not callback_error.is_empty():
		GameState.cancel_oauth()
		var error_detail := (
			callback_error + " " + str(params.get("error_description", ""))
		).to_lower()
		if error_detail.contains("identity") and (
			error_detail.contains("already")
			or error_detail.contains("another user")
		):
			existing_account_required.emit()
		else:
			auth_failed.emit("OAUTH_PROVIDER_ERROR")
		return

	# Pemain bisa kembali dari browser lalu memulai aksi sebelum callback masuk.
	# Jangan mengaktifkan UID Google di tengah intent guest yang sudah persist.
	if GameState.account_switch_blocked(true):
		GameState.cancel_oauth()
		auth_failed.emit("ACCOUNT_SWITCH_BLOCKED")
		return

	var code := str(params.get("code", ""))
	var verifier := GameState.oauth_code_verifier(expected_state)
	var mode := normalized_mode(str(GameState.pending_oauth.get("mode", "")))
	if code.is_empty() or verifier.is_empty() or mode not in ["transfer", "separate"]:
		GameState.cancel_oauth()
		auth_failed.emit("OAUTH_CALLBACK_INVALID")
		return

	var guest_uid := GameState.uid()
	var exchanged := await Backend.exchange_oauth_code(code, verifier)
	if not bool(exchanged.get("ok", false)):
		GameState.cancel_oauth()
		auth_failed.emit(str(exchanged.get("error", "OAUTH_EXCHANGE_FAILED")))
		return

	var body := GameState.as_dict(exchanged.get("data"))
	var user := GameState.as_dict(body.get("user"))
	var new_uid := str(user.get("id", ""))
	if mode == "transfer" and new_uid.is_empty():
		GameState.cancel_oauth()
		auth_failed.emit("OAUTH_SESSION_INVALID")
		return
	if mode == "transfer" and new_uid != guest_uid:
		GameState.cancel_oauth()
		existing_account_required.emit()
		return

	var accepted := Backend.accept_auth_session(body)
	if not bool(accepted.get("ok", false)):
		GameState.cancel_oauth()
		auth_failed.emit(str(accepted.get("error", "OAUTH_SESSION_INVALID")))
		return
	if mode == "transfer":
		GameState.mark_device_guest_transferred()
		GameState.finish_oauth()
	else:
		GameState.discard_guest_local_state(true)
		GameState.finish_oauth()

	var upgraded := await Backend.seeker("upgrade")
	if not bool(upgraded.get("ok", false)):
		auth_failed.emit("OAUTH_UPGRADE_PENDING")
		return
	auth_succeeded.emit(mode, GameState.as_dict(upgraded.get("data")))


static func normalized_mode(mode: String) -> String:
	if mode == "link":
		return "transfer"
	if mode == "restore":
		return "separate"
	return mode


func sign_out_to_guest() -> Dictionary:
	if GameState.is_anonymous():
		return {"ok": false, "error": "ACCOUNT_ALREADY_GUEST"}
	if GameState.account_switch_blocked():
		return {"ok": false, "error": "ACCOUNT_SWITCH_BLOCKED"}

	var prepared := await prepare_device_guest()
	if not bool(prepared.get("ok", false)):
		return prepared
	var guest := GameState.as_dict(prepared.get("session"))
	GameState.begin_account_switch("device_guest")
	var logout := await Backend.sign_out_local()
	if not GameState.activate_stored_session(guest):
		GameState.finish_account_switch()
		return {"ok": false, "error": "DEVICE_GUEST_ACTIVATE_FAILED"}
	GameState.discard_guest_local_state()
	GameState.finish_account_switch()
	auth_succeeded.emit("guest", {})
	return {
		"ok": true,
		"error": "",
		"logout_revoked": bool(logout.get("ok", false)),
	}


func prepare_device_guest() -> Dictionary:
	var prepared: Dictionary
	if GameState.device_guest_expected:
		var stored := GameState.device_guest_session()
		if stored.is_empty():
			return {"ok": false, "error": "DEVICE_GUEST_MISSING"}
		prepared = await Backend.refresh_session_candidate(stored)
	else:
		prepared = await Backend.request_anonymous_session()
	if not bool(prepared.get("ok", false)):
		return prepared
	var guest := GameState.as_dict(prepared.get("session"))
	if not bool(guest.get("is_anonymous", false)):
		return {"ok": false, "error": "DEVICE_GUEST_NOT_ANONYMOUS"}
	if not GameState.store_device_guest(guest):
		return {"ok": false, "error": "DEVICE_GUEST_SAVE_FAILED"}
	return prepared


static func parse_callback_params(url: String) -> Dictionary:
	var params: Dictionary = {}
	var query_start := url.find("?")
	var fragment_start := url.find("#")
	if query_start >= 0:
		var query_end := fragment_start if fragment_start > query_start else url.length()
		_merge_params(params, url.substr(query_start + 1, query_end - query_start - 1))
	if fragment_start >= 0:
		_merge_params(params, url.substr(fragment_start + 1))
	return params


func _start(mode: String) -> Dictionary:
	if not GameState.pending_oauth.is_empty():
		# Menekan Sign in lagi adalah cancel eksplisit untuk browser yang ditutup
		# atau callback yang tidak pernah kembali. Session guest belum diganti,
		# jadi intent lama aman dibuang dan langsung dibuat ulang.
		GameState.cancel_oauth()
	var secure_store := get_node_or_null("/root/SecureStore")
	if (
		(OS.has_feature("android") or OS.has_feature("ios"))
		and (
			secure_store == null
			or not bool(secure_store.call("has_native_store"))
		)
	):
		return {"ok": false, "error": "OAUTH_SECURE_STORE_UNAVAILABLE"}
	var session_result := await Backend.ensure_session()
	if not bool(session_result.get("ok", false)):
		return session_result

	var verifier := _random_urlsafe(48)
	var state := _random_urlsafe(24)
	var challenge := _sha256_urlsafe(verifier)
	var redirect_to := CALLBACK_BASE + "?state=" + state.uri_encode()
	if not GameState.begin_oauth(mode, state, verifier):
		return {"ok": false, "error": "OAUTH_SECURE_STORE_UNAVAILABLE"}

	var result := await Backend.oauth_authorize(mode == "transfer", redirect_to, challenge)
	if not bool(result.get("ok", false)):
		GameState.cancel_oauth()
		return result
	var auth_url := str(GameState.as_dict(result.get("data")).get("url", ""))
	if auth_url.is_empty():
		GameState.cancel_oauth()
		return {"ok": false, "error": "OAUTH_URL_MISSING"}
	auth_started.emit(mode)
	var open_error := OS.shell_open(auth_url)
	if open_error != OK:
		GameState.cancel_oauth()
		return {"ok": false, "error": "OAUTH_BROWSER_FAILED"}
	return {"ok": true, "error": ""}


func _cancel_stale_oauth() -> void:
	if not GameState.pending_oauth.is_empty():
		GameState.cancel_oauth()


func _on_deeplink_received(value: Variant) -> void:
	if value == null or not value.has_method("build_url"):
		return
	if _startup_pending:
		_queued_deeplink_url = str(value.build_url())
		return
	if _oauth_in_flight:
		return
	_oauth_in_flight = true
	await handle_callback_url(str(value.build_url()))
	_oauth_in_flight = false
	if _deeplink != null and _deeplink.has_method("clear_data"):
		_deeplink.call("clear_data")
	oauth_idle.emit()


func _consume_cold_start_link() -> void:
	var url := _queued_deeplink_url
	_queued_deeplink_url = ""
	if url.is_empty() and _deeplink != null and _deeplink.has_method("get_link_url"):
		url = str(_deeplink.call("get_link_url"))
	if not url.is_empty():
		_oauth_in_flight = true
		await handle_callback_url(url)
		_oauth_in_flight = false
		if _deeplink != null and _deeplink.has_method("clear_data"):
			_deeplink.call("clear_data")
	_cold_start_checked = true
	oauth_idle.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		recover_pending()


func _random_urlsafe(size: int) -> String:
	return _base64_url(Crypto.new().generate_random_bytes(size))


func _sha256_urlsafe(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return _base64_url(context.finish())


static func _base64_url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("=")


static func _merge_params(target: Dictionary, encoded: String) -> void:
	for pair in encoded.split("&", false):
		var separator := pair.find("=")
		if separator < 0:
			target[pair.uri_decode()] = ""
		else:
			target[pair.substr(0, separator).uri_decode()] = pair.substr(separator + 1).uri_decode()
