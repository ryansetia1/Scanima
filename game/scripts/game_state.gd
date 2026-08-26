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
const SPRITE_CACHE_VERSION := 6
const LEGACY_SPRITE_CACHE_VERSION := 4

## Runtime saja: {access_token, refresh_token, expires_at, uid, is_anonymous}.
var session: Dictionary = {}
## Runtime-only generation for abandoning async callbacks from a previous UID.
var session_epoch: int = 0

## {idempotency_key, photo_path, generation_id, anima_id, capture_vibe}. Lihat begin_scan().
var pending_scan: Dictionary = {}

## {idempotency_key, anima_id, action, item_id}. Dipertahankan sampai server mengonfirmasi
## supaya retry Feed/Clean tidak mendebit Bits dua kali.
var pending_care: Dictionary = {}

## {session_id, expected_turn, expected_version, action, item_id, idempotency_key}.
## Session tetap disimpan saat tidak ada action supaya app bisa resume; key action
## dipertahankan saat timeout supaya turn dan reward tidak pernah commit dua kali.
var pending_battle: Dictionary = {}

## Team Battle punya lifecycle sendiri karena action Switch membawa slot dan
## endpoint-nya berbeda dari Duel. Bentuknya sama dengan pending_battle plus
## switch_to_slot, sehingga restart tidak dapat mengubah target pergantian.
var pending_team_battle: Dictionary = {}

## Expedition menyimpan run dan encounter sekaligus. `operation` kosong berarti
## hanya bookmark untuk resume; operation terisi dipertahankan sampai response
## authoritative supaya node, Supplies, damage, atau reward tidak commit dua kali.
var pending_expedition: Dictionary = {}

## {idempotency_key, item_id, expected_price}. Satu pembelian menggantung.
var pending_purchase: Dictionary = {}

## {idempotency_key, anima_id, prior_stage, target_stage, generation_id, resume_only, started_at}.
## Satu ritual evolusi aktif per akun; kunci tidak pernah diganti sampai selesai.
var pending_evolution: Dictionary = {}

## {idempotency_key, source_a_id, source_a_stage, source_b_id, source_b_stage,
## mode, generation_id, result_anima_id, started_at}. Resonance dan debit hanya
## boleh direplay dengan intent persis sama setelah timeout atau restart.
var pending_synthesis: Dictionary = {}

## {mode, state, started_at}. Verifier PKCE dan backup token hidup sebagai key
## SecureStore terpisah; sesi guest tetap aktif sampai exchange berhasil.
var pending_oauth: Dictionary = {}

## Token guest perangkat hidup di SecureStore. Boolean ini membedakan guest yang
## memang harus bisa dipulihkan dari akun lama/transfer yang perlu guest baru.
var device_guest_expected: bool = false

## {from_uid, target, started_at}. Tidak memuat token; marker ini membuat boot
## dapat menuntaskan pergantian akun jika app mati di antara dua write SecureStore.
var pending_account_switch: Dictionary = {}

## Preference lokal yang aman dipersist. Push adalah pilihan per-device karena
## izin OS dan FCM topic subscription juga hidup per-device.
var preferences: Dictionary = {
	"chapter_push_enabled": false,
}

## Anima terakhir yang berhasil dimuat, supaya app bisa langsung menampilkannya
## saat dibuka lagi tanpa menunggu jaringan sama sekali.
var last_anima: Dictionary = {}

## Salinan display-only dari respons server terakhir: {uid, saved_at, profile,
## roster, catalog, inventory}. Home mengecatnya sebelum jaringan menjawab lalu
## row authoritative menimpanya beberapa ratus milidetik kemudian. Ia **bukan**
## otoritas: saldo, kebutuhan, dan roster tetap milik Postgres, dan meter yang
## ditampilkan dari sini diproyeksikan ulang lewat `CareRules.projected_care()`.
## File terpisah supaya `state.json` tetap kecil dan cache boleh dibuang sendiri.
var path_boot_cache: String = "user://boot_cache.json"
var boot_cache: Dictionary = {}

## Saldo dari server. Ditampilkan, tidak pernah dipercaya, tidak pernah disimpan.
var profile: Dictionary = {}

## Config rollout dari server (min_client_version, flags). Kosong = permissive.
var client_config: Dictionary = {}


func _ready() -> void:
	load_state()


func uid() -> String:
	return str(session.get("uid", ""))


func load_state() -> void:
	var previous_uid := uid()
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
	pending_team_battle = as_dict(data.get("pending_team_battle"))
	pending_expedition = as_dict(data.get("pending_expedition"))
	pending_purchase = as_dict(data.get("pending_purchase"))
	pending_evolution = as_dict(data.get("pending_evolution"))
	pending_synthesis = as_dict(data.get("pending_synthesis"))
	pending_oauth = as_dict(data.get("pending_oauth"))
	device_guest_expected = bool(data.get("device_guest_expected", false))
	pending_account_switch = as_dict(data.get("pending_account_switch"))
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
	_migrate_device_guest(store)
	_migrate_oauth_pkce(store)
	if uid() != previous_uid:
		session_epoch += 1
	_load_boot_cache()


## Cache boot milik akun lain tidak pernah dipakai maupun dipertahankan: satu
## device bisa berpindah dari guest ke akun Google, dan roster keduanya berbeda.
func _load_boot_cache() -> void:
	boot_cache = {}
	if (
		not pending_account_switch.is_empty()
		or (not pending_oauth.is_empty() and not is_anonymous())
	):
		last_anima = {}
		return
	if not FileAccess.file_exists(path_boot_cache):
		return
	var parsed: Variant = parse_json(FileAccess.get_file_as_string(path_boot_cache))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var cached := as_dict(parsed)
	if str(cached.get("uid", "")).is_empty() or str(cached.get("uid", "")) != uid():
		return
	boot_cache = cached


## Dipanggil setelah respons server sukses. Field yang tidak dikirim tetap
## memakai nilai cache sebelumnya supaya refresh parsial tidak mengosongkan Home.
func remember_boot_cache(values: Dictionary) -> void:
	if uid().is_empty():
		return
	# `fetch_animas()` (Backend.gd) memfilter status=in.(ready,evolving); cache
	# ini wajib menegakkan filter yang sama, atau Anima berstatus lain (atau
	# yang sudah dihapus tapi sempat didorong lokal) tercat ulang ke roster
	# di cold start berikutnya dan tidak pernah hilang lagi.
	if values.has("roster"):
		var roster_value: Variant = values.get("roster")
		var filtered: Array[Dictionary] = []
		if typeof(roster_value) == TYPE_ARRAY:
			for value in (roster_value as Array):
				var row := as_dict(value)
				if str(row.get("status", "")) in ["ready", "evolving"]:
					filtered.append(row)
		values = values.duplicate(true)
		values["roster"] = filtered
	boot_cache.merge(values, true)
	boot_cache["uid"] = uid()
	boot_cache["saved_at"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(path_boot_cache, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(boot_cache))
	file.close()


func clear_boot_cache() -> void:
	boot_cache = {}
	if FileAccess.file_exists(path_boot_cache):
		DirAccess.remove_absolute(path_boot_cache)


func save() -> void:
	var payload := {
		"session": {"uid": uid()} if not uid().is_empty() else {},
		"pending_scan": pending_scan,
		"pending_care": pending_care,
		"pending_battle": pending_battle,
		"pending_team_battle": pending_team_battle,
		"pending_expedition": pending_expedition,
		"pending_purchase": pending_purchase,
		"pending_evolution": pending_evolution,
		"pending_synthesis": pending_synthesis,
		"pending_oauth": pending_oauth,
		"device_guest_expected": device_guest_expected,
		"pending_account_switch": pending_account_switch,
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
	var previous_uid := uid()
	var new_session := {
		"access_token": access_token,
		"refresh_token": refresh_token,
		"expires_at": expires_at,
		"uid": user_id,
		"is_anonymous": anonymous,
	}
	var store := _secure_store()
	if store == null:
		push_error("SecureStore tidak tersedia")
		return false
	var previous_guest: Dictionary = as_dict(store.load_device_guest()) if anonymous else {}
	if anonymous and not store.save_device_guest(new_session):
		push_error("guest perangkat tidak bisa ditulis ke SecureStore")
		return false
	if not store.save_session(new_session):
		if anonymous:
			if previous_guest.is_empty():
				store.clear_device_guest()
			else:
				store.save_device_guest(previous_guest)
		push_error("sesi tidak bisa ditulis ke SecureStore")
		return false
	session = new_session
	if user_id != previous_uid:
		session_epoch += 1
	if anonymous:
		device_guest_expected = true
	save()
	return true


func is_anonymous() -> bool:
	return bool(session.get("is_anonymous", true))


func device_guest_session() -> Dictionary:
	var store := _secure_store()
	return as_dict(store.load_device_guest()) if store != null else {}


func remember_device_guest() -> bool:
	if session.is_empty() or not is_anonymous():
		return false
	return store_device_guest(session)


func store_device_guest(value: Dictionary) -> bool:
	if (
		str(value.get("access_token", "")).is_empty()
		or str(value.get("refresh_token", "")).is_empty()
		or str(value.get("uid", "")).is_empty()
		or not bool(value.get("is_anonymous", false))
	):
		return false
	var store := _secure_store()
	if store == null or not store.save_device_guest(value):
		return false
	device_guest_expected = true
	save()
	return true


func activate_stored_session(value: Dictionary) -> bool:
	var access_token := str(value.get("access_token", ""))
	var refresh_token := str(value.get("refresh_token", ""))
	var user_id := str(value.get("uid", ""))
	if access_token.is_empty() or refresh_token.is_empty() or user_id.is_empty():
		return false
	return set_session(
		access_token,
		refresh_token,
		int(value.get("expires_at", 0)),
		user_id,
		bool(value.get("is_anonymous", true))
	)


func mark_device_guest_transferred() -> void:
	var store := _secure_store()
	if store != null:
		store.clear_device_guest()
	device_guest_expected = false
	save()


func begin_account_switch(target: String) -> void:
	pending_account_switch = {
		"from_uid": uid(),
		"target": target,
		"started_at": int(Time.get_unix_time_from_system()),
	}
	save()


func finish_account_switch() -> void:
	pending_account_switch = {}
	save()


func account_switch_blocked(ignore_oauth: bool = false) -> bool:
	return (
		not pending_scan.is_empty()
		or not pending_care.is_empty()
		or not pending_battle.is_empty()
		or not pending_team_battle.is_empty()
		or not pending_expedition.is_empty()
		or not pending_purchase.is_empty()
		or not pending_evolution.is_empty()
		or not pending_synthesis.is_empty()
		or (not ignore_oauth and not pending_oauth.is_empty())
		or not pending_account_switch.is_empty()
	)


func begin_oauth(mode: String, state: String, code_verifier: String) -> bool:
	var store := _secure_store()
	if store == null or not store.save_oauth_pkce({
		"state": state,
		"code_verifier": code_verifier,
	}):
		return false
	store.backup_session(session)
	pending_oauth = {
		"mode": mode,
		"state": state,
		"started_at": int(Time.get_unix_time_from_system()),
	}
	save()
	return true


func oauth_code_verifier(expected_state: String) -> String:
	var store := _secure_store()
	if store == null:
		return ""
	var pkce: Dictionary = as_dict(store.load_oauth_pkce())
	if str(pkce.get("state", "")) != expected_state:
		return ""
	return str(pkce.get("code_verifier", ""))


func finish_oauth() -> void:
	pending_oauth = {}
	var store := _secure_store()
	if store != null:
		store.clear_backup()
		store.clear_oauth_pkce()
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
		store.clear_oauth_pkce()
	save()


func clear_account_state(clear_device_guest: bool = true) -> void:
	if not session.is_empty():
		session_epoch += 1
	session = {}
	_clear_account_runtime_state()
	pending_account_switch = {}
	var store := _secure_store()
	if store != null:
		store.clear_session()
		store.clear_backup()
		store.clear_oauth_pkce()
		if clear_device_guest:
			store.clear_device_guest()
	if clear_device_guest:
		device_guest_expected = false
	save()


func discard_guest_local_state(preserve_oauth: bool = false) -> void:
	# Sign-in akun terpisah tidak membawa intent atau pilihan guest ke UID Google.
	# Sesi guest terenkripsi dan preference device tetap dipertahankan.
	_clear_account_runtime_state(preserve_oauth)
	save()


func _clear_account_runtime_state(preserve_oauth: bool = false) -> void:
	pending_scan = {}
	pending_care = {}
	pending_battle = {}
	pending_team_battle = {}
	pending_expedition = {}
	pending_purchase = {}
	pending_evolution = {}
	pending_synthesis = {}
	if not preserve_oauth:
		pending_oauth = {}
	last_anima = {}
	profile = {}
	client_config = {}
	clear_boot_cache()


func set_music_enabled(enabled: bool) -> void:
	preferences["music_enabled"] = enabled
	save()


func music_enabled() -> bool:
	return bool(preferences.get("music_enabled", true))


func set_chapter_push_enabled(enabled: bool) -> void:
	preferences["chapter_push_enabled"] = enabled
	save()


func chapter_push_enabled() -> bool:
	return bool(preferences.get("chapter_push_enabled", false))


func set_team_battle_available(available: bool) -> void:
	if team_battle_available() == available and preferences.has("team_battle_available"):
		return
	preferences["team_battle_available"] = available
	save()


func team_battle_available() -> bool:
	# Kosong = permissive: flag production sudah on, jangan lock lobby menunggu RPC.
	return bool(preferences.get("team_battle_available", true))


func set_expedition_available(available: bool) -> void:
	if expedition_available() == available and preferences.has("expedition_available"):
		return
	preferences["expedition_available"] = available
	save()


func expedition_available() -> bool:
	return bool(preferences.get("expedition_available", true))


func _migrate_device_guest(store: Node) -> void:
	if store == null:
		return
	var stored_guest: Dictionary = as_dict(store.load_device_guest())
	if not stored_guest.is_empty():
		device_guest_expected = true
		if session.is_empty() and store.save_session(stored_guest):
			session = stored_guest
		return
	if not session.is_empty() and is_anonymous() and store.save_device_guest(session):
		device_guest_expected = true


func _migrate_oauth_pkce(store: Node) -> void:
	if store == null or pending_oauth.is_empty():
		return
	var legacy_verifier := str(pending_oauth.get("code_verifier", ""))
	if legacy_verifier.is_empty():
		return
	if not store.save_oauth_pkce({
		"state": str(pending_oauth.get("state", "")),
		"code_verifier": legacy_verifier,
	}):
		return
	pending_oauth.erase("code_verifier")
	save()


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
func begin_scan(extension: String, capture_vibe: String = "") -> Dictionary:
	var key := "%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	pending_scan = {
		"idempotency_key": key,
		"photo_path": "%s/%s.%s" % [uid(), key, extension],
		"generation_id": "",
		"anima_id": "",
		"capture_vibe": ScanView.normalize_vibe(capture_vibe),
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


func remember_team_battle(session_id: String, expected_turn: int, expected_version: int) -> void:
	pending_team_battle = {
		"session_id": session_id,
		"expected_turn": expected_turn,
		"expected_version": expected_version,
		"action": "",
		"item_id": "",
		"switch_to_slot": -1,
		"idempotency_key": "",
	}
	save()


func begin_team_battle_action(
	session_id: String,
	expected_turn: int,
	expected_version: int,
	action: String,
	item_id: String = "",
	switch_to_slot: int = -1
) -> Dictionary:
	if (
		not pending_team_battle.is_empty()
		and (
			str(pending_team_battle.get("session_id", "")) != session_id
			or not str(pending_team_battle.get("action", "")).is_empty()
		)
	):
		return pending_team_battle
	var key := "%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	pending_team_battle = {
		"session_id": session_id,
		"expected_turn": expected_turn,
		"expected_version": expected_version,
		"action": action,
		"item_id": item_id,
		"switch_to_slot": switch_to_slot,
		"idempotency_key": key,
	}
	save()
	return pending_team_battle


func confirm_team_battle_response(session_data: Dictionary) -> void:
	if str(session_data.get("status", "")) == "active":
		remember_team_battle(
			str(session_data.get("id", "")),
			int(session_data.get("turn_number", 1)),
			int(session_data.get("version", 1))
		)
	else:
		finish_team_battle()


func finish_team_battle() -> void:
	pending_team_battle = {}
	save()


func remember_expedition(run_data: Dictionary, encounter_data: Dictionary = {}) -> void:
	var status := str(run_data.get("status", ""))
	if status in ["complete", "abandoned"]:
		finish_expedition()
		return
	pending_expedition = {
		"run_id": str(run_data.get("id", "")),
		"run_version": int(run_data.get("version", 1)),
		"encounter_id": str(encounter_data.get("id", "")),
		"expected_turn": int(encounter_data.get("turn_number", 1)),
		"expected_version": int(encounter_data.get("version", 1)),
		"operation": "",
		"action": "",
		"item_id": "",
		"switch_to_slot": -1,
		"node_id": "",
		"option_id": "",
		"target_slot": -1,
		"team_id": "",
		"idempotency_key": "",
	}
	save()


func begin_expedition_operation(
	operation: String,
	fields: Dictionary = {}
) -> Dictionary:
	if (
		not pending_expedition.is_empty()
		and not str(pending_expedition.get("operation", "")).is_empty()
	):
		return pending_expedition
	var pending := pending_expedition.duplicate(true)
	pending["operation"] = operation
	pending["idempotency_key"] = (
		"%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	)
	for key: Variant in fields:
		pending[key] = fields[key]
	pending_expedition = pending
	save()
	return pending_expedition


func confirm_expedition_response(run_data: Dictionary, encounter_data: Dictionary = {}) -> void:
	remember_expedition(run_data, encounter_data)


func finish_expedition() -> void:
	pending_expedition = {}
	save()


func shop_locked() -> bool:
	return (
		not pending_battle.is_empty()
		or not pending_team_battle.is_empty()
		or not pending_expedition.is_empty()
	)


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


func begin_evolution(
	anima_id: String,
	prior_stage: int,
	resume_only: bool = false
) -> Dictionary:
	if not pending_evolution.is_empty():
		return (
			pending_evolution
			if str(pending_evolution.get("anima_id", "")) == anima_id
			else {}
		)
	var target := prior_stage + 1
	var key := "%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	pending_evolution = {
		"idempotency_key": key,
		"anima_id": anima_id,
		"prior_stage": prior_stage,
		"target_stage": target,
		"generation_id": "",
		"resume_only": resume_only,
		"started_at": int(Time.get_unix_time_from_system()),
	}
	save()
	return pending_evolution


func note_evolution_started(
	generation_id: String,
	target_stage: int = 0,
	suggested_name: String = ""
) -> void:
	if pending_evolution.is_empty():
		return
	if not generation_id.is_empty():
		pending_evolution["generation_id"] = generation_id
	if target_stage > 0:
		pending_evolution["target_stage"] = target_stage
	var name := suggested_name.strip_edges()
	if not name.is_empty():
		pending_evolution["suggested_name"] = name
	save()


func finish_evolution() -> void:
	pending_evolution = {}
	save()


func begin_synthesis(
	source_a_id: String,
	source_a_stage: int,
	source_b_id: String,
	source_b_stage: int,
	mode: String
) -> Dictionary:
	if not pending_synthesis.is_empty():
		return pending_synthesis
	var key := "%d-%08x%08x" % [int(Time.get_unix_time_from_system()), randi(), randi()]
	pending_synthesis = {
		"idempotency_key": key,
		"source_a_id": source_a_id,
		"source_a_stage": source_a_stage,
		"source_b_id": source_b_id,
		"source_b_stage": source_b_stage,
		"mode": mode,
		"generation_id": "",
		"result_anima_id": "",
		"started_at": int(Time.get_unix_time_from_system()),
	}
	save()
	return pending_synthesis


func note_synthesis_started(generation_id: String, result_anima_id: String) -> void:
	if pending_synthesis.is_empty():
		return
	if not generation_id.is_empty():
		pending_synthesis["generation_id"] = generation_id
	if not result_anima_id.is_empty():
		pending_synthesis["result_anima_id"] = result_anima_id
	save()


func finish_synthesis() -> void:
	pending_synthesis = {}
	save()


## Folder cache per Anima + stage committed (v6). Sheet lama v5_<id> sengaja
## dibiarkan di disk; lookup baru selalu stage-aware.
func sprite_dir_for_anima(anima_id: String, stage: int = 1) -> String:
	return dir_animas.path_join(
		"v%d_%s_%d" % [SPRITE_CACHE_VERSION, anima_id, clampi(stage, 1, 3)]
	)


func manifest_path_for_anima(anima_id: String, stage: int = 1) -> String:
	return sprite_dir_for_anima(anima_id, stage).path_join("manifest.json")


func has_sprite_for_anima(anima_id: String, stage: int = 1) -> bool:
	return _has_sprite_at(
		manifest_path_for_anima(anima_id, stage),
		sprite_dir_for_anima(anima_id, stage)
	)


## Folder cache legacy per varian species (pustaka publik / art lama).
func sprite_dir(species_key: String, color_bucket: String, stage: int) -> String:
	return dir_animas.path_join(
		"v%d_%s_%s_%d" % [LEGACY_SPRITE_CACHE_VERSION, species_key, color_bucket, stage]
	)


func manifest_path(species_key: String, color_bucket: String, stage: int) -> String:
	return sprite_dir(species_key, color_bucket, stage).path_join("manifest.json")


func has_sprite(species_key: String, color_bucket: String, stage: int) -> bool:
	return _has_sprite_at(manifest_path(species_key, color_bucket, stage), sprite_dir(species_key, color_bucket, stage))


static func _has_sprite_at(manifest_file: String, dir: String) -> bool:
	if not FileAccess.file_exists(manifest_file):
		return false
	var parsed: Variant = parse_json(FileAccess.get_file_as_string(manifest_file))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var sheet := str(as_dict(parsed).get("sheet", ""))
	if sheet.is_empty():
		return false
	return FileAccess.file_exists(dir.path_join(sheet))


## Menyimpan sheet + manifest supaya AnimaLoader bisa memuatnya dari disk apa
## adanya, tanpa jalur kode kedua khusus art yang datang dari jaringan.
##
## Manifest ditulis TERAKHIR. Kalau proses mati di tengah, has_sprite() melihat
## cache yang belum lengkap sebagai tidak ada, bukan memuat sheet setengah
## terunduh dan menampilkan Anima yang rusak.
func store_sprite_for_anima(
	anima_id: String,
	manifest: Dictionary,
	sheet: PackedByteArray,
	stage: int = 1
) -> Dictionary:
	var dir := sprite_dir_for_anima(anima_id, stage)
	return _store_sprite_bundle(dir, manifest_path_for_anima(anima_id, stage), manifest, sheet)


func store_sprite(
	species_key: String,
	color_bucket: String,
	stage: int,
	manifest: Dictionary,
	sheet: PackedByteArray
) -> Dictionary:
	return _store_sprite_bundle(
		sprite_dir(species_key, color_bucket, stage),
		manifest_path(species_key, color_bucket, stage),
		manifest,
		sheet
	)


func _store_sprite_bundle(
	dir: String,
	manifest_file: String,
	manifest: Dictionary,
	sheet: PackedByteArray
) -> Dictionary:
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

	var mf := FileAccess.open(manifest_file, FileAccess.WRITE)
	if mf == null:
		return {"ok": false, "error": "tidak bisa menulis manifest: %s" % manifest_file}
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.close()

	return {"ok": true, "error": "", "manifest_path": manifest_file}


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
