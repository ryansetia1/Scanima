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
	_state.pending_account_switch = {}
	_state.device_guest_expected = false
	_state.set_session("guest-access", "guest-refresh", 2000000000, "guest-uid", true)
	_check(_state.begin_oauth("transfer", "state-ok", "verifier-ok"),
		"PKCE harus tersimpan aman sebelum browser dibuka")
	_check(_state.is_anonymous(), "fixture harus dimulai sebagai guest")
	var oauth_state_on_disk := FileAccess.get_file_as_string(STATE_PATH)
	_check(not oauth_state_on_disk.contains("verifier-ok")
		and not oauth_state_on_disk.contains("code_verifier"),
		"verifier PKCE tidak boleh masuk state.json")
	_check_eq(_secure.load_oauth_pkce().get("code_verifier"), "verifier-ok",
		"verifier PKCE harus hidup di SecureStore")
	_check_eq(_secure.load_backup().get("refresh_token"), "guest-refresh",
		"backup guest harus hidup di secure store")
	_check_eq(_secure.load_device_guest().get("uid"), "guest-uid",
		"session anonymous aktif harus otomatis menjadi guest perangkat")

	# Callback palsu tidak boleh mengganti atau menghapus session guest.
	_auth.handle_callback_url("scanima://auth/callback?state=wrong&code=x")
	_check_eq(_state.uid(), "guest-uid", "state mismatch harus memulihkan uid guest")
	_check_eq(_state.session.get("refresh_token"), "guest-refresh",
		"state mismatch harus memulihkan refresh token guest")
	_check(_state.pending_oauth.is_empty(), "state mismatch harus membersihkan intent OAuth")
	_check(_secure.load_oauth_pkce().is_empty(),
		"state mismatch harus membersihkan verifier PKCE")
	_check(not bool(_auth.get("_startup_pending")),
		"recovery dan cold-start callback harus selesai melalui satu startup gate")

	# Aksi bisa dimulai setelah browser terbuka tetapi sebelum deeplink sampai.
	# Callback wajib tetap di guest daripada mengganti UID di tengah mutation.
	var blocked_errors: Array[String] = []
	_auth.auth_failed.connect(func(error: String) -> void: blocked_errors.append(error))
	_check(_state.begin_oauth("separate", "blocked-state", "blocked-verifier"),
		"fixture callback terblokir harus menyimpan PKCE")
	_state.pending_care = {"idempotency_key": "care-after-browser"}
	await _auth.handle_callback_url(
		"scanima://auth/callback?state=blocked-state&code=must-not-exchange"
	)
	_check_eq(blocked_errors[-1] if not blocked_errors.is_empty() else "", "ACCOUNT_SWITCH_BLOCKED",
		"callback OAuth harus ditolak kalau mutation dimulai sesudah browser terbuka")
	_check_eq(_state.uid(), "guest-uid",
		"callback yang terblokir tidak boleh mengaktifkan UID Google")
	_check(_state.pending_oauth.is_empty() and _secure.load_oauth_pkce().is_empty(),
		"callback terblokir harus membersihkan intent dan verifier OAuth")
	_state.pending_care = {}

	# Parser menerima query dan fragment seperti dua bentuk callback GoTrue.
	var auth_script := _auth.get_script() as GDScript
	var parsed: Dictionary = auth_script.parse_callback_params(
		"scanima://auth/callback?state=a%20b&code=query#error_description=none"
	)
	_check_eq(parsed.get("state"), "a b", "state URL-encoded harus didecode")
	_check_eq(parsed.get("code"), "query", "authorization code harus terbaca")
	_check_eq(parsed.get("error_description"), "none", "fragment callback harus terbaca")
	_check_eq(auth_script.normalized_mode("link"), "transfer",
		"intent link dari build lama harus pulih sebagai transfer")
	_check_eq(auth_script.normalized_mode("restore"), "separate",
		"intent restore dari build lama harus pulih sebagai sign-in terpisah")
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
	_check(restore_url.contains("prompt=select_account"),
		"Google account picker harus dipaksa pada setiap sign-in")

	var restore_prompts: Array[String] = []
	_auth.existing_account_required.connect(func() -> void: restore_prompts.append("restore"))
	_check(_state.begin_oauth("transfer", "conflict-state", "conflict-verifier"),
		"fixture conflict harus menyimpan PKCE")
	_auth.handle_callback_url(
		"scanima://auth/callback?state=conflict-state&error=invalid_request"
		+ "&error_description=Identity%20is%20already%20linked%20to%20another%20user"
	)
	_check_eq(restore_prompts.size(), 1, "identity conflict harus menawarkan restore")
	_check_eq(_state.uid(), "guest-uid", "identity conflict tidak boleh menghapus guest")

	# Response auth dimock sebagai payload GoTrue; session baru baru diterima
	# setelah payload lengkap, lalu backup dibuang eksplisit.
	_check(_state.begin_oauth("separate", "restore-state", "restore-verifier"),
		"fixture separate harus menyimpan PKCE")
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
	_state.discard_guest_local_state(true)
	_check(not _state.pending_oauth.is_empty(),
		"cleanup UID guest harus mempertahankan marker OAuth sampai selesai")
	_check(not _secure.load_backup().is_empty(),
		"backup guest harus bertahan selama marker OAuth belum selesai")
	_state.finish_oauth()
	_check_eq(_state.uid(), "linked-uid", "restore harus memasang uid linked")
	_check(not _state.is_anonymous(), "session Google tidak boleh tetap ditandai guest")
	_check(_secure.load_backup().is_empty(), "backup guest harus hilang sesudah sukses")
	_check(_secure.load_oauth_pkce().is_empty(),
		"verifier PKCE harus hilang sesudah OAuth selesai")
	_check(_state.pending_scan.is_empty() and _state.pending_care.is_empty(),
		"restore tidak boleh membawa intent guest ke akun Google")
	_check(_state.last_anima.is_empty(), "restore tidak boleh membawa pilihan Anima guest")
	_check_eq(_secure.load_device_guest().get("uid"), "guest-uid",
		"sign-in terpisah harus mempertahankan guest perangkat")

	# Marker switch bertahan sampai guest benar-benar menjadi sesi aktif.
	_state.begin_account_switch("device_guest")
	_check(not _state.pending_account_switch.is_empty(),
		"pergantian akun harus memiliki marker recovery")
	_check(_state.activate_stored_session(_state.device_guest_session()),
		"guest yang disimpan harus bisa diaktifkan kembali")
	_state.finish_account_switch()
	_check_eq(_state.uid(), "guest-uid", "Sign Out harus kembali ke uid guest yang sama")
	_check(_state.pending_account_switch.is_empty(),
		"marker switch baru hilang setelah guest aktif")

	# Pending intent dan verifier bertahan restart, tetapi token tetap di secure file.
	accepted = _backend.accept_auth_session({
		"access_token": "linked-access-2",
		"refresh_token": "linked-refresh-2",
		"expires_in": 3600,
		"user": {"id": "linked-uid", "is_anonymous": false},
	})
	_check(bool(accepted.get("ok", false)), "fixture linked kedua harus diterima")
	_check(_state.begin_oauth("separate", "persisted-state", "persisted-verifier"),
		"fixture restart harus menyimpan PKCE")
	_state.pending_oauth = {}
	_state.session = {}
	_state.load_state()
	_check_eq(_state.pending_oauth.get("state"), "persisted-state",
		"pending OAuth harus bertahan restart")
	_check_eq(_state.session.get("refresh_token"), "linked-refresh-2",
		"session harus pulih dari secure store")
	_check_eq(_state.oauth_code_verifier("persisted-state"), "persisted-verifier",
		"verifier PKCE harus pulih dari SecureStore setelah restart")
	_state.cancel_oauth()

	# Sesi aktif yang hilang tidak boleh membuat UID guest baru dan menimpa vault.
	_state.session = {}
	_secure.clear_session()
	var recovered_guest: Dictionary = await _backend.ensure_session()
	_check(bool(recovered_guest.get("ok", false)),
		"ensure_session harus memulihkan guest perangkat yang masih valid")
	_check_eq(_state.uid(), "guest-uid",
		"ensure_session tidak boleh mengganti guest tersimpan dengan UID baru")

	_state.mark_device_guest_transferred()
	_check(_secure.load_device_guest().is_empty(),
		"transfer sukses harus membuang token guest lama")
	_check(not _state.device_guest_expected,
		"Sign Out setelah transfer harus membuat guest baru, bukan menghidupkan guest lama")

	# Urutan operasi sengaja dipagari: marker recovery baru boleh hilang setelah
	# slot guest/intent UID lama selesai dibereskan.
	var auth_source := FileAccess.get_file_as_string("res://scripts/auth_flow.gd")
	var callback_start := auth_source.find("func handle_callback_url")
	var callback_end := auth_source.find("\n\nfunc sign_out_to_guest", callback_start)
	var callback_body := auth_source.substr(callback_start, callback_end - callback_start)
	var transfer_cleanup := callback_body.find("GameState.mark_device_guest_transferred()")
	var transfer_finish := callback_body.find("GameState.finish_oauth()", transfer_cleanup)
	_check(transfer_cleanup >= 0 and transfer_finish > transfer_cleanup,
		"transfer harus membuang slot guest sebelum menghapus marker OAuth")
	var separate_cleanup := callback_body.find("GameState.discard_guest_local_state(true)")
	var separate_finish := callback_body.find("GameState.finish_oauth()", separate_cleanup)
	_check(separate_cleanup >= 0 and separate_finish > separate_cleanup,
		"sign-in terpisah harus membersihkan state guest sebelum marker OAuth hilang")
	var uid_conflict := callback_body.find("new_uid != guest_uid")
	var separate_offer := callback_body.find("existing_account_required.emit()", uid_conflict)
	_check(uid_conflict >= 0 and separate_offer > uid_conflict,
		"transfer ke UID Google lama harus menawarkan sign-in terpisah, bukan merge")
	var sign_out_start := auth_source.find("func sign_out_to_guest")
	var sign_out_body := auth_source.substr(sign_out_start)
	var activate_guest := sign_out_body.find("GameState.activate_stored_session(guest)")
	var discard_linked := sign_out_body.find("GameState.discard_guest_local_state()")
	_check(activate_guest >= 0 and discard_linked > activate_guest,
		"Sign Out tidak boleh membuang state linked sebelum guest berhasil aktif")
	_check(auth_source.contains("if _oauth_in_flight:"),
		"callback OAuth aktif harus memblokir percobaan sign-in yang bersaing")

	var missing_uid: Dictionary = _backend.accept_auth_session({
		"access_token": "missing-user-access",
		"refresh_token": "missing-user-refresh",
		"expires_in": 3600,
	})
	_check(not bool(missing_uid.get("ok", false)),
		"payload OAuth tanpa UID sendiri harus ditolak")

	# Build lama sempat menaruh verifier di pending_oauth. Migrasi satu kali harus
	# memindahkannya ke SecureStore tanpa memutus OAuth yang sedang berjalan.
	_state.pending_oauth = {
		"mode": "restore",
		"state": "legacy-state",
		"code_verifier": "legacy-verifier",
		"started_at": 1999999999,
	}
	_state.save()
	_secure.clear_oauth_pkce()
	_state.pending_oauth = {}
	_state.load_state()
	_check(not _state.pending_oauth.has("code_verifier"),
		"migrasi harus menghapus verifier legacy dari state.json")
	_check_eq(_state.oauth_code_verifier("legacy-state"), "legacy-verifier",
		"migrasi harus memindahkan verifier legacy ke SecureStore")
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
