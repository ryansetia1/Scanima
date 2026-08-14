extends SceneTree

## Gratis dan tanpa browser/jaringan:
##   godot --headless --path game --script res://tests/test_auth_flow.gd

const STATE_PATH := "user://uji_auth_state.json"
const SECURE_PATH := "user://uji_auth_secure.json"

var _checks := 0
var _failures: PackedStringArray = []
var _state: Node
var _secure: Node
var _backend: Node
var _auth: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_state = get_root().get_node("GameState")
	_secure = get_root().get_node("SecureStore")
	_backend = get_root().get_node("Backend")
	_auth = get_root().get_node("AuthFlow")
	_state.path_state = STATE_PATH
	_secure.fallback_path = SECURE_PATH
	_clean()

	_state.session = {}
	_state.pending_oauth = {}
	_state.set_session("guest-access", "guest-refresh", 2000000000, "guest-uid", true)
	_state.begin_oauth("link", "state-ok", "verifier-ok")
	_check(_state.is_anonymous(), "fixture harus dimulai sebagai guest")
	_check_eq(_secure.load_backup().get("refresh_token"), "guest-refresh",
		"backup guest harus hidup di secure store")

	# Callback palsu tidak boleh mengganti atau menghapus session guest.
	_auth.handle_callback_url("scanima://auth/callback?state=wrong&code=x")
	_check_eq(_state.uid(), "guest-uid", "state mismatch harus memulihkan uid guest")
	_check_eq(_state.session.get("refresh_token"), "guest-refresh",
		"state mismatch harus memulihkan refresh token guest")
	_check(_state.pending_oauth.is_empty(), "state mismatch harus membersihkan intent OAuth")

	# Parser menerima query dan fragment seperti dua bentuk callback GoTrue.
	var auth_script := _auth.get_script() as GDScript
	var parsed: Dictionary = auth_script.parse_callback_params(
		"scanima://auth/callback?state=a%20b&code=query#error_description=none"
	)
	_check_eq(parsed.get("state"), "a b", "state URL-encoded harus didecode")
	_check_eq(parsed.get("code"), "query", "authorization code harus terbaca")
	_check_eq(parsed.get("error_description"), "none", "fragment callback harus terbaca")
	var profile_script := load("res://scripts/seeker_profile_view.gd") as GDScript
	_check_eq(profile_script.level_from_xp(0), 1, "0 Seeker EXP harus Level 1")
	_check_eq(profile_script.level_from_xp(5), 2, "5 Seeker EXP harus Level 2")
	_check_eq(profile_script.level_from_xp(20), 3, "20 Seeker EXP harus Level 3")
	var restore_authorize: Dictionary = await _backend.oauth_authorize(
		false,
		"scanima://auth/callback?state=restore smoke",
		"pkce-challenge",
	)
	var restore_url := str(_state.as_dict(restore_authorize.get("data")).get("url", ""))
	_check(bool(restore_authorize.get("ok", false)),
		"restore harus membangun URL OAuth tanpa request awal")
	_check(restore_url.begins_with(
		"https://kgcaisvmmpxswevjvgft.supabase.co/auth/v1/authorize?provider=google"
	), "restore harus membuka endpoint authorize Supabase")
	_check(restore_url.contains("redirect_to=scanima%3A%2F%2Fauth%2Fcallback"),
		"callback aplikasi harus URL-encoded")
	_check(restore_url.contains("code_challenge=pkce-challenge"),
		"PKCE challenge harus ikut ke browser")

	var restore_prompts: Array[String] = []
	_auth.existing_account_required.connect(func() -> void: restore_prompts.append("restore"))
	_state.begin_oauth("link", "conflict-state", "conflict-verifier")
	_auth.handle_callback_url(
		"scanima://auth/callback?state=conflict-state&error=invalid_request"
		+ "&error_description=Identity%20is%20already%20linked%20to%20another%20user"
	)
	_check_eq(restore_prompts.size(), 1, "identity conflict harus menawarkan restore")
	_check_eq(_state.uid(), "guest-uid", "identity conflict tidak boleh menghapus guest")

	# Response auth dimock sebagai payload GoTrue; session baru baru diterima
	# setelah payload lengkap, lalu backup dibuang eksplisit.
	_state.begin_oauth("restore", "restore-state", "restore-verifier")
	var accepted: Dictionary = _backend.accept_auth_session({
		"access_token": "linked-access",
		"refresh_token": "linked-refresh",
		"expires_in": 3600,
		"user": {"id": "linked-uid", "is_anonymous": false},
	})
	_check(bool(accepted.get("ok", false)), "response auth lengkap harus diterima")
	_state.pending_scan = {"idempotency_key": "guest-scan"}
	_state.pending_care = {"idempotency_key": "guest-care"}
	_state.last_anima = {"id": "guest-anima"}
	_state.finish_oauth()
	_state.discard_guest_local_state()
	_check_eq(_state.uid(), "linked-uid", "restore harus memasang uid linked")
	_check(not _state.is_anonymous(), "session Google tidak boleh tetap ditandai guest")
	_check(_secure.load_backup().is_empty(), "backup guest harus hilang sesudah sukses")
	_check(_state.pending_scan.is_empty() and _state.pending_care.is_empty(),
		"restore tidak boleh membawa intent guest ke akun Google")
	_check(_state.last_anima.is_empty(), "restore tidak boleh membawa pilihan Anima guest")

	# Pending intent dan verifier bertahan restart, tetapi token tetap di secure file.
	_state.begin_oauth("link", "persisted-state", "persisted-verifier")
	_state.pending_oauth = {}
	_state.session = {}
	_state.load_state()
	_check_eq(_state.pending_oauth.get("state"), "persisted-state",
		"pending OAuth harus bertahan restart")
	_check_eq(_state.session.get("refresh_token"), "linked-refresh",
		"session harus pulih dari secure store")
	_state.cancel_oauth()

	_clean()
	if _failures.is_empty():
		print("test_auth_flow: OK (%d check)" % _checks)
		quit(0)
	else:
		printerr("test_auth_flow: GAGAL %d dari %d check" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - %s" % failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s (dapat %s, harus %s)" % [message, str(actual), str(expected)])


func _clean() -> void:
	DirAccess.remove_absolute(STATE_PATH)
	DirAccess.remove_absolute(STATE_PATH + ".tmp")
	DirAccess.remove_absolute(SECURE_PATH)
	DirAccess.remove_absolute(SECURE_PATH + ".tmp")
