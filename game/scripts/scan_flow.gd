extends Node2D

## Vertical slice Phase 2: dari foto di device sampai Anima hidup di layar.
##
## Yang ditunggu pemain ada DUA fase dengan panjang yang sangat berbeda, dan
## menyatukannya menjadi satu spinner adalah cara tercepat membuat app terasa
## macet. create_anima balik dalam ~15 detik karena Vision ikut ditunggu di
## dalamnya (hasilnya yang menentukan apakah server berhak mendebit Core), lalu
## gambarnya sendiri baru selesai sekitar satu menit kemudian lewat webhook.
## Kalau spesiesnya sudah ada di pustaka, fase kedua tidak ada sama sekali.
##
## Foto datang dari kamera lewat plugin GodotGetImage di Android, dan dari
## FileDialog di desktop. Dua jalur, satu tujuan: keduanya berakhir di
## _scan_bytes(), sebab create_anima tidak peduli fotonya dari mana. Jalur
## desktop bukan sisa yang belum dibersihkan — ia yang membuat alur ini bisa
## diperiksa di laptop tanpa perangkat Android.
##
## ponytail: hanya kamera, galeri tidak dipakai walau plugin mendukungnya.
## Fiksinya memfoto benda di depanmu, dan galeri membuka pintu untuk memindai
## gambar unduhan — karakter berhak cipta, foto orang, logo merek — yang persis
## kategori yang harus ditahan gate. Plafonnya: pemain tidak bisa memakai foto
## kemarin. Upgrade satu baris, panggil getGalleryImage() yang sudah ada.

## ponytail: polling 2 detik, bukan Realtime. Plafon ~500 hatch bersamaan;
## upgrade ke Supabase Realtime kalau kena.
const POLL_INTERVAL_SEC := 2.0
const POLL_TIMEOUT_SEC := 180.0
const MAX_FOTO_BYTE := 6 * 1024 * 1024

## 1280 px bukan angka pilihan bebas: seluruh foto di eval/photos/ berada di atau
## di bawah ukuran itu, jadi Smoke Set sudah membuktikan gate dan pemetaan stat
## pada resolusi ini. Menaikkannya berarti produksi memberi Vision gambar yang
## lebih besar daripada apa pun yang pernah diuji, dan yang bisa bergeser bukan
## cuma stat — kalau species_key berubah, dedup cache pecah dan scan yang
## seharusnya gratis membayar $0.07. Naikkan hanya bersama eval ulang.
const FOTO_MAX_PX := 1280
const FOTO_QUALITY := 85

@onready var _anima: AnimaPresenter = %Anima
@onready var _header: Label = %Header
@onready var _status: Label = %Status
@onready var _scan_button: Button = %ScanButton
@onready var _pose_row: HBoxContainer = %PoseRow
@onready var _dialog: FileDialog = %PhotoDialog
@onready var _preview: TextureRect = %PhotoPreview

var _busy := false

## Singleton plugin Android, null di desktop dan di test headless.
var _picker: Object = null


func _ready() -> void:
	_scan_button.pressed.connect(_on_pick_pressed)
	_dialog.file_selected.connect(_scan_file)
	_setup_picker()
	_show_cached_anima()
	await _boot()

	# Memeriksa layar sungguhan tanpa membuka editor:
	#   godot --path game -- --screenshot=/tmp/scan.png
	# Test bisa membuktikan region sprite benar, tapi tidak bisa membuktikan
	# tombolnya masih di dalam layar.
	#
	# --preview= memasang foto ke band preview tanpa memindainya. Tanpa ini,
	# satu-satunya cara melihat band itu adalah membelanjakan Scan Charge, jadi
	# perubahan tata letak berikutnya akan diperiksa dengan mata atau tidak
	# diperiksa sama sekali. Di build Android argumen ini tidak pernah ada.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="):
			var jalur := arg.trim_prefix("--preview=")
			_show_preview(FileAccess.get_file_as_bytes(jalur), jalur.get_extension().to_lower() == "png")
		if arg.begins_with("--screenshot="):
			await _capture_and_quit(arg.trim_prefix("--screenshot="))


# ---------------------------------------------------------------- boot

func _boot() -> void:
	_set_busy(true)
	_say("Menyiapkan akun…")

	var sesi := await Backend.ensure_session()
	if not sesi.ok:
		# Kegagalan di sini tidak boleh terlihat seperti app rusak biasa: kalau
		# refresh token ditolak, akun pemain berisiko tidak bisa dijangkau lagi.
		_say("Tidak bisa masuk: %s\nCoba lagi dengan jaringan yang stabil." % sesi.error)
		_set_busy(false)
		return

	await Backend.fetch_profile()
	_refresh_header()
	_set_busy(false)

	# Scan yang tertinggal dari sesi sebelumnya dilanjutkan, bukan dibuang. Core-nya
	# sudah terdebit dan gambarnya mungkin sudah selesai selagi app tertutup.
	var pending := GameState.pending_scan
	if not pending.is_empty():
		var anima_id := str(pending.get("anima_id", ""))
		if anima_id.is_empty():
			_say("Ada scan yang belum selesai. Menyambung…")
			await _resume_without_anima()
		else:
			_set_busy(true)
			await _wait_for_hatch(anima_id)
			_set_busy(false)
	elif GameState.last_anima.is_empty():
		_say("Foto satu benda di sekitarmu untuk memulai.")
	else:
		# Tanpa ini status berhenti di pesan boot, dan layar yang menampilkan
		# Anima sambil berkata "Menyiapkan akun..." terbaca seperti macet.
		var nama := str(GameState.last_anima.get("nickname", ""))
		if nama.is_empty():
			nama = str(GameState.last_anima.get("species_key", "Anima"))
		_say("%s menunggu. Foto benda lain untuk menambah koleksi." % nama)


## Scan yang mati sebelum create_anima menjawab. Memanggilnya lagi dengan kunci
## idempotency yang sama aman: server mengembalikan hasil yang sama, dan hanya
## itu satu-satunya cara pemain tidak kehilangan Core karena jaringan yang putus.
func _resume_without_anima() -> void:
	_set_busy(true)
	var pending := GameState.pending_scan
	var res := await Backend.create_anima(
		str(pending.get("photo_path", "")), str(pending.get("idempotency_key", ""))
	)
	await _handle_create_result(res)
	_set_busy(false)


# ---------------------------------------------------------------- ambil foto

func _setup_picker() -> void:
	if not Engine.has_singleton("GodotGetImage"):
		return
	_picker = Engine.get_singleton("GodotGetImage")

	# Dipasang sebelum permintaan pertama, bukan sesudahnya: plugin men-decode
	# bitmap berukuran tak diketahui, dan opsi inilah yang menahannya dari
	# kehabisan memori pada foto 12 MP. Resize juga memotong unggahan dari
	# megabyte ke ratusan kilobyte — itu kuota data pemain, bukan cuma waktu.
	_picker.setOptions({
		"image_width": FOTO_MAX_PX,
		"image_height": FOTO_MAX_PX,
		"keep_aspect": true,
		"image_quality": FOTO_QUALITY,
		"image_format": "jpg",
		"auto_rotate_image": true,
	})

	# Bentuk string, bukan _picker.image_request_completed: signal-nya didaftarkan
	# saat runtime oleh plugin, jadi tidak ada properti untuk di-resolve saat
	# kompilasi. Ketiganya membawa argumen, termasuk yang izin — arity yang salah
	# membuat connect gagal dan handler-nya tidak pernah dipanggil.
	_picker.connect("image_request_completed", _on_photo_taken)
	_picker.connect("permission_not_granted_by_user", _on_camera_denied)
	_picker.connect("error", _on_picker_error)
	_scan_button.text = "Foto Benda"


func _on_pick_pressed() -> void:
	if _busy:
		return
	if _picker == null:
		_dialog.popup_centered_ratio(0.9)
		return

	# Sengaja tidak mengunci tombol di sini. Kamera itu Activity terpisah dan
	# pembatalan tidak memancarkan signal apa pun, jadi tombol yang dikunci
	# sekarang akan mati selamanya bagi pemain yang berubah pikiran. Kuncinya
	# dipasang di _scan_bytes, saat byte-nya benar-benar sudah ada.
	if _picker.hasCamera():
		_picker.getCameraImage()
	else:
		# Perangkat tanpa kamera tetap bisa memasang app, sebab manifest plugin
		# menandai fitur kameranya opsional. Jangan tinggalkan tombol mati di sana.
		_picker.getGalleryImage()


## Dictionary karena metode yang sama melayani pilih-banyak gambar. Isinya bisa
## null kalau format yang dipilih tidak didukung, jadi jangan percaya bentuknya.
func _on_photo_taken(images: Dictionary) -> void:
	for buffer in images.values():
		if buffer is PackedByteArray and not (buffer as PackedByteArray).is_empty():
			_scan_bytes(buffer, "jpg")
			return
	_say("Foto tidak terbaca. Coba lagi.")


func _on_camera_denied(_permission: String) -> void:
	# resendPermission() tercantum di dokumentasi plugin tapi private di .aar yang
	# dirilis, jadi ia tidak bisa dipanggil dari sini. Permintaan izin berikutnya
	# menempel pada getCameraImage() berikutnya — jadi menekan tombolnya lagi
	# memang jalan pemulihannya, dan pemain harus diberi tahu itu. Tanpa kalimat
	# ini, satu penolakan terlihat seperti tombol yang rusak permanen.
	_say("Scanima butuh izin kamera untuk memfoto benda.\nTekan tombolnya lagi untuk memberi izin.")


func _on_picker_error(message: String) -> void:
	_say("Kamera gagal: %s" % message)


## Jalur desktop. Tidak ada resize di sini, dan itu disengaja: FileDialog memberi
## file apa adanya, yang justru dibutuhkan saat menguji foto eval ukuran asli.
func _scan_file(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		_say("Foto tidak bisa dibaca:\n%s" % path)
		return
	_scan_bytes(bytes, path.get_extension().to_lower())


# ---------------------------------------------------------------- scan

func _scan_bytes(bytes: PackedByteArray, extension: String) -> void:
	if _busy:
		return
	_set_busy(true)

	if bytes.size() > MAX_FOTO_BYTE:
		# Ditolak di sini juga, bukan hanya oleh bucket: 6 MB yang ditolak setelah
		# terkirim adalah kuota data pemain yang terbuang tanpa alasan.
		_say("Foto terlalu besar (%.1f MB). Batasnya 6 MB." % (bytes.size() / 1048576.0))
		_set_busy(false)
		return

	var is_png := extension == "png"
	_show_preview(bytes, is_png)
	var scan := GameState.begin_scan("png" if is_png else "jpg")

	_say("Mengunggah foto…")
	var up := await Backend.upload_photo(
		str(scan["photo_path"]), bytes, "image/png" if is_png else "image/jpeg"
	)
	if not up.ok:
		GameState.finish_scan()
		_say("Unggah gagal: %s" % up.error)
		_set_busy(false)
		return

	# Fase satu. Belasan detik tanpa apa pun di layar sudah terasa seperti macet,
	# padahal ini bagian yang paling cepat.
	_say("Menganalisis foto… (belasan detik)")
	var res := await Backend.create_anima(str(scan["photo_path"]), str(scan["idempotency_key"]))
	await _handle_create_result(res)
	_set_busy(false)


func _handle_create_result(res: Dictionary) -> void:
	await Backend.fetch_profile()
	_refresh_header()

	if not res.ok:
		match res.error:
			"NO_SCAN_CHARGE":
				_say("Scan Charge habis. Isi lagi besok, atau tonton iklan.")
			"NO_CORE":
				# Hasil Vision sudah dibayar dan disimpan server sebagai Temuan
				# Tertunda, jadi ini bukan kerugian — pemain tidak perlu memfoto
				# ulang benda yang mungkin sudah tidak ada di dekatnya.
				_say("Spesies baru ditemukan, tapi Genesis Core habis.\nTemuan ini disimpan dan bisa diklaim nanti.")
			"SPEND_CAP":
				_say("Batas biaya harian tercapai. Coba lagi besok.")
			_:
				_say("Gagal: %s" % res.error)
		GameState.finish_scan()
		return

	var data := GameState.as_dict(res.data)

	if str(data.get("gate", "")) == "rejected":
		_say("Foto ini tidak bisa dipakai (%s).\nCoba benda, bukan orang." % str(data.get("reason", "?")))
		GameState.finish_scan()
		return

	var anima_id := str(data.get("anima_id", ""))
	GameState.note_scan_started(str(data.get("generation_id", "")), anima_id)

	if bool(data.get("cache_hit", false)):
		# Discovery Scan: art-nya sudah ada, tidak ada yang perlu ditunggu.
		var vision := GameState.as_dict(data.get("vision"))
		var manifest := GameState.as_dict(data.get("manifest"))
		await _present(
			anima_id,
			str(vision.get("species_key", "")),
			str(vision.get("color_bucket", "")),
			# Dari manifest, bukan angka 1 yang ditulis di sini: tahap ikut
			# menentukan folder cache, dan evolusi akan memakai tahap lain.
			int(manifest.get("stage", 1)),
			str(data.get("sheet_path", "")),
			manifest,
			# Nama yang sama dengan yang dipakai server: ia memilih
			# suggested_name dari Vision kalau client tidak mengirim nickname.
			str(vision.get("suggested_name", ""))
		)
		return

	if anima_id.is_empty():
		_say("Server tidak memberi anima_id. Coba lagi nanti.")
		return

	await _wait_for_hatch(anima_id)


# ---------------------------------------------------------------- inkubasi

func _wait_for_hatch(anima_id: String) -> void:
	_say("Menetaskan Anima… (sekitar satu menit)")
	var deadline := Time.get_unix_time_from_system() + POLL_TIMEOUT_SEC

	while Time.get_unix_time_from_system() < deadline:
		await get_tree().create_timer(POLL_INTERVAL_SEC).timeout
		var res := await Backend.fetch_anima(anima_id)
		if not res.ok or typeof(res.data) != TYPE_ARRAY:
			continue
		var rows: Array = res.data
		if rows.is_empty():
			continue

		var row := GameState.as_dict(rows[0])
		match str(row.get("status", "")):
			"ready":
				await _present(
					anima_id,
					str(row.get("species_key", "")),
					str(row.get("color_bucket", "")),
					int(row.get("stage", 1)),
					"",
					{},
					str(row.get("nickname", ""))
				)
				return
			"failed":
				# Server sudah mengembalikan Core-nya sendiri lewat refund_generation.
				_say("Gambar gagal dibuat. Genesis Core sudah dikembalikan.")
				await Backend.fetch_profile()
				_refresh_header()
				GameState.finish_scan()
				return

	# Bukan kegagalan: webhook mungkin masih jalan. Scan-nya tetap tersimpan.
	_say("Belum selesai. Buka lagi nanti — progresnya tersimpan.")


# ---------------------------------------------------------------- tampilkan

## Mengunduh art kalau belum ada di device, lalu menyerahkannya ke AnimaLoader
## apa adanya. Tidak ada jalur kode kedua untuk art yang datang dari jaringan:
## begitu file ada di user://, ia sama saja dengan art hasil eval di laptop.
func _present(
	anima_id: String,
	species_key: String,
	color_bucket: String,
	stage: int,
	sheet_path: String,
	manifest: Dictionary,
	nickname := ""
) -> void:
	if species_key.is_empty() or color_bucket.is_empty():
		_say("Data spesies tidak lengkap dari server.")
		return

	if not GameState.has_sprite(species_key, color_bucket, stage):
		_say("Mengunduh art…")
		if manifest.is_empty() or sheet_path.is_empty():
			var art := await Backend.fetch_species_art(species_key, color_bucket, stage)
			if not art.ok or typeof(art.data) != TYPE_ARRAY or (art.data as Array).is_empty():
				_say("Art belum ada di pustaka: %s" % art.error)
				return
			var row := GameState.as_dict((art.data as Array)[0])
			sheet_path = str(row.get("sheet_path", ""))
			manifest = GameState.as_dict(row.get("manifest"))

		var unduh := await Backend.download_sheet(sheet_path)
		if not unduh.ok:
			_say("Unduh art gagal: %s" % unduh.error)
			return

		var simpan := GameState.store_sprite(species_key, color_bucket, stage, manifest, unduh.bytes)
		if not simpan.ok:
			_say("Gagal menyimpan art: %s" % simpan.error)
			return

	if not _load_and_apply(species_key, color_bucket, stage):
		return

	GameState.remember_anima({
		"id": anima_id,
		"nickname": nickname,
		"species_key": species_key,
		"color_bucket": color_bucket,
		"stage": stage,
	})
	GameState.finish_scan()
	# Fotonya sudah selesai tugasnya begitu Anima-nya ada; membiarkannya di layar
	# hanya menutupi hasil yang justru ingin dilihat pemain.
	_preview.visible = false
	_say("%s siap." % (nickname if not nickname.is_empty() else species_key))


func _show_cached_anima() -> void:
	var anima := GameState.last_anima
	if anima.is_empty():
		return
	var species := str(anima.get("species_key", ""))
	var color := str(anima.get("color_bucket", ""))
	var stage := int(anima.get("stage", 1))
	if GameState.has_sprite(species, color, stage):
		_load_and_apply(species, color, stage)


func _load_and_apply(species_key: String, color_bucket: String, stage: int) -> bool:
	var loaded := AnimaLoader.load_from_manifest(
		GameState.manifest_path(species_key, color_bucket, stage)
	)
	if not loaded.get("ok", false):
		_say("Art tidak bisa dimuat: %s" % loaded.get("error", "?"))
		return false
	_anima.apply(loaded)
	_build_pose_buttons(loaded["poses"])
	return true


func _build_pose_buttons(poses: PackedStringArray) -> void:
	for child in _pose_row.get_children():
		child.queue_free()
	for pose in poses:
		var button := Button.new()
		button.text = pose.capitalize()
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_anima.set_pose.bind(pose))
		_pose_row.add_child(button)


# ---------------------------------------------------------------- UI kecil

## Menampilkan foto yang akan dipindai, sekaligus mencetak ukurannya. Dimensi di
## log itu pemeriksaan termurah untuk resize dan rotasi: potret yang keluar
## sebagai lanskap berarti auto_rotate_image gagal di perangkat itu, dan tanpa ini
## kegagalannya cuma muncul sebagai stat yang aneh berbulan-bulan kemudian.
func _show_preview(bytes: PackedByteArray, is_png: bool) -> void:
	var image := Image.new()
	var err := image.load_png_from_buffer(bytes) if is_png else image.load_jpg_from_buffer(bytes)
	if err != OK:
		_preview.visible = false
		return
	_preview.texture = ImageTexture.create_from_image(image)
	_preview.visible = true
	print("foto: %d x %d, %.0f KB" % [image.get_width(), image.get_height(), bytes.size() / 1024.0])


func _say(text: String) -> void:
	_status.text = text
	print(text)


func _refresh_header() -> void:
	var p := GameState.profile
	if p.is_empty():
		_header.text = "Scanima"
		return
	_header.text = "%d Scan  ·  %d Core  ·  %d Bits" % [
		int(p.get("scan_charges", 0)), int(p.get("genesis_cores", 0)), int(p.get("bits", 0))
	]


func _set_busy(busy: bool) -> void:
	_busy = busy
	_scan_button.disabled = busy


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _anima.sprite_frames != null:
		_anima.hop()


func _capture_and_quit(path: String) -> void:
	for _i in 5:
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("viewport tidak bisa dibaca, jalankan tanpa --headless")
		get_tree().quit(1)
		return
	if image.save_png(path) != OK:
		push_error("gagal menulis screenshot ke %s" % path)
		get_tree().quit(1)
		return

	print("screenshot: %s" % path)
	get_tree().quit(0)
