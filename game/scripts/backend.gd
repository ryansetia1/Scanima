extends Node

## Transport ke Supabase, dan satu-satunya tempat di client yang tahu URL serta
## kunci project.
##
## Kunci di bawah ini kunci publishable dan memang dirancang ikut ke dalam build:
## yang membatasi akses adalah RLS di server, bukan kerahasiaan kuncinya. Yang
## tidak boleh masuk ke file ini sampai kapan pun adalah REPLICATE_API_TOKEN atau
## service role key, sebab keduanya melewati semua pagar sekaligus.
##
## Semua method di sini await. Pola pemakaiannya:
##
##   var res := await Backend.ensure_session()
##   if not res.ok: ...

const URL_BASE := "https://kgcaisvmmpxswevjvgft.supabase.co"
const KEY_PUBLISHABLE := "sb_publishable_piIQGzH_6YwgNS7EiyOZ_Q_z7WN8NGN"

const TIMEOUT_SEC := 30.0
const ATLAS_THUMB_CACHE_MAX := 96
## create_anima menunggu Vision di dalamnya; terukur 15 detik di produksi.
const TIMEOUT_FUNGSI_SEC := 90.0
## Token hidup satu jam. Diperbarui saat sisanya di bawah angka ini, bukan setelah
## ada request yang gagal, supaya tidak ada panggilan mati di tengah jalan hanya
## karena umur token.
const MARGIN_REFRESH_SEC := 120
## Sinyal mobile putus dalam hitungan detik, bukan menit. Commit turn boleh
## mengulang sendiri sebelum menyerah supaya lift dan terowongan tidak menjadi
## aksi yang hilang; yang diulang hanya kegagalan transport, sebab server yang
## sudah menjawab 4xx berarti sudah memutuskan. Dua ulangan menambah ~6 detik
## saat benar-benar offline, dan itu tertutup animasi dari simulasi lokal.
const RETRY_BACKOFF_SEC := 2.0
const RETRY_BACKOFF_MAX_SEC := 8.0
const TURN_RETRIES := 2
const ANIMA_FIELDS := (
	"id,status,nickname,species_key,color_bucket,stage,subject_kind,element,secondary_element,"
	+ "typing_version,sheet_path,manifest,rarity,base_stats,body_height_cm,"
	+ "strike_name,surge_name,evolution_version,strike_effect_id,surge_effect_id,"
	+ "care,care_score,care_synced_at,sleep_started_at,sleep_energy_at_start,"
	+ "well_cared_on,play_score_on,play_score_today,dormant_since,battle_wins,"
	+ "synthesis_history"
)


# ------------------------------------------------------------------ sesi

## Memastikan ada token yang masih hidup. Dipanggil sebelum apa pun yang lain.
func ensure_session() -> Dictionary:
	if not needs_refresh(GameState.session, int(Time.get_unix_time_from_system())):
		return {"ok": true, "error": ""}
	if GameState.session.is_empty():
		if GameState.device_guest_expected:
			var guest := GameState.device_guest_session()
			if guest.is_empty() or not GameState.activate_stored_session(guest):
				return {"ok": false, "code": 0, "error": "DEVICE_GUEST_RECOVERY_FAILED"}
			if not needs_refresh(GameState.session, int(Time.get_unix_time_from_system())):
				return {"ok": true, "error": ""}
		else:
			return await sign_in_anonymous()
	return await refresh_session()


## Pure, supaya matematika kedaluwarsanya bisa diuji tanpa jaringan.
static func needs_refresh(session: Dictionary, now_unix: int) -> bool:
	if session.is_empty():
		return true
	if str(session.get("access_token", "")).is_empty():
		return true
	return int(session.get("expires_at", 0)) - now_unix <= MARGIN_REFRESH_SEC


## Identitas pemain. Scanima tidak punya layar login: akun dibuat di sini, sekali,
## saat app pertama kali jalan. Trigger handle_new_user di Postgres yang mengisi
## profil beserta saldo awalnya.
func sign_in_anonymous() -> Dictionary:
	var prepared := await request_anonymous_session()
	return _activate_session_candidate(prepared)


## Menyiapkan guest tanpa mengganti sesi aktif. Sign Out setelah transfer memakai
## ini sebelum mencabut Google, jadi kegagalan jaringan tidak meninggalkan app
## tanpa identitas yang bisa dipulihkan.
func request_anonymous_session() -> Dictionary:
	var res := await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/auth/v1/signup",
		_headers(false, ["content-type: application/json"]),
		"{}".to_utf8_buffer(),
		TIMEOUT_SEC
	)
	return _prepare_session_response(res)


func refresh_session() -> Dictionary:
	var prepared := await refresh_session_candidate(GameState.session)
	if not bool(prepared.get("ok", false)):
		# Sengaja TIDAK membuat akun anonim baru di sini. Sign-in baru akan
		# membuat app terlihat pulih sementara seluruh Anima pemain tertinggal di
		# akun yang tidak bisa dijangkau lagi. Gagal yang kelihatan lebih baik
		# daripada kehilangan data yang tidak kelihatan.
		return prepared
	return _activate_session_candidate(prepared)


## Refresh token kandidat tanpa menyentuh GameState. Dipakai untuk membuktikan
## guest perangkat masih hidup sebelum sesi Google lokal dilepas.
func refresh_session_candidate(candidate: Dictionary) -> Dictionary:
	var token := str(candidate.get("refresh_token", ""))
	if token.is_empty():
		return {"ok": false, "code": 0, "data": null, "error": "sesi tanpa refresh token"}
	var res := await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/auth/v1/token?grant_type=refresh_token",
		_headers(false, ["content-type: application/json"]),
		JSON.stringify({"refresh_token": token}).to_utf8_buffer(),
		TIMEOUT_SEC
	)
	return _prepare_session_response(res, str(candidate.get("uid", "")))


func sign_out_local() -> Dictionary:
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/auth/v1/logout?scope=local",
		_headers(true),
		PackedByteArray(),
		TIMEOUT_SEC,
		1
	)


func _prepare_session_response(res: Dictionary, fallback_uid: String = "") -> Dictionary:
	if not bool(res.get("ok", false)):
		return res
	var prepared := _normalize_session(res.get("data"), fallback_uid)
	if not bool(prepared.get("ok", false)):
		return prepared
	prepared["code"] = int(res.get("code", 200))
	return prepared


func _normalize_session(data: Variant, fallback_uid: String = "") -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "code": 0, "data": data, "error": "balasan auth bukan object"}
	var body: Dictionary = data
	var access := str(body.get("access_token", ""))
	var refresh := str(body.get("refresh_token", ""))
	var user: Dictionary = GameState.as_dict(body.get("user"))
	var user_id := str(user.get("id", fallback_uid))
	if access.is_empty() or refresh.is_empty() or user_id.is_empty():
		return {"ok": false, "code": 0, "data": data, "error": "balasan auth tidak lengkap"}
	return {
		"ok": true,
		"code": 200,
		"data": data,
		"session": {
			"access_token": access,
			"refresh_token": refresh,
			"expires_at": int(Time.get_unix_time_from_system()) + int(body.get("expires_in", 3600)),
			"uid": user_id,
			"is_anonymous": bool(user.get("is_anonymous", false)),
		},
		"error": "",
	}


func _activate_session_candidate(prepared: Dictionary) -> Dictionary:
	if not bool(prepared.get("ok", false)):
		return prepared
	if not GameState.activate_stored_session(GameState.as_dict(prepared.get("session"))):
		return {
			"ok": false, "code": 0, "data": prepared.get("data"),
			"error": "secure session storage unavailable",
		}
	return prepared


func _store_session(data: Variant) -> Dictionary:
	return _activate_session_candidate(_normalize_session(data))


# ------------------------------------------------------------------ data

## GET ke PostgREST. Yang membatasi barisnya RLS, jadi tidak ada filter owner_id
## di sini: menambahkannya hanya menduplikasi pagar yang sudah berdiri.
func get_rest(path_and_query: String) -> Dictionary:
	return await _send(
		HTTPClient.METHOD_GET,
		"%s/rest/v1/%s" % [URL_BASE, path_and_query],
		_headers(true),
		PackedByteArray(),
		TIMEOUT_SEC
	)


func fetch_profile() -> Dictionary:
	var previous_cores := int(GameState.profile.get("genesis_cores", -1))
	var res := await seeker("profile")
	if res.ok and typeof(res.data) == TYPE_DICTIONARY:
		GameState.profile = GameState.as_dict(res.data)
		var config := GameState.as_dict(GameState.profile.get("client_config"))
		if not config.is_empty():
			GameState.client_config = config
		GameState.profile.erase("client_config")
		res["previous_genesis_cores"] = previous_cores
	elif res.code == 426 and typeof(res.data) == TYPE_DICTIONARY:
		var minimums := GameState.as_dict(GameState.as_dict(res.data).get("min_client_version"))
		if not minimums.is_empty():
			GameState.client_config = {"min_client_version": minimums}
	return res


func fetch_client_config() -> Dictionary:
	if not GameState.client_config.is_empty():
		return {"ok": true, "data": GameState.client_config, "error": ""}
	var profile := await fetch_profile()
	if not profile.ok or GameState.client_config.is_empty():
		return {"ok": false, "data": {}, "error": profile.error}
	return {"ok": true, "data": GameState.client_config, "error": ""}


func fetch_anima(anima_id: String) -> Dictionary:
	return await get_rest(
		"animas?id=eq.%s&select=%s" % [anima_id.uri_encode(), ANIMA_FIELDS]
	)


func fetch_animas() -> Dictionary:
	# owner_id sengaja tidak ikut query. RLS-lah yang membatasi koleksi ke pemain
	# aktif; menduplikasi uid di URL hanya menciptakan pagar kedua yang bisa drift.
	return await get_rest(
		"animas?status=in.(ready,evolving)"
		+ "&select=" + ANIMA_FIELDS
		+ "&order=born_at.desc"
	)


func evolve_anima(
	anima_id: String,
	idempotency_key: String,
	resume_only: bool = false
) -> Dictionary:
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/evolve_anima",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify({
			"anima_id": anima_id,
			"idempotency_key": idempotency_key,
			"resume_only": resume_only,
		}).to_utf8_buffer(),
		TIMEOUT_FUNGSI_SEC
	)


## Read-only, jadi ia sengaja tidak menerima idempotency key: membaca silsilah
## bentuk tidak pernah membelanjakan Core, Bits, atau panggilan model.
func evolution_history(anima_id: String) -> Dictionary:
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/evolve_anima",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify({
			"anima_id": anima_id,
			"operation": "history",
		}).to_utf8_buffer(),
		TIMEOUT_FUNGSI_SEC
	)


func synthesize_anima(operation: String, payload: Dictionary = {}) -> Dictionary:
	var body := payload.duplicate(true)
	body["operation"] = operation
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/synthesize_anima",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(),
		TIMEOUT_FUNGSI_SEC if operation in ["attempt", "resume"] else TIMEOUT_SEC
	)


func rename_anima(anima_id: String, nickname: String) -> Dictionary:
	return await _send(
		HTTPClient.METHOD_PATCH,
		"%s/rest/v1/animas?id=eq.%s&select=id,nickname" % [URL_BASE, anima_id.uri_encode()],
		_headers(true, ["content-type: application/json", "Prefer: return=representation"]),
		JSON.stringify({"nickname": nickname}).to_utf8_buffer(),
		TIMEOUT_SEC
	)


func delete_anima(anima_id: String) -> Dictionary:
	return await _send(
		HTTPClient.METHOD_DELETE,
		"%s/rest/v1/animas?id=eq.%s&select=id" % [URL_BASE, anima_id.uri_encode()],
		_headers(true, ["Prefer: return=representation"]),
		PackedByteArray(),
		TIMEOUT_SEC
	)


func fetch_species_art(species_key: String, color_bucket: String, stage: int) -> Dictionary:
	return await get_rest(
		"species_library?species_key=eq.%s&color_bucket=eq.%s&stage=eq.%d&select=sheet_path,manifest"
		% [species_key.uri_encode(), color_bucket.uri_encode(), stage]
	)


# ------------------------------------------------------------------ foto & art

## Menulis langsung ke bucket photos. Tidak ada endpoint unggah di server, dan
## tidak perlu: policy Storage menuntut foldernya bernama uid pemain sendiri, dan
## bucket menegakkan batas ukuran serta tipe.
##
## 409 diperlakukan sebagai berhasil. Itu yang terjadi saat scan dilanjutkan
## setelah app mati: fotonya sudah ada di sana dari percobaan sebelumnya, dan
## bucket ini sengaja tidak memberi hak menimpa.
func upload_photo(object_path: String, bytes: PackedByteArray, mime: String) -> Dictionary:
	var res := await _send(
		HTTPClient.METHOD_POST,
		"%s/storage/v1/object/photos/%s" % [URL_BASE, object_path],
		_headers(true, ["content-type: " + mime]),
		bytes,
		TIMEOUT_SEC
	)
	if not res.ok and res.code == 409:
		return {"ok": true, "code": 409, "data": res.data, "error": "", "bytes": PackedByteArray()}
	return res


## Bucket sheets publik supaya art datang dari CDN, bukan lewat Postgres.
func download_sheet(sheet_path: String) -> Dictionary:
	return await _send(
		HTTPClient.METHOD_GET,
		"%s/storage/v1/object/public/sheets/%s" % [URL_BASE, sheet_path.uri_encode()],
		_headers(false),
		PackedByteArray(),
		TIMEOUT_SEC
	)


## Bucket anima_sheets privat — hanya prefix uid pemain sendiri (RLS Storage).
func download_anima_sheet(sheet_path: String) -> Dictionary:
	if sheet_path.is_empty():
		return {"ok": false, "code": 0, "data": null, "bytes": PackedByteArray(), "error": "sheet_path kosong"}
	return await _send(
		HTTPClient.METHOD_GET,
		"%s/storage/v1/object/authenticated/anima_sheets/%s" % [URL_BASE, sheet_path.uri_encode()],
		_headers(true),
		PackedByteArray(),
		TIMEOUT_SEC
	)


# ------------------------------------------------------------------ fungsi

func create_anima(
	photo_path: String,
	idempotency_key: String,
	nickname := "",
	capture_vibe := ""
) -> Dictionary:
	var body := {
		"photo_path": photo_path,
		"idempotency_key": idempotency_key,
		"capture_vibe": ScanView.normalize_vibe(capture_vibe),
	}
	if not nickname.is_empty():
		body["nickname"] = nickname
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/create_anima",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(),
		TIMEOUT_FUNGSI_SEC
	)


func timezone_offset_minutes() -> int:
	return clampi(int(Time.get_time_zone_from_system().get("bias", 0)), -840, 840)


func care_anima(
	anima_id: String,
	action: String,
	idempotency_key := "",
	item_id := ""
) -> Dictionary:
	var body := {
		"anima_id": anima_id,
		"action": action,
		"timezone_offset_minutes": timezone_offset_minutes(),
	}
	if not idempotency_key.is_empty():
		body["idempotency_key"] = idempotency_key
	if not item_id.is_empty():
		body["item_id"] = item_id
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/care_anima",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(),
		TIMEOUT_SEC
	)


func fetch_catalog() -> Dictionary:
	return await get_rest("catalog_items?select=id,kind,use_type,name_key,price,effect,effect_value,sprite_sheet,sprite_index&active=eq.true&order=kind.asc,sprite_index.asc")


func fetch_inventory() -> Dictionary:
	return await get_rest("player_inventory?select=item_id,quantity")


func purchase_item(item_id: String, expected_price: int, idempotency_key: String) -> Dictionary:
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/shop",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify({
			"item_id": item_id,
			"expected_price": expected_price,
			"idempotency_key": idempotency_key,
		}).to_utf8_buffer(),
		TIMEOUT_SEC
	)


func battle_anima(operation: String, payload: Dictionary = {}) -> Dictionary:
	var body := payload.duplicate(true)
	body["operation"] = operation
	body["timezone_offset_minutes"] = timezone_offset_minutes()
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/battle_anima",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(),
		TIMEOUT_SEC,
		turn_retries(operation)
	)


func team_battle(operation: String, payload: Dictionary = {}) -> Dictionary:
	var body := payload.duplicate(true)
	body["operation"] = operation
	body["timezone_offset_minutes"] = timezone_offset_minutes()
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/team_battle",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(),
		TIMEOUT_SEC,
		turn_retries(operation)
	)


func expedition(operation: String, payload: Dictionary = {}) -> Dictionary:
	var body := payload.duplicate(true)
	body["operation"] = operation
	body["timezone_offset_minutes"] = timezone_offset_minutes()
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/expedition",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(),
		TIMEOUT_SEC,
		turn_retries(operation)
	)


## Hanya commit turn yang boleh mengulang sendiri. Ia idempoten lewat
## `idempotency_key`, animasinya sudah jalan dari simulasi lokal, dan gagalnya
## berarti pemain kehilangan aksi yang sudah dilihatnya terjadi. Operasi lain
## (start, resume, forfeit, katalog) lebih baik gagal cepat lalu ditawarkan lagi.
static func turn_retries(operation: String) -> int:
	return TURN_RETRIES if operation == "turn" else 0


func seeker(operation: String, payload: Dictionary = {}) -> Dictionary:
	var body := payload.duplicate(true)
	body["operation"] = operation
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/seeker",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(),
		TIMEOUT_SEC
	)


func atlas(operation: String, payload: Dictionary = {}) -> Dictionary:
	var body := payload.duplicate(true)
	body["operation"] = operation
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/functions/v1/gallery",
		_headers(true, ["content-type: application/json"]),
		JSON.stringify(body).to_utf8_buffer(),
		TIMEOUT_FUNGSI_SEC if operation == "publish" else TIMEOUT_SEC
	)


func download_url(url: String) -> Dictionary:
	if url.is_empty():
		return {"ok": false, "code": 0, "data": null, "bytes": PackedByteArray(), "error": "url kosong"}
	return await _send(
		HTTPClient.METHOD_GET,
		url,
		PackedStringArray(),
		PackedByteArray(),
		TIMEOUT_SEC
	)


static func atlas_thumb_cache_path(form_id: String) -> String:
	return "user://atlas_thumbs/%s.png" % form_id


static func store_atlas_thumb(form_id: String, bytes: PackedByteArray) -> Dictionary:
	if form_id.is_empty() or bytes.is_empty():
		return {"ok": false, "error": "thumb kosong"}
	var dir := DirAccess.open("user://")
	if dir == null:
		return {"ok": false, "error": "cache dir gagal"}
	if not dir.dir_exists("atlas_thumbs"):
		var mk := dir.make_dir("atlas_thumbs")
		if mk != OK:
			return {"ok": false, "error": "cache dir gagal dibuat"}
	var path := atlas_thumb_cache_path(form_id)
	if not FileAccess.file_exists(path):
		var files := DirAccess.get_files_at("user://atlas_thumbs")
		while files.size() >= ATLAS_THUMB_CACHE_MAX:
			var oldest := ""
			var oldest_time := 9223372036854775807
			for filename in files:
				var candidate := "user://atlas_thumbs".path_join(filename)
				var modified := FileAccess.get_modified_time(candidate)
				if modified < oldest_time:
					oldest_time = modified
					oldest = filename
			if oldest.is_empty():
				break
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path("user://atlas_thumbs".path_join(oldest))
			)
			files.remove_at(files.find(oldest))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cache write gagal"}
	file.store_buffer(bytes)
	file.close()
	return {"ok": true, "error": ""}


func oauth_authorize(link_identity: bool, redirect_to: String, code_challenge: String) -> Dictionary:
	var endpoint := "/auth/v1/user/identities/authorize" if link_identity else "/auth/v1/authorize"
	var query := (
		"?provider=google"
		+ "&redirect_to=" + redirect_to.uri_encode()
		+ "&scopes=" + "openid email profile".uri_encode()
		+ "&code_challenge=" + code_challenge.uri_encode()
		+ "&code_challenge_method=s256"
		+ "&prompt=select_account"
		+ "&skip_http_redirect=true"
	)
	var auth_url := URL_BASE + endpoint + query
	# Sign-in biasa tidak perlu request awal: browser harus membuka endpoint
	# authorize dan mengikuti redirect provider. Link tetap di-fetch karena
	# endpoint-nya memerlukan bearer guest dan mengembalikan URL sebagai JSON.
	if not link_identity:
		return {
			"ok": true, "code": 0, "data": {"url": auth_url},
			"bytes": PackedByteArray(), "error": "",
		}
	return await _send(
		HTTPClient.METHOD_GET,
		auth_url,
		_headers(true),
		PackedByteArray(),
		TIMEOUT_SEC
	)


func exchange_oauth_code(auth_code: String, code_verifier: String) -> Dictionary:
	return await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/auth/v1/token?grant_type=pkce",
		_headers(false, ["content-type: application/json"]),
		JSON.stringify({
			"auth_code": auth_code,
			"code_verifier": code_verifier,
		}).to_utf8_buffer(),
		TIMEOUT_SEC
	)


func accept_auth_session(data: Variant) -> Dictionary:
	return _store_session(data)


# ------------------------------------------------------------------ transport

func _headers(authed: bool, extra: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var headers: PackedStringArray = [
		"apikey: " + KEY_PUBLISHABLE,
		"x-scanima-platform: " + ClientVersion.platform_key(),
		"x-scanima-build: " + str(ClientVersion.APP_BUILD_VERSION),
	]
	if authed:
		headers.append("Authorization: Bearer " + str(GameState.session.get("access_token", "")))
	headers.append_array(extra)
	return headers


## Satu HTTPRequest per panggilan, lalu dibuang. HTTPRequest hanya bisa melayani
## satu request sekaligus, dan node sekali pakai lebih murah daripada antrean
## sendiri plus bug re-entrancy yang datang bersamanya.
func _send(
	method: int,
	url: String,
	headers: PackedStringArray,
	body: PackedByteArray,
	timeout: float,
	retries := 0
) -> Dictionary:
	var expected_uid := GameState.uid() if _has_authorization(headers) else ""
	var response := await _send_attempt(method, url, headers, body, timeout, expected_uid)
	var delay := RETRY_BACKOFF_SEC
	var left := retries
	while left > 0 and bool(response.get("transport", false)):
		await get_tree().create_timer(delay).timeout
		delay = minf(delay * 2.0, RETRY_BACKOFF_MAX_SEC)
		left -= 1
		response = await _send_attempt(method, url, headers, body, timeout, expected_uid)
	return response


func _send_attempt(
	method: int,
	url: String,
	headers: PackedStringArray,
	body: PackedByteArray,
	timeout: float,
	expected_uid: String = ""
) -> Dictionary:
	var authenticated := _has_authorization(headers)
	if authenticated and GameState.uid() != expected_uid:
		return _stale_account_response()
	var outgoing_headers := headers
	if authenticated:
		var session_result := await ensure_session()
		if not bool(session_result.get("ok", false)):
			return session_result
		if GameState.uid() != expected_uid:
			return _stale_account_response()
		outgoing_headers = _with_access_token(
			headers,
			str(GameState.session.get("access_token", ""))
		)

	var response := await _send_once(method, url, outgoing_headers, body, timeout)
	if authenticated and GameState.uid() != expected_uid:
		return _stale_account_response()
	if not authenticated or int(response.get("code", 0)) != 401:
		return response

	# Token bisa dicabut server walau expires_at lokal belum dekat. Satu refresh
	# dan satu retry cukup; request berbiaya punya idempotency key sendiri.
	var refresh_result := await refresh_session()
	if not bool(refresh_result.get("ok", false)):
		return response
	if GameState.uid() != expected_uid:
		return _stale_account_response()
	var retried := await _send_once(
		method,
		url,
		_with_access_token(headers, str(GameState.session.get("access_token", ""))),
		body,
		timeout
	)
	return _stale_account_response() if GameState.uid() != expected_uid else retried


static func _stale_account_response() -> Dictionary:
	return {
		"ok": false, "code": 0, "data": null, "bytes": PackedByteArray(),
		"error": "STALE_ACCOUNT_RESPONSE", "stale": true,
	}


static func response_applies(response: Dictionary, expected_epoch: int) -> bool:
	return (
		not bool(response.get("stale", false))
		and GameState.session_epoch == expected_epoch
	)


func _send_once(
	method: int,
	url: String,
	headers: PackedStringArray,
	body: PackedByteArray,
	timeout: float
) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)

	var started := http.request_raw(url, headers, method, body)
	if started != OK:
		http.queue_free()
		return {
			"ok": false, "code": 0, "data": null, "bytes": PackedByteArray(),
			"error": "request tidak bisa dimulai: %s" % error_string(started),
			"transport": true,
		}

	var res: Array = await http.request_completed
	http.queue_free()

	var result := int(res[0])
	var code := int(res[1])
	var raw: PackedByteArray = res[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false, "code": code, "data": null, "bytes": raw,
			"error": "jaringan gagal (result %d, http %d)" % [result, code],
			"transport": true,
		}

	var text := ""
	var data: Variant = null
	if _maybe_json(raw):
		text = raw.get_string_from_utf8()
		data = GameState.parse_json(text)

	if code >= 400:
		# Pesan dari server dipertahankan apa adanya. Kode seperti NO_CORE dan
		# SPEND_CAP adalah kontrak, bukan teks bebas, dan pemanggil membacanya.
		var message := text if not text.is_empty() else "http %d" % code
		if typeof(data) == TYPE_DICTIONARY:
			var dict: Dictionary = data
			message = str(dict.get("error", dict.get("msg", dict.get("message", text))))
		if code == 401:
			message = "AUTH_EXPIRED"
		return {"ok": false, "code": code, "data": data, "bytes": raw, "error": message}

	return {"ok": true, "code": code, "data": data, "bytes": raw, "error": ""}


static func _has_authorization(headers: PackedStringArray) -> bool:
	for header in headers:
		if header.strip_edges().to_lower().begins_with("authorization:"):
			return true
	return false


static func _with_access_token(headers: PackedStringArray, access_token: String) -> PackedStringArray:
	var refreshed := PackedStringArray()
	for header in headers:
		if not header.strip_edges().to_lower().begins_with("authorization:"):
			refreshed.append(header)
	refreshed.append("Authorization: Bearer " + access_token)
	return refreshed


## Sheet PNG dari CDN tidak pernah dicoba jadi JSON. Memaksa 1 MB biner menjadi
## String memberi galat Unicode di log dan menyalin isinya tanpa guna, sementara
## pemanggilnya memakai bytes. Balasan JSON Supabase selalu mulai dengan { atau [.
static func _maybe_json(raw: PackedByteArray) -> bool:
	for byte in raw:
		if byte == 0x20 or byte == 0x09 or byte == 0x0a or byte == 0x0d:
			continue
		return byte == 0x7b or byte == 0x5b
	return false
