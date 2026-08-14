extends SceneTree

## Uji lapisan client yang tidak menyentuh jaringan:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##       --script res://tests/test_client_state.gd
##
## Yang diuji di sini dipilih karena kalau rusak, rusaknya mahal dan sunyi:
##
##   - sesi yang tidak selamat melewati restart berarti akun pemain lenyap, dan
##     pemain anonim tidak punya email untuk memulihkannya
##   - kunci idempotency yang berubah di tengah scan berarti Genesis Core kedua
##     terdebit untuk satu Anima yang sama
##   - kunci care yang hilang setelah timeout berarti Bits bisa terdebit dua kali
##   - kunci turn Battle yang berubah setelah timeout berarti damage/reward bisa
##     diproses dua kali
##   - cache art setengah terunduh yang terbaca lengkap berarti Anima tampil rusak
##
## State pemain tidak disentuh: GameState diarahkan ke file dan folder sementara.
##
## Autoload diambil lewat node path, bukan lewat nama globalnya. Dalam mode
## --script, node autoload-nya SUDAH ada di bawah root, tetapi nama globalnya
## belum terdaftar saat skrip ini dikompilasi, jadi menulis `GameState` di sini
## gagal dengan "Identifier not found" sebelum satu baris pun jalan.

const PATH_UJI := "user://uji_state.json"
const PATH_SECURE_UJI := "user://uji_secure_session.json"
const DIR_UJI := "user://uji_animas"

var _failures: PackedStringArray = []
var _checks := 0
var GameState: Node
var SecureStore: Node
var Backend: GDScript


func _initialize() -> void:
	GameState = get_root().get_node("GameState")
	SecureStore = get_root().get_node("SecureStore")
	# Script-nya, bukan node-nya: yang dipakai di sini fungsi statis dan konstanta.
	Backend = get_root().get_node("Backend").get_script()
	GameState.path_state = PATH_UJI
	GameState.dir_animas = DIR_UJI
	SecureStore.fallback_path = PATH_SECURE_UJI
	_bersihkan()

	_test_sesi_bertahan()
	_test_kedaluwarsa()
	_test_kunci_scan()
	_test_scan_selesai()
	_test_kunci_care()
	_test_kunci_battle()
	_test_kunci_purchase()
	_test_state_rusak()
	_test_cache_art()
	_test_cache_setengah()

	_bersihkan()

	print("")
	if _failures.is_empty():
		print("test_client_state: OK (%d check)" % _checks)
		quit(0)
	else:
		printerr("test_client_state: GAGAL %d dari %d check" % [_failures.size(), _checks])
		for f in _failures:
			printerr("  - %s" % f)
		quit(1)


# ---------------------------------------------------------------- helper

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s (dapat %s, harus %s)" % [message, str(actual), str(expected)])


## Melupakan semua yang ada di memori lalu membaca ulang dari disk, seperti app
## yang baru dibuka. Uji yang hanya memeriksa variabel di memori akan lulus walau
## penulisannya tidak pernah sampai ke disk.
func _muat_ulang() -> void:
	GameState.session = {}
	GameState.pending_scan = {}
	GameState.pending_care = {}
	GameState.pending_battle = {}
	GameState.last_anima = {}
	GameState.load_state()


func _bersihkan() -> void:
	DirAccess.remove_absolute(PATH_UJI)
	DirAccess.remove_absolute(PATH_UJI + ".tmp")
	DirAccess.remove_absolute(PATH_SECURE_UJI)
	DirAccess.remove_absolute(PATH_SECURE_UJI + ".tmp")
	_hapus_folder(DIR_UJI)


func _hapus_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if dir.current_is_dir():
			_hapus_folder(path.path_join(name))
		else:
			DirAccess.remove_absolute(path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------- test

func _test_sesi_bertahan() -> void:
	print("1. sesi selamat melewati restart")
	GameState.set_session("akses-1", "refresh-1", 1786600000, "uid-abc")
	_muat_ulang()
	_check_eq(GameState.session.get("access_token"), "akses-1", "access token harus kembali")
	_check_eq(GameState.session.get("refresh_token"), "refresh-1", "refresh token harus kembali")
	_check_eq(GameState.uid(), "uid-abc", "uid harus kembali")
	_check(GameState.is_anonymous(), "flag guest harus bertahan bersama secure session")
	var state_on_disk := FileAccess.get_file_as_string(PATH_UJI)
	_check(
		not state_on_disk.contains("akses-1") and not state_on_disk.contains("refresh-1"),
		"state.json tidak boleh lagi memuat token"
	)
	GameState.set_reduced_motion(true)
	_muat_ulang()
	_check(GameState.reduced_motion(), "Reduced Motion harus bertahan restart")
	# expires_at wajib int, bukan float: JSON tidak punya int dan pembandingan
	# umur token memakai aritmetika bilangan bulat.
	_check_eq(int(GameState.session.get("expires_at")), 1786600000, "expires_at harus utuh")


func _test_kedaluwarsa() -> void:
	print("2. matematika umur token")
	var now := 1786600000
	_check(Backend.needs_refresh({}, now), "sesi kosong harus dianggap perlu refresh")
	_check(
		Backend.needs_refresh({"access_token": "", "expires_at": now + 9999}, now),
		"sesi tanpa access token harus perlu refresh"
	)
	_check(
		not Backend.needs_refresh({"access_token": "a", "expires_at": now + 3600}, now),
		"token yang masih satu jam tidak boleh dipaksa refresh"
	)
	_check(
		Backend.needs_refresh({"access_token": "a", "expires_at": now + 60}, now),
		"token sisa 60 detik harus direfresh sebelum dipakai"
	)
	var margin: int = Backend.get_script_constant_map()["MARGIN_REFRESH_SEC"]
	_check(
		Backend.needs_refresh({"access_token": "a", "expires_at": now + margin}, now),
		"tepat di margin harus direfresh, bukan diloloskan"
	)
	_check(
		Backend.needs_refresh({"access_token": "a", "expires_at": now - 1}, now),
		"token yang sudah mati harus direfresh"
	)
	var headers: PackedStringArray = Backend._with_access_token(
		PackedStringArray(["apikey: public", "Authorization: Bearer lama"]),
		"baru"
	)
	var auth_count := 0
	for header in headers:
		if header.to_lower().begins_with("authorization:"):
			auth_count += 1
	_check_eq(auth_count, 1, "refresh header tidak boleh menggandakan Authorization")
	_check(headers.has("Authorization: Bearer baru"), "request harus memakai access token terbaru")
	_check(headers.has("apikey: public"), "refresh header harus mempertahankan header lain")

	var source := FileAccess.get_file_as_string("res://scripts/backend.gd")
	var send_start := source.find("func _send(")
	var send_end := source.find("\n\nfunc _send_once(", send_start)
	var send_body := source.substr(send_start, send_end - send_start)
	_check(
		send_body.find("await ensure_session()") < send_body.find("await _send_once("),
		"request authenticated harus memeriksa umur token sebelum dikirim"
	)
	_check(
		send_body.find("response.get(\"code\", 0)") != -1
		and send_body.find("await refresh_session()") != -1,
		"401 harus mencoba tepat satu refresh sebelum turn ditawarkan untuk retry"
	)


func _test_kunci_scan() -> void:
	print("3. kunci idempotency dan jalur foto")
	GameState.set_session("akses", "refresh", 1786600000, "uid-abc")
	var scan: Dictionary = GameState.begin_scan("jpg")
	var kunci := str(scan["idempotency_key"])

	_check(not kunci.is_empty(), "kunci idempotency tidak boleh kosong")
	_check(kunci.length() <= 128, "kunci harus di bawah batas 128 char milik server")
	_check(
		str(scan["photo_path"]).begins_with("uid-abc/"),
		"photo_path wajib di dalam folder uid sendiri, kalau tidak server menolak 403"
	)
	_check(str(scan["photo_path"]).ends_with(".jpg"), "ekstensi foto harus ikut")

	# Ini invarian uang: scan yang dilanjutkan setelah app mati wajib memakai
	# kunci yang sama, kalau tidak server memperlakukannya sebagai scan baru dan
	# mendebit Core kedua.
	_muat_ulang()
	_check_eq(GameState.pending_scan.get("idempotency_key"), kunci, "kunci harus bertahan di disk")
	_check_eq(GameState.pending_scan.get("photo_path"), scan["photo_path"], "jalur foto harus bertahan")

	var lain: Dictionary = GameState.begin_scan("png")
	_check(str(lain["idempotency_key"]) != kunci, "scan berbeda harus punya kunci berbeda")
	_check(str(lain["photo_path"]).ends_with(".png"), "ekstensi png harus dihormati")


func _test_scan_selesai() -> void:
	print("4. scan yang berjalan lalu selesai")
	GameState.begin_scan("jpg")
	GameState.note_scan_started("gen-1", "anima-1")
	_muat_ulang()
	_check_eq(GameState.pending_scan.get("anima_id"), "anima-1", "anima_id harus bertahan untuk polling")
	_check_eq(GameState.pending_scan.get("generation_id"), "gen-1", "generation_id harus bertahan")

	GameState.finish_scan()
	_muat_ulang()
	_check(GameState.pending_scan.is_empty(), "scan yang selesai tidak boleh tertinggal dan dilanjutkan lagi")
	_check_eq(GameState.uid(), "uid-abc", "sesi tidak boleh ikut terhapus saat scan selesai")


func _test_kunci_care() -> void:
	print("5. aksi care bertahan sampai server mengonfirmasi")
	var care: Dictionary = GameState.begin_care("anima-1", "feed", "ember_noodles")
	var key := str(care.get("idempotency_key", ""))
	_check(not key.is_empty(), "care harus punya idempotency key")
	_check(key.length() <= 128, "key care harus muat batas server")
	_check_eq(care.get("item_id"), "ember_noodles", "Feed pending harus membawa food_id")

	# Hanya satu aksi boleh menggantung. Tap kedua sebelum jawaban harus memakai
	# intent lama, bukan menimpa key dan berpotensi mendebit dua kali.
	var kedua: Dictionary = GameState.begin_care("anima-1", "clean")
	_check_eq(kedua.get("idempotency_key"), key, "aksi kedua tidak boleh menimpa pending care")
	_check_eq(kedua.get("action"), "feed", "action pending harus tetap Feed")

	_muat_ulang()
	_check_eq(GameState.pending_care.get("idempotency_key"), key, "key care harus selamat dari restart")
	_check_eq(GameState.pending_care.get("anima_id"), "anima-1", "anima care harus selamat dari restart")
	_check_eq(GameState.pending_care.get("item_id"), "ember_noodles", "food_id care harus selamat dari restart")

	GameState.finish_care()
	_muat_ulang()
	_check(GameState.pending_care.is_empty(), "care terkonfirmasi harus dihapus dari disk")
	_check_eq(GameState.uid(), "uid-abc", "menyelesaikan care tidak boleh menghapus sesi")


func _test_kunci_battle() -> void:
	print("6. session dan turn Battle bertahan sampai server mengonfirmasi")
	GameState.remember_battle("battle-1", 3, 7)
	_muat_ulang()
	_check_eq(GameState.pending_battle.get("session_id"), "battle-1", "session Battle harus bertahan")
	_check_eq(int(GameState.pending_battle.get("expected_turn")), 3, "turn server harus bertahan")

	var turn: Dictionary = GameState.begin_battle_action("battle-1", 3, 7, "item", "vital_patch")
	var key := str(turn.get("idempotency_key", ""))
	_check(not key.is_empty(), "turn Battle harus punya idempotency key")
	_check(key.length() <= 128, "key Battle harus muat batas server")
	_check_eq(turn.get("item_id"), "vital_patch", "turn Item harus membawa item_id")

	var kedua: Dictionary = GameState.begin_battle_action("battle-1", 3, 7, "guard")
	_check_eq(kedua.get("idempotency_key"), key, "tap kedua tidak boleh mengganti key turn")
	_check_eq(kedua.get("action"), "item", "tap kedua tidak boleh mengganti action tertunda")
	_check_eq(kedua.get("item_id"), "vital_patch", "tap kedua tidak boleh mengganti item_id tertunda")
	_muat_ulang()
	_check_eq(
		GameState.pending_battle.get("idempotency_key"),
		key,
		"timeout/restart harus me-replay key turn yang sama"
	)
	_check_eq(GameState.pending_battle.get("item_id"), "vital_patch", "item_id Battle harus selamat dari restart")

	GameState.confirm_battle_response({
		"id": "battle-1", "status": "active", "turn_number": 4, "version": 8,
	})
	_muat_ulang()
	_check_eq(int(GameState.pending_battle.get("expected_turn")), 4, "response memajukan turn")
	_check_eq(int(GameState.pending_battle.get("expected_version")), 8, "response memajukan version")
	_check(str(GameState.pending_battle.get("action", "")).is_empty(), "action terkonfirmasi harus kosong")

	var berikutnya: Dictionary = GameState.begin_battle_action("battle-1", 4, 8, "guard")
	_check(
		str(berikutnya.get("idempotency_key", "")) != key,
		"turn berikutnya harus mendapat key baru"
	)
	GameState.confirm_battle_response({"id": "battle-1", "status": "won"})
	_muat_ulang()
	_check(GameState.pending_battle.is_empty(), "Battle terminal tidak boleh di-resume lagi")
	_check_eq(GameState.uid(), "uid-abc", "menyelesaikan Battle tidak boleh menghapus sesi")


func _test_kunci_purchase() -> void:
	print("7. pembelian Shop bertahan sampai server mengonfirmasi")
	var pending: Dictionary = GameState.begin_purchase("byte_berry", 2)
	var key := str(pending.get("idempotency_key", ""))
	_check(not key.is_empty(), "pembelian harus punya idempotency key")
	_check_eq(pending.get("item_id"), "byte_berry", "pembelian harus membawa item_id")
	_check_eq(int(pending.get("expected_price")), 2, "pembelian harus membawa harga yang dilihat pemain")
	var kedua: Dictionary = GameState.begin_purchase("pulse_cell", 8)
	_check_eq(kedua.get("idempotency_key"), key, "tap Buy kedua tidak boleh menimpa pending purchase")
	_check_eq(kedua.get("item_id"), "byte_berry", "item pending harus tetap yang pertama")
	_muat_ulang()
	_check_eq(GameState.pending_purchase.get("idempotency_key"), key, "key pembelian harus selamat dari restart")
	_check_eq(GameState.pending_purchase.get("item_id"), "byte_berry", "item_id pembelian harus selamat dari restart")
	GameState.finish_purchase()
	_muat_ulang()
	_check(GameState.pending_purchase.is_empty(), "pembelian terkonfirmasi harus dihapus dari disk")
	_check_eq(GameState.uid(), "uid-abc", "menyelesaikan pembelian tidak boleh menghapus sesi")


func _test_state_rusak() -> void:
	print("8. state.json rusak tidak menghapus apa pun (satu ERROR di bawah disengaja)")
	var file := FileAccess.open(PATH_UJI, FileAccess.WRITE)
	file.store_string("{\"session\": {\"access_token\": \"akses")
	file.close()

	_muat_ulang()
	_check_eq(
		GameState.uid(),
		"uid-abc",
		"state non-sensitif rusak tidak boleh menghalangi sesi dari SecureStore"
	)
	# Filenya sengaja dibiarkan: masih ada kemungkinan diselamatkan manual, dan
	# menimpanya menutup kemungkinan itu untuk selamanya.
	_check(FileAccess.file_exists(PATH_UJI), "file yang rusak tidak boleh dihapus otomatis")

	GameState.set_session("akses-2", "refresh-2", 1786600000, "uid-xyz")
	_muat_ulang()
	_check_eq(GameState.uid(), "uid-xyz", "menulis ulang harus memperbaiki file yang rusak")


func _test_cache_art() -> void:
	print("8. art tersimpan dan bisa dimuat AnimaLoader")
	_check(
		GameState.sprite_dir("uji_kotak", "cool_blue", 1).get_file().begins_with("v4_"),
		"cache art v4 harus mengabaikan PNG lama yang masih punya matte putih"
	)
	var built := PlaceholderSheet.build()
	var image: Image = built["image"]
	var manifest: Dictionary = built["manifest"]
	var png := image.save_png_to_buffer()

	_check(not GameState.has_sprite("uji_kotak", "cool_blue", 1), "cache harus kosong sebelum disimpan")

	var simpan: Dictionary = GameState.store_sprite("uji_kotak", "cool_blue", 1, manifest, png)
	_check(simpan.get("ok", false), "store_sprite harus berhasil: %s" % simpan.get("error", ""))
	_check(GameState.has_sprite("uji_kotak", "cool_blue", 1), "cache harus terbaca lengkap sesudah disimpan")

	# Inti cache-nya: art dari jaringan tidak boleh butuh jalur kode kedua. Yang
	# tersimpan harus bisa dimuat oleh AnimaLoader yang sama dengan hasil eval.
	var loaded := AnimaLoader.load_from_manifest(GameState.manifest_path("uji_kotak", "cool_blue", 1))
	_check(loaded.get("ok", false), "AnimaLoader harus memuat art dari cache: %s" % loaded.get("error", ""))
	_check_eq((loaded.get("poses", PackedStringArray()) as PackedStringArray).size(), 9, "sembilan pose harus ada")

	# Varian lain tidak boleh ikut terbaca ada hanya karena species_key-nya sama.
	_check(
		not GameState.has_sprite("uji_kotak", "warm_red", 1),
		"color_bucket berbeda harus dianggap art berbeda"
	)
	_check(
		not GameState.has_sprite("uji_kotak", "cool_blue", 2),
		"stage berbeda harus dianggap art berbeda"
	)


func _test_cache_setengah() -> void:
	print("9. cache setengah terunduh dianggap tidak ada")
	var dir: String = GameState.sprite_dir("uji_kotak", "cool_blue", 1)
	var manifest_dict: Dictionary = PlaceholderSheet.build()["manifest"]
	var sheet_name := str(manifest_dict["sheet"])

	DirAccess.remove_absolute(dir.path_join(sheet_name))
	_check(
		not GameState.has_sprite("uji_kotak", "cool_blue", 1),
		"manifest tanpa sheet harus dianggap belum ada, bukan dimuat dan gagal di tengah"
	)

	# Sebaliknya juga: sheet ada tapi manifest belum ditulis. Ini urutan yang
	# dipakai store_sprite, jadi inilah bentuk kegagalan yang benar-benar mungkin.
	var f := FileAccess.open(dir.path_join(sheet_name), FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3]))
	f.close()
	DirAccess.remove_absolute(GameState.manifest_path("uji_kotak", "cool_blue", 1))
	_check(
		not GameState.has_sprite("uji_kotak", "cool_blue", 1),
		"sheet tanpa manifest harus dianggap belum ada"
	)
