extends Node

## Satu-satunya pemilik state yang bertahan antar sesi aplikasi.
##
## Yang disimpan di JSON hanya UID, preference, dan intent yang tidak aman
## direkonstruksi. Token hidup di SecureStore (Keystore/Keychain), sedangkan
## saldo, kebutuhan, dan roster selalu dibaca ulang dari server.
##
## Sesi adalah satu-satunya bukti kepemilikan akun. Pemain anonim tidak punya
## email maupun password, jadi file ini hilang atau rusak sama dengan kehilangan
## seluruh Anima tanpa cara memulihkan. Itu alasan penulisannya atomik, bukan
## kehati-hatian yang berlebihan.

## Bukan const supaya uji bisa menunjuk folder sementara, bukan state pemain.
var path_state: String = "user://state.json"
var dir_animas: String = "user://animas"

## Runtime saja: {access_token, refresh_token, expires_at, uid, is_anonymous}.
var session: Dictionary = {}

## {idempotency_key, photo_path, generation_id, anima_id}. Lihat begin_scan().
var pending_scan: Dictionary = {}

## {idempotency_key, anima_id, action, item_id}. Dipertahankan sampai server mengonfirmasi
## supaya retry Feed/Clean tidak mendebit Bits dua kali.
var pending_care: Dictionary = {}

## {session_id, expected_turn, expected_version, action, item_id, idempotency_key}.
## Session tetap disimpan saat tidak ada action supaya app bisa resume; key action
## dipertahankan saat timeout supaya turn dan reward tidak pernah commit dua kali.
var pending_battle: Dictionary = {}

## {idempotency_key, item_id, expected_price}. Satu pembelian menggantung.
var pending_purchase: Dictionary = {}

## {mode, state, code_verifier, started_at}. Sesi guest tetap aktif sampai
## exchange berhasil, dan backup token disimpan terpisah di SecureStore.
var pending_oauth: Dictionary = {}

## Preference lokal yang aman dipersist, saat ini hanya Reduced Motion.
var preferences: Dictionary = {"reduced_motion": false}

## Anima terakhir yang berhasil dimuat, supaya app bisa langsung menampilkannya
## saat dibuka lagi tanpa menunggu jaringan sama sekali.
var last_anima: Dictionary = {}

## Saldo dari server. Ditampilkan, tidak pernah dipercaya, tidak pernah disimpan.
var profile: Dictionary = {}


func _ready() -> void:
	load_state()


func uid() -> String:
	return str(session.get("uid", ""))


func load_state() -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists(path_state):
		# JSON.new().parse(), bukan JSON.parse_string(): yang kedua mencetak galat
		# parser engine ke log setiap kali file rusak.
		var parsed: Variant = parse_json(FileAccess.get_file_as_string(path_state))
		if typeof(parsed) != TYPE_DICTIONARY:
			# Jangan hapus file rusak: ia mungkin masih dapat dipulihkan manual.
			push_error("state tidak terbaca, diabaikan: %s" % path_state)
		else:
			data = parsed
	pending_scan = as_dict(data.get("pending_scan"))
	pending_care = as_dict(data.get("pending_care"))
	pending_battle = as_dict(data.get("pending_battle"))
	pending_purchase = as_dict(data.get("pending_purchase"))
	pending_oauth = as_dict(data.get("pending_oauth"))
	preferences.merge(as_dict(data.get("preferences")), true)
	last_anima = as_dict(data.get("last_anima"))

	var legacy_session := as_dict(data.get("session"))
	var store := _secure_store()
	var stored: Dictionary = store.load_session() if store != null else {}
	if not stored.is_empty():
		session = stored
	elif legacy_session.has("access_token"):
		# Migrasi satu kali dari build lama. save() berikutnya menghapus token dari
		# state.json setelah blob aman berhasil ditulis.
		if store != null and store.save_session(legacy_session):
			session = legacy_session
			save()
		elif not OS.has_feature("android") and not OS.has_feature("ios"):
			session = legacy_session
	else:
		session = legacy_session


func save() -> void:
	var payload := {
		"session": {"uid": uid()} if not uid().is_empty() else {},
		"pending_scan": pending_scan,
		"pending_care": pending_care,
		"pending_battle": pending_battle,
		"pending_purchase": pending_purchase,
		"pending_oauth": pending_oauth,
		"preferences": preferences,
		"last_anima": last_anima,
	}
	var tmp := path_state + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("tidak bisa menulis %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	# Tulis ke file sementara lalu rename, bukan menimpa langsung: app yang mati
	# di tengah penulisan meninggalkan JSON terpotong, dan JSON terpotong di file
	# ini berarti akun pemain lenyap.
	var err := DirAccess.rename_absolute(tmp, path_state)
	if err != OK:
		push_error("gagal memindahkan state sementara: %s" % error_string(err))


func set_session(
	access_token: String,
	refresh_token: String,
	expires_at: int,
	user_id: String,
	anonymous: bool = true
) -> bool:
	var new_session := {
		"access_token": access_token,
		"refresh_token": refresh_token,
		"expires_at": expires_at,
		"uid": user_id,
		"is_anonymous": anonymous,
	}
	var store := _secure_store()
	if store == null or not store.save_session(new_session):
		push_error("sesi tidak bisa ditulis ke SecureStore")
		return false
	session = new_session
	save()
	return true


func is_anonymous() -> bool:
	return bool(session.get("is_anonymous", true))


func begin_oauth(mode: String, state: String, code_verifier: String) -> void:
	var store := _secure_store()
	if store != null:
		store.backup_session(session)
	pending_oauth = {
		"mode": mode,
		"state": state,
		"code_verifier": code_verifier,
		"started_at": int(Time.get_unix_time_from_system()),
	}
	save()


func finish_oauth() -> void:
	pending_oauth = {}
	var store := _secure_store()
	if store != null:
		store.clear_backup()
	save()


func cancel_oauth(restore_backup: bool = false) -> void:
	var store := _secure_store()
	if restore_backup and store != null:
		var backup: Dictionary = store.load_backup()
		if not backup.is_empty():
			session = backup
			store.save_session(session)
	pending_oauth = {}
	if store != null:
		store.clear_backup()
	save()


func clear_account_state() -> void:
	session = {}
	pending_scan = {}
	pending_care = {}
	pending_battle = {}
	pending_purchase = {}
	pending_oauth = {}
	last_anima = {}
	profile = {}
	var store := _secure_store()
	if store != null:
		store.clear_session()
		store.clear_backup()
	save()


func discard_guest_local_state() -> void:
	# Restore akun yang sudah ada tidak menggabungkan intent atau pilihan guest
	# dari instalasi ini. Preference device tetap dipertahankan.
	pending_scan = {}
	pending_care = {}
	pending_battle = {}
	pending_purchase = {}
	last_anima = {}
	profile = {}
	save()


func set_reduced_motion(enabled: bool) -> void:
	preferences["reduced_motion"] = enabled
	save()


func reduced_motion() -> bool:
	return bool(preferences.get("reduced_motion", false))


func _secure_store() -> Node:
	# --script dikompilasi sebelum autoload resmi masuk tree, tetapi node sibling
	# sudah dipasang di root. get_parent() menjaga test dan startup frame pertama
	# tetap memakai secure store tanpa bergantung pada SceneTree node ini.
	var parent := get_parent()
	if parent != null:
		return parent.get_node_or_null("SecureStore")
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("SecureStore") if tree != null else null


## Kunci idempotency dibuat SEKALI per scan dan bertahan sampai scan itu selesai,
## termasuk melewati app yang mati di tengah jalan. Kunci baru untuk foto yang
## sama berarti Genesis Core kedua terdebit untuk satu Anima yang sama.
##
## Nama file fotonya sengaja diturunkan dari kunci itu, jadi scan yang dilanjutkan
## otomatis menunjuk objek yang sama tanpa perlu menyimpan dua hal.
func begin_scan(extension: String) -> Dictionary:
	var key := "%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	pending_scan = {
		"idempotency_key": key,
		"photo_path": "%s/%s.%s" % [uid(), key, extension],
		"generation_id": "",
		"anima_id": "",
	}
	save()
	return pending_scan


func note_scan_started(generation_id: String, anima_id: String) -> void:
	if pending_scan.is_empty():
		return
	pending_scan["generation_id"] = generation_id
	pending_scan["anima_id"] = anima_id
	save()


func finish_scan() -> void:
	pending_scan = {}
	save()


func begin_care(anima_id: String, action: String, item_id: String = "") -> Dictionary:
	if not pending_care.is_empty():
		return pending_care
	var key := "%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	pending_care = {
		"idempotency_key": key,
		"anima_id": anima_id,
		"action": action,
		"item_id": item_id,
	}
	save()
	return pending_care


func finish_care() -> void:
	pending_care = {}
	save()


func remember_battle(session_id: String, expected_turn: int, expected_version: int) -> void:
	pending_battle = {
		"session_id": session_id,
		"expected_turn": expected_turn,
		"expected_version": expected_version,
		"action": "",
		"item_id": "",
		"idempotency_key": "",
	}
	save()


func begin_battle_action(
	session_id: String,
	expected_turn: int,
	expected_version: int,
	action: String,
	item_id: String = ""
) -> Dictionary:
	if not str(pending_battle.get("action", "")).is_empty():
		return pending_battle
	var key := "%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	pending_battle = {
		"session_id": session_id,
		"expected_turn": expected_turn,
		"expected_version": expected_version,
		"action": action,
		"item_id": item_id,
		"idempotency_key": key,
	}
	save()
	return pending_battle


func confirm_battle_response(session_data: Dictionary) -> void:
	if str(session_data.get("status", "")) == "active":
		remember_battle(
			str(session_data.get("id", "")),
			int(session_data.get("turn_number", 1)),
			int(session_data.get("version", 1))
		)
	else:
		finish_battle()


func finish_battle() -> void:
	pending_battle = {}
	save()


func begin_purchase(item_id: String, expected_price: int) -> Dictionary:
	if not pending_purchase.is_empty():
		return pending_purchase
	var key := "%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	pending_purchase = {
		"idempotency_key": key,
		"item_id": item_id,
		"expected_price": expected_price,
	}
	save()
	return pending_purchase


func finish_purchase() -> void:
	pending_purchase = {}
	save()


## Folder cache per varian art. Kuncinya sama dengan kunci pustaka di server
## (species_key, color_bucket, stage), jadi dua Anima yang berbagi art memakai
## satu salinan file di device.
func sprite_dir(species_key: String, color_bucket: String, stage: int) -> String:
	return dir_animas.path_join("%s_%s_%d" % [species_key, color_bucket, stage])


func manifest_path(species_key: String, color_bucket: String, stage: int) -> String:
	return sprite_dir(species_key, color_bucket, stage).path_join("manifest.json")


func has_sprite(species_key: String, color_bucket: String, stage: int) -> bool:
	var path := manifest_path(species_key, color_bucket, stage)
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = parse_json(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var sheet := str(as_dict(parsed).get("sheet", ""))
	if sheet.is_empty():
		return false
	return FileAccess.file_exists(sprite_dir(species_key, color_bucket, stage).path_join(sheet))


## Menyimpan sheet + manifest supaya AnimaLoader bisa memuatnya dari disk apa
## adanya, tanpa jalur kode kedua khusus art yang datang dari jaringan.
##
## Manifest ditulis TERAKHIR. Kalau proses mati di tengah, has_sprite() melihat
## cache yang belum lengkap sebagai tidak ada, bukan memuat sheet setengah
## terunduh dan menampilkan Anima yang rusak.
func store_sprite(
	species_key: String,
	color_bucket: String,
	stage: int,
	manifest: Dictionary,
	sheet: PackedByteArray
) -> Dictionary:
	var dir := sprite_dir(species_key, color_bucket, stage)
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "tidak bisa membuat %s: %s" % [dir, error_string(err)]}

	var sheet_name := str(manifest.get("sheet", "")).strip_edges()
	if sheet_name.is_empty():
		return {"ok": false, "error": "manifest tanpa nama sheet"}

	var file := FileAccess.open(dir.path_join(sheet_name), FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "tidak bisa menulis sheet: %s" % dir.path_join(sheet_name)}
	file.store_buffer(sheet)
	file.close()

	var path := manifest_path(species_key, color_bucket, stage)
	var mf := FileAccess.open(path, FileAccess.WRITE)
	if mf == null:
		return {"ok": false, "error": "tidak bisa menulis manifest: %s" % path}
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.close()

	return {"ok": true, "error": "", "manifest_path": path}


func remember_anima(anima: Dictionary) -> void:
	last_anima = anima
	save()


## Parse yang gagal dengan tenang, tanpa mencetak galat parser engine.
## Dipakai juga oleh Backend untuk balasan server.
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## Dipakai juga oleh Backend: balasan JSON dari server tidak boleh dipercaya
## bentuknya, dan Dictionary kosong lebih mudah ditangani daripada null.
static func as_dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		return dict
	return {}
