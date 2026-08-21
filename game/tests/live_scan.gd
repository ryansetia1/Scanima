extends SceneTree

## Menjalankan seluruh jalur client terhadap produksi, tanpa UI.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##       --script res://tests/live_scan.gd -- --photo=/abs/path/foto.jpg
##
## BERBIAYA. Satu jalan menghabiskan satu Scan Charge dan satu panggilan Vision
## (~$0.003). Kalau spesies pada foto itu BELUM ada di species_library, ia juga
## memicu image generation ~$0.07 — jadi pakai foto yang spesiesnya sudah ada di
## pustaka kecuali memang sengaja membayar.
##
## Ini satu-satunya pemeriksaan yang bisa membuktikan lapisan jaringan client
## benar, karena yang diuji justru bagian yang tidak bisa dipalsukan: sign-in
## anonim, policy Storage per folder, kontrak create_anima, dan art yang
## benar-benar terunduh dari CDN lalu dimuat AnimaLoader.
##
## Sesi uji ditulis ke file sementara dan SENGAJA tidak dihapus, supaya jalan
## berikutnya memakai pemain uji yang sama beserta sisa Scan Charge-nya, bukan
## menumpuk akun anonim baru di produksi setiap kali.

const PATH_UJI := "user://live_scan_state.json"
const DIR_UJI := "user://live_scan_animas"
const POLL_INTERVAL_SEC := 3.0
const POLL_TIMEOUT_SEC := 180.0

var GameState: Node
var Backend: Node
var _t0 := 0.0


func _initialize() -> void:
	# Satu frame dulu. _initialize() jalan lebih awal daripada kode game mana pun,
	# dan pada titik itu node autoload belum benar-benar berada di dalam tree —
	# HTTPRequest yang ditambahkan ke node di luar tree menolak dengan
	# ERR_UNCONFIGURED. Scene sungguhan tidak pernah kena ini.
	await process_frame

	GameState = get_root().get_node("GameState")
	Backend = get_root().get_node("Backend")
	GameState.path_state = PATH_UJI
	GameState.dir_animas = DIR_UJI
	GameState.load_state()

	var photo := _arg_value("--photo=")
	if photo.is_empty():
		printerr("butuh --photo=/abs/path/foto.jpg")
		quit(2)
		return

	_t0 = Time.get_unix_time_from_system()
	var ok := await _run(photo)
	print("")
	if ok:
		print("live_scan: OK (%.1f detik)" % (Time.get_unix_time_from_system() - _t0))
		quit(0)
	else:
		printerr("live_scan: GAGAL")
		quit(1)


func _run(photo: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(photo)
	if bytes.is_empty():
		printerr("foto tidak terbaca: %s" % photo)
		return false
	print("foto: %s (%.0f KB)" % [photo, bytes.size() / 1024.0])

	print("1. sesi")
	var sesi: Dictionary = await Backend.ensure_session()
	if not sesi.ok:
		printerr("  sign-in gagal: %s" % sesi.error)
		return false
	print("  pemain %s" % GameState.uid())

	var profil: Dictionary = await Backend.fetch_profile()
	if not profil.ok:
		printerr("  baca profil gagal: %s" % profil.error)
		return false
	if GameState.profile.is_empty():
		# Nol baris untuk pemain yang jelas ada berarti trigger bootstrap tidak
		# jalan, atau RLS menolak. Keduanya diam-diam terlihat seperti "profil
		# belum dibuat", jadi harus gagal keras di sini.
		printerr("  profil kosong padahal pemain sudah ada")
		return false
	print("  saldo: %d scan, %d core" % [
		int(GameState.profile.get("scan_charges", 0)),
		int(GameState.profile.get("genesis_cores", 0)),
	])

	print("2. unggah foto ke bucket photos")
	var is_png := photo.get_extension().to_lower() == "png"
	var scan: Dictionary = GameState.begin_scan("png" if is_png else "jpg")
	var up: Dictionary = await Backend.upload_photo(
		str(scan["photo_path"]), bytes, "image/png" if is_png else "image/jpeg"
	)
	if not up.ok:
		printerr("  unggah gagal: %s" % up.error)
		return false
	print("  %s (http %d)" % [scan["photo_path"], up.code])

	print("3. create_anima")
	var t := Time.get_unix_time_from_system()
	var res: Dictionary = await Backend.create_anima(
		str(scan["photo_path"]), str(scan["idempotency_key"])
	)
	print("  balik dalam %.1f detik" % (Time.get_unix_time_from_system() - t))
	if not res.ok:
		printerr("  ditolak: %s (http %d)" % [res.error, res.code])
		return false

	var data: Dictionary = GameState.as_dict(res.data)
	if str(data.get("gate", "")) == "rejected":
		printerr("  gate menolak foto: %s" % str(data.get("reason", "?")))
		return false

	var species := ""
	var color := ""
	var stage := 1
	var anima_id := str(data.get("anima_id", ""))
	GameState.note_scan_started(str(data.get("generation_id", "")), anima_id)

	if bool(data.get("cache_hit", false)):
		var vision: Dictionary = GameState.as_dict(data.get("vision"))
		species = str(vision.get("species_key", ""))
		color = str(vision.get("color_bucket", ""))
		stage = int(GameState.as_dict(data.get("manifest")).get("stage", 1))
		print("  cache hit: %s / %s tahap %d, art gratis" % [species, color, stage])
	else:
		print("  genesis: menunggu webhook, ~satu menit")
		var hasil := await _tunggu(anima_id)
		if hasil.is_empty():
			return false
		species = str(hasil.get("species_key", ""))
		color = str(hasil.get("color_bucket", ""))
		stage = int(hasil.get("stage", 1))

	print("4. unduh art dan muat di AnimaLoader")
	var art: Dictionary = await Backend.fetch_species_art(species, color, stage)
	if not art.ok or typeof(art.data) != TYPE_ARRAY or (art.data as Array).is_empty():
		printerr("  pustaka tidak memberi art: %s" % art.error)
		return false
	var row: Dictionary = GameState.as_dict((art.data as Array)[0])
	var sheet_path := str(row.get("sheet_path", ""))
	var manifest: Dictionary = GameState.as_dict(row.get("manifest"))

	var unduh: Dictionary
	var use_anima := not anima_id.is_empty()
	if use_anima:
		unduh = await Backend.download_anima_sheet(sheet_path)
		if not unduh.ok:
			unduh = await Backend.download_sheet(sheet_path)
	else:
		unduh = await Backend.download_sheet(sheet_path)
	if not unduh.ok:
		printerr("  unduh sheet gagal: %s" % unduh.error)
		return false
	var png: PackedByteArray = unduh.bytes
	print("  %s (%.0f KB)" % [sheet_path, png.size() / 1024.0])

	var simpan: Dictionary
	if use_anima:
		simpan = GameState.store_sprite_for_anima(anima_id, manifest, png)
	else:
		simpan = GameState.store_sprite(species, color, stage, manifest, png)
	if not simpan.ok:
		printerr("  gagal menyimpan art: %s" % simpan.error)
		return false
	var cache_ok: bool = (
		GameState.has_sprite_for_anima(anima_id)
		if use_anima
		else GameState.has_sprite(species, color, stage)
	)
	if not cache_ok:
		printerr("  cache tidak terbaca lengkap sesudah disimpan")
		return false

	var manifest_path: String = (
		GameState.manifest_path_for_anima(anima_id)
		if use_anima
		else GameState.manifest_path(species, color, stage)
	)
	var loaded := AnimaLoader.load_from_manifest(manifest_path)
	if not loaded.get("ok", false):
		printerr("  AnimaLoader menolak art produksi: %s" % loaded.get("error", "?"))
		return false

	var poses: PackedStringArray = loaded.get("poses", PackedStringArray())
	print("  frame %s, pose %s" % [str(loaded["frame_size"]), ", ".join(poses)])
	if poses.size() < 4:
		printerr("  art produksi harus punya minimal empat pose, dapat %d" % poses.size())
		return false

	GameState.remember_anima({
		"id": anima_id, "species_key": species, "color_bucket": color, "stage": stage,
	})
	GameState.finish_scan()

	print("5. saldo sesudah scan")
	await Backend.fetch_profile()
	print("  %d scan, %d core" % [
		int(GameState.profile.get("scan_charges", 0)),
		int(GameState.profile.get("genesis_cores", 0)),
	])
	return true


func _tunggu(anima_id: String) -> Dictionary:
	var deadline := Time.get_unix_time_from_system() + POLL_TIMEOUT_SEC
	while Time.get_unix_time_from_system() < deadline:
		await create_timer(POLL_INTERVAL_SEC).timeout
		var res: Dictionary = await Backend.fetch_anima(anima_id)
		if not res.ok or typeof(res.data) != TYPE_ARRAY or (res.data as Array).is_empty():
			continue
		var row: Dictionary = GameState.as_dict((res.data as Array)[0])
		var status := str(row.get("status", ""))
		print("  +%.0fs status=%s" % [Time.get_unix_time_from_system() - _t0, status])
		if status == "ready":
			return row
		if status == "failed":
			printerr("  generation gagal, Core sudah direfund server")
			return {}
	printerr("  webhook tidak selesai dalam %d detik" % POLL_TIMEOUT_SEC)
	return {}


func _arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""
