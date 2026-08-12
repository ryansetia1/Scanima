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
	GameState.set_session(access, refresh, int(Time.get_unix_time_from_system()) + umur, user_id)
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
	var res := await get_rest("profiles?select=scan_charges,genesis_cores,bits")
	if res.ok and typeof(res.data) == TYPE_ARRAY and (res.data as Array).size() > 0:
		GameState.profile = GameState.as_dict((res.data as Array)[0])
	return res


func fetch_anima(anima_id: String) -> Dictionary:
	return await get_rest(
		"animas?id=eq.%s&select=id,status,nickname,species_key,color_bucket,stage,element,rarity,base_stats"
		% anima_id.uri_encode()
	)


func fetch_animas() -> Dictionary:
	# owner_id sengaja tidak ikut query. RLS-lah yang membatasi koleksi ke pemain
	# aktif; menduplikasi uid di URL hanya menciptakan pagar kedua yang bisa drift.
	return await get_rest(
		"animas?status=eq.ready"
		+ "&select=id,nickname,species_key,color_bucket,stage,element,rarity,base_stats"
		+ "&order=born_at.desc"
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
		return {"ok": false, "code": code, "data": data, "bytes": raw, "error": message}

	return {"ok": true, "code": code, "data": data, "bytes": raw, "error": ""}


## Sheet PNG dari CDN tidak pernah dicoba jadi JSON. Memaksa 1 MB biner menjadi
## String memberi galat Unicode di log dan menyalin isinya tanpa guna, sementara
## pemanggilnya memakai bytes. Balasan JSON Supabase selalu mulai dengan { atau [.
static func _maybe_json(raw: PackedByteArray) -> bool:
	for byte in raw:
		if byte == 0x20 or byte == 0x09 or byte == 0x0a or byte == 0x0d:
			continue
		return byte == 0x7b or byte == 0x5b
	return false
