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
## create_anima menunggu Vision di dalamnya; terukur 15 detik di produksi.
const TIMEOUT_FUNGSI_SEC := 90.0
## Token hidup satu jam. Diperbarui saat sisanya di bawah angka ini, bukan setelah
## ada request yang gagal, supaya tidak ada panggilan mati di tengah jalan hanya
## karena umur token.
const MARGIN_REFRESH_SEC := 120
const ANIMA_FIELDS := (
	"id,status,nickname,species_key,color_bucket,stage,element,rarity,base_stats,"
	+ "strike_name,surge_name,"
	+ "care,care_score,care_synced_at,sleep_started_at,sleep_energy_at_start,"
	+ "well_cared_on,play_score_on,play_score_today,dormant_since,battle_wins"
)


# ------------------------------------------------------------------ sesi

## Memastikan ada token yang masih hidup. Dipanggil sebelum apa pun yang lain.
func ensure_session() -> Dictionary:
	if not needs_refresh(GameState.session, int(Time.get_unix_time_from_system())):
		return {"ok": true, "error": ""}
	if GameState.session.is_empty():
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
	var res := await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/auth/v1/signup",
		_headers(false, ["content-type: application/json"]),
		"{}".to_utf8_buffer(),
		TIMEOUT_SEC
	)
	if not res.ok:
		return res
	return _store_session(res.data)


func refresh_session() -> Dictionary:
	var token := str(GameState.session.get("refresh_token", ""))
	if token.is_empty():
		return {"ok": false, "code": 0, "data": null, "error": "sesi tanpa refresh token"}

	var res := await _send(
		HTTPClient.METHOD_POST,
		URL_BASE + "/auth/v1/token?grant_type=refresh_token",
		_headers(false, ["content-type: application/json"]),
		JSON.stringify({"refresh_token": token}).to_utf8_buffer(),
		TIMEOUT_SEC
	)
	if not res.ok:
		# Sengaja TIDAK membuat akun anonim baru di sini. Sign-in baru akan
		# membuat app terlihat pulih sementara seluruh Anima pemain tertinggal di
		# akun yang tidak bisa dijangkau lagi. Gagal yang kelihatan lebih baik
		# daripada kehilangan data yang tidak kelihatan.
		return res
	return _store_session(res.data)


func _store_session(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "code": 0, "data": data, "error": "balasan auth bukan object"}
	var body: Dictionary = data
	var access := str(body.get("access_token", ""))
	var refresh := str(body.get("refresh_token", ""))
	var user: Dictionary = GameState.as_dict(body.get("user"))
	var user_id := str(user.get("id", GameState.uid()))
	if access.is_empty() or refresh.is_empty() or user_id.is_empty():
		return {"ok": false, "code": 0, "data": data, "error": "balasan auth tidak lengkap"}

	var umur := int(body.get("expires_in", 3600))
	if not GameState.set_session(
		access,
		refresh,
		int(Time.get_unix_time_from_system()) + umur,
		user_id,
		bool(user.get("is_anonymous", false))
	):
		return {"ok": false, "code": 0, "data": data, "error": "secure session storage unavailable"}
	return {"ok": true, "code": 200, "data": data, "error": ""}


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
	var res := await get_rest(
		"profiles?select=scan_charges,genesis_cores,bits,active_anima_id,"
		+ "seeker_name,seeker_name_changed_at,seeker_xp,guest_scan_used_at,"
		+ "account_upgraded_at,battle_victories,birth_year,gender,created_at"
	)
	if res.ok and typeof(res.data) == TYPE_ARRAY and (res.data as Array).size() > 0:
		GameState.profile = GameState.as_dict((res.data as Array)[0])
	return res


func fetch_anima(anima_id: String) -> Dictionary:
	return await get_rest(
		"animas?id=eq.%s&select=%s" % [anima_id.uri_encode(), ANIMA_FIELDS]
	)


func fetch_animas() -> Dictionary:
	# owner_id sengaja tidak ikut query. RLS-lah yang membatasi koleksi ke pemain
	# aktif; menduplikasi uid di URL hanya menciptakan pagar kedua yang bisa drift.
	return await get_rest(
		"animas?status=eq.ready"
		+ "&select=" + ANIMA_FIELDS
		+ "&order=born_at.desc"
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


# ------------------------------------------------------------------ fungsi

func create_anima(photo_path: String, idempotency_key: String, nickname := "") -> Dictionary:
	var body := {"photo_path": photo_path, "idempotency_key": idempotency_key}
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
		TIMEOUT_SEC
	)


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


func oauth_authorize(link_identity: bool, redirect_to: String, code_challenge: String) -> Dictionary:
	var endpoint := "/auth/v1/user/identities/authorize" if link_identity else "/auth/v1/authorize"
	var query := (
		"?provider=google"
		+ "&redirect_to=" + redirect_to.uri_encode()
		+ "&scopes=" + "openid email profile".uri_encode()
		+ "&code_challenge=" + code_challenge.uri_encode()
		+ "&code_challenge_method=s256"
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
	var headers: PackedStringArray = ["apikey: " + KEY_PUBLISHABLE]
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
	timeout: float
) -> Dictionary:
	var authenticated := _has_authorization(headers)
	var outgoing_headers := headers
	if authenticated:
		var session_result := await ensure_session()
		if not bool(session_result.get("ok", false)):
			return session_result
		outgoing_headers = _with_access_token(
			headers,
			str(GameState.session.get("access_token", ""))
		)

	var response := await _send_once(method, url, outgoing_headers, body, timeout)
	if not authenticated or int(response.get("code", 0)) != 401:
		return response

	# Token bisa dicabut server walau expires_at lokal belum dekat. Satu refresh
	# dan satu retry cukup; request berbiaya punya idempotency key sendiri.
	var refresh_result := await refresh_session()
	if not bool(refresh_result.get("ok", false)):
		return response
	return await _send_once(
		method,
		url,
		_with_access_token(headers, str(GameState.session.get("access_token", ""))),
		body,
		timeout
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
