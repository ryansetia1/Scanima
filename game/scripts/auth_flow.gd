extends Node

signal auth_started(mode: String)
signal auth_succeeded(mode: String, profile: Dictionary)
signal auth_failed(error: String)
signal existing_account_required

const DEEPLINK_SCRIPT := preload("res://addons/DeeplinkPlugin/Deeplink.gd")
const CALLBACK_BASE := "scanima://auth/callback"
const OAUTH_TIMEOUT_SEC := 600

var _deeplink: Node


func _ready() -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		_deeplink = DEEPLINK_SCRIPT.new()
		_deeplink.set("scheme", "scanima")
		_deeplink.set("host", "auth")
		_deeplink.set("path_prefix", "/callback")
		add_child(_deeplink)
		_deeplink.connect("deeplink_received", _on_deeplink_received)
		call_deferred("_consume_cold_start_link")
	recover_pending()


func start_google_link() -> Dictionary:
	if not GameState.is_anonymous():
		return {"ok": false, "error": "ACCOUNT_ALREADY_LINKED"}
	return await _start("link")


func start_google_restore() -> Dictionary:
	return await _start("restore")


func cancel() -> void:
	GameState.cancel_oauth()
	auth_failed.emit("OAUTH_CANCELLED")


func recover_pending() -> void:
	if GameState.pending_oauth.is_empty():
		return
	var started_at := int(GameState.pending_oauth.get("started_at", 0))
	if started_at <= 0 or int(Time.get_unix_time_from_system()) - started_at > OAUTH_TIMEOUT_SEC:
		GameState.cancel_oauth()


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

	var code := str(params.get("code", ""))
	var verifier := str(GameState.pending_oauth.get("code_verifier", ""))
	var mode := str(GameState.pending_oauth.get("mode", ""))
	if code.is_empty() or verifier.is_empty() or mode not in ["link", "restore"]:
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
	if mode == "link" and (new_uid.is_empty() or new_uid != guest_uid):
		GameState.cancel_oauth()
		auth_failed.emit("OAUTH_UID_CHANGED")
		return

	var accepted := Backend.accept_auth_session(body)
	if not bool(accepted.get("ok", false)):
		GameState.cancel_oauth()
		auth_failed.emit(str(accepted.get("error", "OAUTH_SESSION_INVALID")))
		return
	GameState.finish_oauth()
	if mode == "restore":
		GameState.discard_guest_local_state()

	var profile: Dictionary = {}
	if mode == "link":
		var upgraded := await Backend.seeker("upgrade")
		if not bool(upgraded.get("ok", false)):
			auth_failed.emit("OAUTH_UPGRADE_PENDING")
			return
		profile = GameState.as_dict(upgraded.get("data"))
	auth_succeeded.emit(mode, profile)


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
	GameState.begin_oauth(mode, state, verifier)

	var result := await Backend.oauth_authorize(mode == "link", redirect_to, challenge)
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


func _on_deeplink_received(value: Variant) -> void:
	if value != null and value.has_method("build_url"):
		handle_callback_url(str(value.build_url()))


func _consume_cold_start_link() -> void:
	if _deeplink == null or not _deeplink.has_method("get_link_url"):
		return
	var url := str(_deeplink.call("get_link_url"))
	if not url.is_empty():
		handle_callback_url(url)
		if _deeplink.has_method("clear_data"):
			_deeplink.call("clear_data")


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
