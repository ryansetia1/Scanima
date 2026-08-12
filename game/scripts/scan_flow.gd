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
const CARE_RULES: GDScript = preload("res://scripts/care_rules.gd")

## 1280 px bukan angka pilihan bebas: seluruh foto di eval/photos/ berada di atau
## di bawah ukuran itu, jadi Smoke Set sudah membuktikan gate dan pemetaan stat
## pada resolusi ini. Menaikkannya berarti produksi memberi Vision gambar yang
## lebih besar daripada apa pun yang pernah diuji, dan yang bisa bergeser bukan
## cuma stat — kalau species_key berubah, dedup cache pecah dan scan yang
## seharusnya gratis membayar $0.07. Naikkan hanya bersama eval ulang.
const FOTO_MAX_PX := 1280
const FOTO_QUALITY := 85
const TOUCH_MIN := 96.0
const THUMBNAIL_SIZE := 128
const BASE_MARGIN := 32.0

var _ui_juice: GDScript = load("res://scripts/ui_juice.gd") as GDScript

@onready var _stage: Node2D = %Stage
@onready var _incubator: IncubatorEffect = %Incubator
@onready var _anima: AnimaPresenter = %Anima
@onready var _header: Label = %Header
@onready var _status: Label = %Status
@onready var _scan_button: Button = %ScanButton
@onready var _pose_row: HBoxContainer = %PoseRow
@onready var _dialog: FileDialog = %PhotoDialog
@onready var _preview: TextureRect = %PhotoPreview
@onready var _main_margin: MarginContainer = %Margin
@onready var _collection_margin: MarginContainer = %CollectionMargin
@onready var _stats_margin: MarginContainer = %StatsMargin
@onready var _header_card: PanelContainer = %HeaderCard
@onready var _stage_badge: PanelContainer = %StageBadge
@onready var _status_panel: PanelContainer = %StatusPanel
@onready var _collection_button: Button = %CollectionButton
@onready var _stats_button: Button = %StatsButton
@onready var _collection_overlay: Control = %CollectionOverlay
@onready var _stats_overlay: Control = %StatsOverlay
@onready var _anima_list: ItemList = %AnimaList
@onready var _collection_status: Label = %CollectionStatus
@onready var _stats_title: Label = %StatsTitle
@onready var _stat_hp: Label = %StatHp
@onready var _stat_atk: Label = %StatAtk
@onready var _stat_def: Label = %StatDef
@onready var _stat_spd: Label = %StatSpd
@onready var _stat_special: Label = %StatSpecial
@onready var _stat_element: Label = %StatElement
@onready var _stat_rarity: Label = %StatRarity
@onready var _stat_stage: Label = %StatStage
@onready var _care_panel: PanelContainer = %CarePanel
@onready var _care_summary: Label = %CareSummary
@onready var _need_hunger: ProgressBar = %NeedHunger
@onready var _need_energy: ProgressBar = %NeedEnergy
@onready var _need_hygiene: ProgressBar = %NeedHygiene
@onready var _need_bond: ProgressBar = %NeedBond
@onready var _feed_button: Button = %FeedButton
@onready var _clean_button: Button = %CleanButton
@onready var _sleep_button: Button = %SleepButton
@onready var _play_button: Button = %PlayButton
@onready var _collection_panel: PanelContainer = $UI/CollectionOverlay/CollectionMargin/Panel
@onready var _stats_panel: PanelContainer = $UI/StatsOverlay/StatsMargin/Panel

var _busy := false
var _roster: Array[Dictionary] = []
var _current_anima: Dictionary = {}
var _roster_error := ""
var _placeholder_icon: Texture2D = null
var _thumbnail_cache: Dictionary = {}

## Singleton plugin Android, null di desktop dan di test headless.
var _picker: Object = null


func _ready() -> void:
	_scan_button.pressed.connect(_on_pick_pressed)
	_collection_button.pressed.connect(_on_collection_pressed)
	_stats_button.pressed.connect(_on_stats_pressed)
	%CloseCollectionButton.pressed.connect(_close_collection)
	%CloseStatsButton.pressed.connect(_close_stats)
	_feed_button.pressed.connect(_perform_care.bind("feed"))
	_clean_button.pressed.connect(_perform_care.bind("clean"))
	_sleep_button.pressed.connect(_toggle_sleep)
	_play_button.pressed.connect(_perform_care.bind("play"))
	_anima_list.item_selected.connect(_on_anima_selected)
	_dialog.file_selected.connect(_scan_file)
	get_viewport().size_changed.connect(_layout_for_viewport)
	_layout_for_viewport()
	await get_tree().process_frame
	_ui_juice.install_buttons(self)
	_ui_juice.reveal(_header_card, 0.02)
	_ui_juice.reveal(_stage_badge, 0.08)
	_ui_juice.reveal(_status_panel, 0.14)
	_ui_juice.reveal(_scan_button, 0.20)
	_ui_juice.reveal($UI/Margin/Column/ActionsRow, 0.26)
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
		if arg == "--collection":
			await _on_collection_pressed()
		if arg == "--stats":
			await _on_stats_pressed()
		if arg == "--incubator":
			_start_incubation()
			_say("Menyintesis Anima… energi sedang dibentuk.")
		if arg == "--hatch-demo":
			await _run_hatch_demo()
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
	await _reload_roster()
	if not GameState.pending_care.is_empty():
		_say("Menyelesaikan perawatan yang tertunda…")
		await _resume_pending_care()
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
	elif not _roster.is_empty():
		var active := _active_row()
		if active.is_empty():
			active = _roster[0]
		# Selalu present row aktif, bahkan kalau art-nya sudah cached. Boot sempat
		# menampilkan last_anima sebelum jaringan selesai; kalau row itu sudah tidak
		# ada di roster, melewati present di sini membuat sprite A memakai stats B.
		_set_busy(true)
		await _present_row(active)
		_set_busy(false)
	elif not GameState.last_anima.is_empty():
		# Tanpa ini status berhenti di pesan boot, dan layar yang menampilkan
		# Anima sambil berkata "Menyiapkan akun..." terbaca seperti macet.
		var nama := str(GameState.last_anima.get("nickname", ""))
		if nama.is_empty():
			nama = str(GameState.last_anima.get("species_key", "Anima"))
		var suffix := "\nKoleksi belum termuat; tekan Koleksi untuk mencoba lagi." if not _roster_error.is_empty() else ""
		_say("%s menunggu. Foto benda lain untuk menambah koleksi.%s" % [nama, suffix])
	else:
		_say("Foto satu benda di sekitarmu untuk memulai.")


func _reload_roster() -> void:
	var res := await Backend.fetch_animas()
	if not res.ok or typeof(res.data) != TYPE_ARRAY:
		_roster_error = res.error if not res.error.is_empty() else "balasan koleksi tidak sah"
		_collection_status.text = "Koleksi gagal dimuat.\nTekan Koleksi lagi untuk mencoba."
		return

	var rows: Array = res.data
	var ready: Array[Dictionary] = []
	for value in rows:
		var row := GameState.as_dict(value)
		if not str(row.get("id", "")).is_empty():
			ready.append(row)
	_roster = ready
	_roster_error = ""
	_collection_status.text = "Belum ada Anima siap." if _roster.is_empty() else "%d Anima siap" % _roster.size()
	_populate_collection()


func _active_row() -> Dictionary:
	var wanted := str(GameState.last_anima.get("id", ""))
	if wanted.is_empty():
		return {}
	for row in _roster:
		if str(row.get("id", "")) == wanted:
			return row
	return {}


func _on_collection_pressed() -> void:
	await _ui_juice.show_overlay(_collection_overlay, _collection_panel)
	if not _roster_error.is_empty():
		_collection_button.disabled = true
		await _reload_roster()
		_collection_button.disabled = false


func _close_collection() -> void:
	await _ui_juice.hide_overlay(_collection_overlay, _collection_panel)


func _on_stats_pressed() -> void:
	if _current_anima.is_empty() or GameState.as_dict(_current_anima.get("base_stats")).is_empty():
		return
	_refresh_stats()
	await _ui_juice.show_overlay(_stats_overlay, _stats_panel)


func _close_stats() -> void:
	await _ui_juice.hide_overlay(_stats_overlay, _stats_panel)


func _on_anima_selected(index: int) -> void:
	if index < 0 or index >= _anima_list.item_count or _busy:
		return
	var row := GameState.as_dict(_anima_list.get_item_metadata(index))
	if row.is_empty():
		return
	await _ui_juice.hide_overlay(_collection_overlay, _collection_panel)
	_set_busy(true)
	await _present_row(row)
	_set_busy(false)


func _present_row(row: Dictionary) -> void:
	await _present(
		str(row.get("id", "")),
		str(row.get("species_key", "")),
		str(row.get("color_bucket", "")),
		int(row.get("stage", 1)),
		"",
		{},
		str(row.get("nickname", "")),
		row,
		false
	)
	if str(_current_anima.get("id", "")) == str(row.get("id", "")):
		await _sync_active_care(false)


func _toggle_sleep() -> void:
	var action := "wake" if _is_sleeping(_current_anima) else "sleep"
	await _perform_care(action)


func _perform_care(action: String) -> void:
	if _busy or _current_anima.is_empty():
		return
	if not GameState.pending_care.is_empty():
		_say("Perawatan sebelumnya masih menunggu konfirmasi.")
		return

	var anima_id := str(_current_anima.get("id", ""))
	if anima_id.is_empty():
		return

	_set_busy(true)
	var pending := GameState.begin_care(anima_id, action)
	await _send_pending_care(pending, true)
	_set_busy(false)


func _resume_pending_care() -> void:
	var pending := GameState.pending_care.duplicate(true)
	if pending.is_empty():
		return
	await _send_pending_care(pending, false)


func _send_pending_care(pending: Dictionary, show_feedback: bool) -> void:
	var action := str(pending.get("action", ""))
	var res := await Backend.care_anima(
		str(pending.get("anima_id", "")),
		action,
		str(pending.get("idempotency_key", ""))
	)
	if res.ok:
		GameState.finish_care()
		if _apply_care_response(GameState.as_dict(res.data), action, show_feedback):
			_say(_care_success_message(action))
		return

	# Galat 4xx adalah keputusan server, bukan gangguan sementara. Menyimpan key
	# selamanya akan mengunci semua tombol care walau saldo/kondisinya berubah.
	if res.code >= 400 and res.code < 500:
		GameState.finish_care()
	_say(_care_error_message(res.error))


func _sync_active_care(show_error: bool) -> void:
	var anima_id := str(_current_anima.get("id", ""))
	if anima_id.is_empty():
		return
	var res := await Backend.care_anima(anima_id, "sync")
	if res.ok:
		_apply_care_response(GameState.as_dict(res.data), "sync", false)
	elif show_error:
		_say("Kondisi Anima belum tersinkron: %s" % res.error)


func _apply_care_response(data: Dictionary, action: String, show_feedback: bool) -> bool:
	var row := normalize_anima_data(GameState.as_dict(data.get("anima")))
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return false

	if data.has("bits"):
		GameState.profile["bits"] = int(data.get("bits", 0))
		_refresh_header()
	_upsert_roster(row)

	if str(_current_anima.get("id", "")) == anima_id:
		_current_anima = row
		_refresh_stats()
		_refresh_care()
		if show_feedback:
			_anima.care_feedback(action)
	_populate_collection()
	return true


func _care_success_message(action: String) -> String:
	match action:
		"feed":
			return "Anima sudah makan. −5 Bits"
		"clean":
			return "Anima kembali bersih. −5 Bits"
		"play":
			return "Bond bertambah. −5 Energy"
		"sleep":
			return "Anima mulai tidur. Penuh dalam 6 jam."
		"wake":
			return "Anima bangun dengan Energy yang sudah dipulihkan."
		_:
			return "Kondisi Anima tersinkron."


func _care_error_message(error: String) -> String:
	match error:
		"NO_BITS":
			return "Bits tidak cukup. Makan dan Bersih membutuhkan 5 Bits."
		"NO_ENERGY":
			return "Energy kurang untuk bermain."
		"NEED_FULL":
			return "Kebutuhan itu sudah penuh."
		"ALREADY_SLEEPING":
			return "Anima sedang tidur."
		"NOT_SLEEPING":
			return "Anima sudah bangun."
		"ANIMA_NOT_READY":
			return "Anima belum siap dirawat."
		"ANIMA_NOT_FOUND":
			return "Anima tidak ditemukan di akun ini."
		_:
			return "Perawatan gagal: %s" % error


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
	_scan_button.text = "SCAN REAL OBJECT"


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
		_restore_previous_anima()
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
		_restore_previous_anima()
		return

	var data := GameState.as_dict(res.data)

	if str(data.get("gate", "")) == "rejected":
		_say("Foto ini tidak bisa dipakai (%s).\nCoba benda, bukan orang." % str(data.get("reason", "?")))
		GameState.finish_scan()
		_restore_previous_anima()
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
			str(vision.get("suggested_name", "")),
			vision
		)
		return

	if anima_id.is_empty():
		_say("Server tidak memberi anima_id. Coba lagi nanti.")
		_restore_previous_anima()
		return

	await _wait_for_hatch(anima_id)


# ---------------------------------------------------------------- inkubasi

func _wait_for_hatch(anima_id: String) -> void:
	_start_incubation()
	_say("Menyintesis Anima… energi sedang dibentuk (sekitar satu menit)")
	var remaining_poll_sec := POLL_TIMEOUT_SEC

	# Hitung waktu polling aktif, bukan wall clock. SceneTreeTimer berhenti saat app
	# di-background; waktu yang pemain habiskan di kamera/app lain tidak boleh
	# langsung menghabiskan timeout begitu Scanima aktif lagi.
	while remaining_poll_sec > 0.0:
		await get_tree().create_timer(POLL_INTERVAL_SEC).timeout
		remaining_poll_sec -= POLL_INTERVAL_SEC
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
					str(row.get("nickname", "")),
					row
				)
				return
			"failed":
				# Server sudah mengembalikan Core-nya sendiri lewat refund_generation.
				_say("Gambar gagal dibuat. Genesis Core sudah dikembalikan.")
				await Backend.fetch_profile()
				_refresh_header()
				GameState.finish_scan()
				_restore_previous_anima()
				return

	# Bukan kegagalan: webhook mungkin masih jalan. Scan-nya tetap tersimpan.
	_say("Belum selesai. Buka lagi nanti — progresnya tersimpan.")
	_restore_previous_anima()


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
	nickname: String = "",
	anima_data: Dictionary = {},
	complete_scan: bool = true
) -> void:
	if species_key.is_empty() or color_bucket.is_empty():
		_say("Data spesies tidak lengkap dari server.")
		if complete_scan:
			_restore_previous_anima()
		return

	var hatching := _incubator.is_active()
	if not GameState.has_sprite(species_key, color_bucket, stage):
		_say("Mengunduh art…")
		if manifest.is_empty() or sheet_path.is_empty():
			var art := await Backend.fetch_species_art(species_key, color_bucket, stage)
			if not art.ok or typeof(art.data) != TYPE_ARRAY or (art.data as Array).is_empty():
				_say("Art belum ada di pustaka: %s" % art.error)
				if complete_scan:
					_restore_previous_anima()
				return
			var row := GameState.as_dict((art.data as Array)[0])
			sheet_path = str(row.get("sheet_path", ""))
			manifest = GameState.as_dict(row.get("manifest"))

		var unduh := await Backend.download_sheet(sheet_path)
		if not unduh.ok:
			_say("Unduh art gagal: %s" % unduh.error)
			if complete_scan:
				_restore_previous_anima()
			return

		var simpan := GameState.store_sprite(species_key, color_bucket, stage, manifest, unduh.bytes)
		if not simpan.ok:
			_say("Gagal menyimpan art: %s" % simpan.error)
			if complete_scan:
				_restore_previous_anima()
			return

	if not _load_and_apply(species_key, color_bucket, stage):
		if complete_scan:
			_restore_previous_anima()
		return

	# create_anima mengembalikan bentuk Vision (`stats`), sedangkan row Postgres
	# memakai `base_stats`. Normalisasi sekali sebelum Stats dan roster lokal
	# membaca data yang sama.
	_current_anima = normalize_anima_data(anima_data)
	_current_anima.merge({
		"id": anima_id,
		"nickname": nickname,
		"species_key": species_key,
		"color_bucket": color_bucket,
		"stage": stage,
	}, true)
	GameState.remember_anima({
		"id": anima_id,
		"nickname": nickname,
		"species_key": species_key,
		"color_bucket": color_bucket,
		"stage": stage,
	})
	_upsert_roster(_current_anima)
	_refresh_stats()
	_refresh_care()
	_populate_collection()
	if complete_scan:
		GameState.finish_scan()
	# Fotonya sudah selesai tugasnya begitu Anima-nya ada; membiarkannya di layar
	# hanya menutupi hasil yang justru ingin dilihat pemain.
	_preview.visible = false
	if hatching:
		_say("Menetas!")
		await _incubator.burst()
		await _anima.hatch_reveal()
	else:
		_incubator.stop()
		_anima.visible = true
	_pose_row.visible = true
	if complete_scan:
		await _sync_active_care(false)
	_say("%s siap." % (nickname if not nickname.is_empty() else species_key))


static func normalize_anima_data(anima_data: Dictionary) -> Dictionary:
	var normalized := anima_data.duplicate(true)
	if not normalized.has("base_stats") and typeof(normalized.get("stats")) == TYPE_DICTIONARY:
		normalized["base_stats"] = normalized["stats"]
	if normalized.has("care") or normalized.has("care_synced_at"):
		normalized["care"] = CARE_RULES.normalized_care(normalized.get("care"))
	return normalized


func _show_cached_anima() -> void:
	var anima := GameState.last_anima
	if anima.is_empty():
		return
	_current_anima = anima.duplicate(true)
	_refresh_stats()
	_refresh_care()
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
	_anima.visible = not _incubator.is_active()
	_build_pose_buttons(loaded["poses"])
	return true


func _build_pose_buttons(poses: PackedStringArray) -> void:
	for child in _pose_row.get_children():
		child.queue_free()
	for pose in poses:
		var button := Button.new()
		button.text = pose.capitalize()
		button.custom_minimum_size = Vector2(0, TOUCH_MIN)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"PoseButton"
		button.pressed.connect(_anima.set_pose.bind(pose))
		_pose_row.add_child(button)
		_ui_juice.install_button(button)


func _upsert_roster(row: Dictionary) -> void:
	var id := str(row.get("id", ""))
	if id.is_empty():
		return
	for i in _roster.size():
		if str(_roster[i].get("id", "")) == id:
			_roster[i] = row
			return
	_roster.push_front(row)


func _populate_collection() -> void:
	if not is_instance_valid(_anima_list):
		return
	# ponytail: pass pertama membuat thumbnail cached secara sinkron. Plafon
	# sekitar 100 Anima lokal; kalau roster nyata melewatinya, simpan thumbnail
	# 128px terpisah saat sheet diunduh dan virtualisasikan daftar.
	_anima_list.clear()
	var active_id := str(_current_anima.get("id", GameState.last_anima.get("id", "")))
	var selected := -1
	for row in _roster:
		var id := str(row.get("id", ""))
		var active := id == active_id
		var nama := str(row.get("nickname", row.get("species_key", "Anima")))
		var label := "%s%s · %s S%d" % [
			"● " if active else "",
			nama,
			str(row.get("element", "?")).capitalize(),
			int(row.get("stage", 1)),
		]
		_anima_list.add_item(label, _thumbnail_for(row), true)
		var index := _anima_list.item_count - 1
		_anima_list.set_item_metadata(index, row)
		_anima_list.set_item_tooltip(index, "%s · rarity %d/5" % [nama, int(row.get("rarity", 1))])
		if active:
			selected = index
	if selected >= 0:
		_anima_list.select(selected)
	_collection_status.text = "Belum ada Anima siap." if _roster.is_empty() else "%d Anima siap" % _roster.size()


func _thumbnail_for(row: Dictionary) -> Texture2D:
	var species := str(row.get("species_key", ""))
	var color := str(row.get("color_bucket", ""))
	var stage := int(row.get("stage", 1))
	var cache_key := "%s|%s|%d" % [species, color, stage]
	if _thumbnail_cache.has(cache_key):
		return _thumbnail_cache[cache_key] as Texture2D
	if GameState.has_sprite(species, color, stage):
		var loaded := AnimaLoader.load_from_manifest(GameState.manifest_path(species, color, stage))
		if bool(loaded.get("ok", false)):
			var frames: SpriteFrames = loaded.get("frames")
			if frames != null and frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
				var frame := frames.get_frame_texture("idle", 0)
				if frame != null:
					var image := frame.get_image()
					if image != null and not image.is_empty():
						image.resize(THUMBNAIL_SIZE, THUMBNAIL_SIZE, Image.INTERPOLATE_LANCZOS)
						var texture := ImageTexture.create_from_image(image)
						_thumbnail_cache[cache_key] = texture
						return texture

	if _placeholder_icon == null:
		var placeholder := Image.create_empty(
			THUMBNAIL_SIZE, THUMBNAIL_SIZE, false, Image.FORMAT_RGBA8
		)
		placeholder.fill(Color(0.16, 0.18, 0.22, 1.0))
		_placeholder_icon = ImageTexture.create_from_image(placeholder)
	return _placeholder_icon


func _refresh_stats() -> void:
	var stats := GameState.as_dict(_current_anima.get("base_stats"))
	var nama := str(_current_anima.get("nickname", _current_anima.get("species_key", "Anima")))
	_stats_title.text = "%s // BIOMETRICS" % nama.to_upper()
	_stat_hp.text = _stat_value(stats, "hp")
	_stat_atk.text = _stat_value(stats, "atk")
	_stat_def.text = _stat_value(stats, "def")
	_stat_spd.text = _stat_value(stats, "spd")
	_stat_special.text = _stat_value(stats, "special")
	_stat_element.text = str(_current_anima.get("element", "—")).capitalize()
	_stat_rarity.text = "%d / 5" % int(_current_anima["rarity"]) if _current_anima.has("rarity") else "—"
	_stat_stage.text = _stage_name(int(_current_anima.get("stage", 1)))
	_stats_button.disabled = _busy or _current_anima.is_empty() or stats.is_empty()


func _refresh_care() -> void:
	var has_care := typeof(_current_anima.get("care")) == TYPE_DICTIONARY
	var should_reveal := has_care and not _care_panel.visible
	_care_panel.visible = has_care
	if not has_care:
		_set_care_buttons_disabled(true)
		return
	if should_reveal:
		_ui_juice.reveal(_care_panel)

	var care: Dictionary = CARE_RULES.normalized_care(_current_anima.get("care"))
	_ui_juice.tween_meter(_need_hunger, care["hunger"])
	_ui_juice.tween_meter(_need_energy, care["energy"])
	_ui_juice.tween_meter(_need_hygiene, care["hygiene"])
	_ui_juice.tween_meter(_need_bond, care["bond"])

	var sleeping := _is_sleeping(_current_anima)
	var dormant := _has_timestamp(_current_anima.get("dormant_since"))
	var state := "DORMANT" if dormant else ("SLEEPING" if sleeping else "ACTIVE")
	_care_summary.text = "CARE SCORE %03d  //  %s" % [
		int(_current_anima.get("care_score", 0)),
		state,
	]
	_sleep_button.text = "WAKE" if sleeping else "SLEEP"
	_set_care_buttons_disabled(_busy)
	if _anima.sprite_frames != null:
		_anima.apply_care_state(sleeping, dormant)


func _set_care_buttons_disabled(disabled: bool) -> void:
	_feed_button.disabled = disabled
	_clean_button.disabled = disabled
	_sleep_button.disabled = disabled
	_play_button.disabled = disabled


func _is_sleeping(row: Dictionary) -> bool:
	return _has_timestamp(row.get("sleep_started_at"))


static func _has_timestamp(value: Variant) -> bool:
	return value != null and not str(value).is_empty()


func _stat_value(stats: Dictionary, key: String) -> String:
	return str(int(stats[key])) if stats.has(key) else "—"


func _stage_name(stage: int) -> String:
	match stage:
		1:
			return "Baby"
		2:
			return "Adult"
		3:
			return "Perfect"
		_:
			return str(stage)


func _layout_for_viewport() -> void:
	if not is_instance_valid(_stage):
		return
	var viewport_size := get_viewport_rect().size
	var insets := Vector4.ZERO
	if OS.has_feature("android") or OS.has_feature("ios"):
		var screen_size := Vector2(DisplayServer.screen_get_size())
		if screen_size.x > 0.0 and screen_size.y > 0.0:
			var safe := DisplayServer.get_display_safe_area()
			var scale := Vector2(viewport_size.x / screen_size.x, viewport_size.y / screen_size.y)
			insets = Vector4(
				safe.position.x * scale.x,
				safe.position.y * scale.y,
				(screen_size.x - safe.end.x) * scale.x,
				(screen_size.y - safe.end.y) * scale.y
			)

	_apply_margins(_main_margin, insets, BASE_MARGIN, BASE_MARGIN)
	_apply_margins(_collection_margin, insets, 48.0, 48.0)
	_apply_margins(_stats_margin, insets, 64.0, 96.0)
	_stage.position = stage_position_for(viewport_size, insets)


static func stage_position_for(viewport_size: Vector2, insets: Vector4) -> Vector2:
	var safe_top := insets.y
	var safe_bottom := viewport_size.y - insets.w
	return Vector2(viewport_size.x * 0.5, lerpf(safe_top, safe_bottom, 0.57))


func _apply_margins(node: MarginContainer, insets: Vector4, side: float, vertical: float) -> void:
	node.add_theme_constant_override("margin_left", int(side + insets.x))
	node.add_theme_constant_override("margin_top", int(vertical + insets.y))
	node.add_theme_constant_override("margin_right", int(side + insets.z))
	node.add_theme_constant_override("margin_bottom", int(vertical + insets.w))


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
	# Foto dan Anima lama sama-sama hidup di area tengah. Menyembunyikan Anima
	# selama preview membuat orientasi foto terbaca jelas dan mencegah dua subjek
	# saling menutupi; Anima muncul lagi hanya setelah art berhasil dipresentasikan.
	_anima.visible = false
	print("foto: %d x %d, %.0f KB" % [image.get_width(), image.get_height(), bytes.size() / 1024.0])


func _start_incubation() -> void:
	_preview.visible = false
	_anima.visible = false
	_pose_row.visible = false
	_incubator.start()


func _restore_previous_anima() -> void:
	_incubator.stop()
	_preview.visible = false
	_anima.visible = _anima.sprite_frames != null
	_pose_row.visible = _anima.sprite_frames != null


func _say(text: String) -> void:
	_status.text = text
	_ui_juice.pop(_status_panel, 1.025)
	print(text)


func _refresh_header() -> void:
	var p := GameState.profile
	if p.is_empty():
		_header.text = "— SCANS    ◈ — CORES    ◆ — BITS"
		return
	_header.text = "%02d SCANS    ◈ %02d CORES    ◆ %03d BITS" % [
		int(p.get("scan_charges", 0)), int(p.get("genesis_cores", 0)), int(p.get("bits", 0))
	]
	_ui_juice.pop(_header_card, 1.018)


func _set_busy(busy: bool) -> void:
	_busy = busy
	_scan_button.disabled = busy
	_collection_button.disabled = busy
	_stats_button.disabled = (
		busy
		or _current_anima.is_empty()
		or GameState.as_dict(_current_anima.get("base_stats")).is_empty()
	)
	_set_care_buttons_disabled(
		busy or typeof(_current_anima.get("care")) != TYPE_DICTIONARY
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _stats_overlay.visible:
			_close_stats()
			get_viewport().set_input_as_handled()
			return
		if _collection_overlay.visible:
			_close_collection()
			get_viewport().set_input_as_handled()
			return
	if not _busy and event is InputEventMouseButton and event.pressed and _anima.sprite_frames != null:
		_anima.hop()


func _capture_and_quit(path: String) -> void:
	for _i in 24:
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


func _run_hatch_demo() -> void:
	if _anima.sprite_frames == null:
		_say("Demo hatch butuh satu Anima yang sudah cached.")
		return
	_set_busy(true)
	_start_incubation()
	_say("Demo: menyintesis Anima…")
	await get_tree().create_timer(1.8).timeout
	await _incubator.burst()
	await _anima.hatch_reveal()
	_pose_row.visible = true
	_set_busy(false)
	_say("Demo hatch selesai.")
