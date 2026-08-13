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
const THUMBNAIL_SIZE := 128
const BASE_MARGIN := 32.0
const SLEEP_SYNC_RETRY_SEC := 30.0
const SLEEP_SYNC_EPSILON_SEC := 1.0

@onready var _stage: Node2D = %Stage
@onready var _first_anima_effect: FirstAnimaEffect = %FirstAnimaEffect
@onready var _incubator: IncubatorEffect = %Incubator
@onready var _anima: AnimaPresenter = %Anima
@onready var _status: Label = %Status
@onready var _dialog: FileDialog = %PhotoDialog
@onready var _status_panel: PanelContainer = %StatusPanel
@onready var _safe_margin: MarginContainer = %SafeMargin
@onready var _top_hud: PanelContainer = %TopHud
@onready var _scan_count: Label = %ScanCount
@onready var _core_count: Label = %CoreCount
@onready var _bits_count: Label = %BitsCount
@onready var _core_info_button: Button = %CoreInfoButton
@onready var _core_info_overlay: Control = %CoreInfoOverlay
@onready var _core_info_panel: PanelContainer = %CoreInfoPanel
@onready var _core_info_dismiss: Button = %CoreInfoDismissButton
@onready var _core_info_close: Button = %CoreInfoCloseButton
@onready var _home_view: HomeView = %HomeView
@onready var _scan_view: ScanView = %ScanView
@onready var _collection_view: CollectionView = %CollectionView
@onready var _details_view: AnimaDetailsView = %AnimaDetailsView
@onready var _bottom_nav: BottomNav = %BottomNav
@onready var _delete_anima_dialog: ConfirmationDialog = %DeleteAnimaDialog
@onready var _rename_anima_dialog: ConfirmationDialog = %RenameAnimaDialog
@onready var _rename_anima_input: LineEdit = %RenameAnimaInput

var _busy := false
var _roster: Array[Dictionary] = []
var _current_anima: Dictionary = {}
var _profile_anima: Dictionary = {}
var _roster_error := ""
var _placeholder_icon: Texture2D = null
var _thumbnail_cache: Dictionary = {}
var _destination: StringName = BottomNav.HOME
var _toast_revision := 0
var _sleep_completion_timer: Timer = null
var _sleep_sync_in_flight := false
var _pending_delete_id := ""
var _pending_rename_id := ""

## Singleton plugin Android, null di desktop dan di test headless.
var _picker: Object = null


func _ready() -> void:
	_sleep_completion_timer = Timer.new()
	_sleep_completion_timer.name = "SleepCompletionTimer"
	_sleep_completion_timer.one_shot = true
	add_child(_sleep_completion_timer)
	_sleep_completion_timer.timeout.connect(_sync_sleep_completion)
	_scan_view.scan_requested.connect(_on_pick_pressed)
	_home_view.care_requested.connect(_perform_care)
	_home_view.first_scan_requested.connect(_open_scan)
	_home_view.retry_requested.connect(_retry_roster)
	_collection_view.preview_requested.connect(_sync_collection_preview)
	_collection_view.profile_requested.connect(_show_collection_profile)
	_collection_view.summon_requested.connect(_summon_collection_anima)
	_collection_view.first_scan_requested.connect(_open_scan)
	_collection_view.retry_requested.connect(_retry_roster)
	_details_view.delete_requested.connect(_show_delete_confirmation)
	_bottom_nav.destination_selected.connect(_switch_destination)
	_delete_anima_dialog.confirmed.connect(_delete_confirmed)
	_delete_anima_dialog.canceled.connect(_delete_canceled)
	_rename_anima_dialog.confirmed.connect(_rename_confirmed)
	_rename_anima_dialog.canceled.connect(_rename_canceled)
	_rename_anima_input.text_submitted.connect(_rename_submitted)
	_delete_anima_dialog.get_ok_button().theme_type_variation = &"DangerButton"
	_rename_anima_dialog.get_ok_button().theme_type_variation = &"PrimaryButton"
	# Tombol X native terlalu kecil untuk touch dan posisinya berubah mengikuti
	# lebar title. Kedua dialog sudah punya aksi Cancel/Keep 96px yang eksplisit.
	var empty_close_icon := ImageTexture.new()
	_delete_anima_dialog.add_theme_icon_override("close", empty_close_icon)
	_rename_anima_dialog.add_theme_icon_override("close", empty_close_icon)
	LocaleManager.locale_changed.connect(_refresh_localized_ui)
	_core_info_button.pressed.connect(_show_core_info)
	_core_info_dismiss.pressed.connect(_hide_core_info)
	_core_info_close.pressed.connect(_hide_core_info)
	_dialog.file_selected.connect(_scan_file)
	get_viewport().size_changed.connect(_layout_for_viewport)
	_layout_for_viewport()
	await get_tree().process_frame
	UiJuice.install_buttons(self)
	UiJuice.reveal(_top_hud, 0.02)
	UiJuice.reveal(_home_view, 0.08)
	UiJuice.reveal(_bottom_nav, 0.14)
	_switch_destination(BottomNav.HOME)
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
			_switch_destination(BottomNav.SCAN)
			_show_preview(FileAccess.get_file_as_bytes(jalur), jalur.get_extension().to_lower() == "png")
		if arg == "--collection":
			_switch_destination(BottomNav.COLLECTION)
		if arg == "--stats":
			_switch_destination(BottomNav.ANIMA)
		if arg == "--core-info":
			_show_core_info()
		if arg == "--rename-demo" and not _current_anima.is_empty():
			_show_hatch_rename(str(_current_anima.get("id", "")))
		if arg == "--delete-demo" and not _current_anima.is_empty():
			_show_delete_confirmation(str(_current_anima.get("id", "")))
		if arg == "--sleep-demo" and not _current_anima.is_empty():
			_current_anima["sleep_started_at"] = Time.get_datetime_string_from_system(true)
			_refresh_care()
		if arg == "--incubator":
			_switch_destination(BottomNav.SCAN)
			_set_busy(true)
			_start_incubation()
			_say(tr("STATUS_INCUBATOR_DEMO"))
		if arg == "--hatch-demo":
			await _run_hatch_demo()
		if arg == "--collection-sheet-demo":
			_run_collection_sheet_demo()
		if arg == "--empty-demo":
			_run_empty_demo()
		if arg == "--summon-demo":
			await _run_summon_demo()
		if arg.begins_with("--screenshot="):
			await _capture_and_quit(arg.trim_prefix("--screenshot="))


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_RESUMED
		and is_node_ready()
		and is_instance_valid(_sleep_completion_timer)
		and _is_sleeping(_current_anima)
	):
		_sleep_completion_timer.stop()
		call_deferred("_sync_sleep_completion")


# ---------------------------------------------------------------- boot

func _boot() -> void:
	_set_busy(true)
	_set_home_shell_state(&"loading")
	_say(tr("STATUS_INITIALIZING"))

	var sesi := await Backend.ensure_session()
	if not sesi.ok:
		# Kegagalan di sini tidak boleh terlihat seperti app rusak biasa: kalau
		# refresh token ditolak, akun pemain berisiko tidak bisa dijangkau lagi.
		print("session error: %s" % sesi.error)
		_set_home_shell_state(&"error")
		_say(tr("STATUS_ACCOUNT_ERROR"))
		_set_busy(false)
		return

	await Backend.fetch_profile()
	_refresh_header()
	var roster_loaded := await _reload_roster()
	if not GameState.pending_care.is_empty():
		_say(tr("STATUS_RESUMING_CARE"))
		await _resume_pending_care()
	_set_busy(false)

	# Scan yang tertinggal dari sesi sebelumnya dilanjutkan, bukan dibuang. Core-nya
	# sudah terdebit dan gambarnya mungkin sudah selesai selagi app tertutup.
	var pending := GameState.pending_scan
	if not pending.is_empty():
		var anima_id := str(pending.get("anima_id", ""))
		if anima_id.is_empty():
			_switch_destination(BottomNav.SCAN)
			_say(tr("STATUS_RESUMING_SCAN"))
			await _resume_without_anima()
		else:
			_switch_destination(BottomNav.SCAN)
			_set_busy(true)
			await _wait_for_hatch(anima_id)
			_set_busy(false)
	elif not roster_loaded:
		_set_home_shell_state(&"error")
		_say(tr("STATUS_ROSTER_ERROR"))
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
	else:
		_current_anima = {}
		GameState.remember_anima({})
		_anima.sprite_frames = null
		_set_home_shell_state(&"empty")
		_say(tr("STATUS_FIRST_SCAN"))


func _reload_roster() -> bool:
	var res := await Backend.fetch_animas()
	if not res.ok or typeof(res.data) != TYPE_ARRAY:
		_roster_error = res.error if not res.error.is_empty() else "balasan koleksi tidak sah"
		_collection_view.set_error()
		return false

	var rows: Array = res.data
	var ready: Array[Dictionary] = []
	for value in rows:
		var row := GameState.as_dict(value)
		if not str(row.get("id", "")).is_empty():
			ready.append(row)
	_roster = ready
	_roster_error = ""
	_populate_collection()
	return true


func _active_row() -> Dictionary:
	var wanted := str(GameState.last_anima.get("id", ""))
	if wanted.is_empty():
		return {}
	for row in _roster:
		if str(row.get("id", "")) == wanted:
			return row
	return {}


func _sync_collection_preview(row: Dictionary, revision: int) -> void:
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return
	var res := await Backend.care_anima(anima_id, "sync")
	if not res.ok:
		print("collection care sync error: %s" % res.error)
		_collection_view.set_care_sync_error(revision)
		return

	var data := GameState.as_dict(res.data)
	var synced := normalize_anima_data(GameState.as_dict(data.get("anima")))
	if synced.is_empty():
		_collection_view.set_care_sync_error(revision)
		return
	_apply_care_response(data)
	_collection_view.apply_care_sync(synced, revision)


func _show_collection_profile(row: Dictionary) -> void:
	if row.is_empty() or _busy:
		return
	_switch_destination(BottomNav.ANIMA, row)


func _summon_collection_anima(row: Dictionary, care_synced: bool) -> void:
	if row.is_empty() or _busy:
		return
	_set_busy(true)
	_collection_view.set_sheet_busy(true)
	var loaded := await _prepare_anima_art(
		str(row.get("species_key", "")),
		str(row.get("color_bucket", "")),
		int(row.get("stage", 1))
	)
	if not bool(loaded.get("ok", false)):
		_collection_view.set_sheet_busy(false)
		_set_busy(false)
		return

	_switch_destination(BottomNav.HOME)
	await _anima.summon_dissolve()
	await _incubator.start_portal()
	_anima.apply(loaded)
	_anima.visible = false

	_current_anima = normalize_anima_data(row)
	_profile_anima = {}
	GameState.remember_anima({
		"id": str(_current_anima.get("id", "")),
		"nickname": str(_current_anima.get("nickname", "")),
		"species_key": str(_current_anima.get("species_key", "")),
		"color_bucket": str(_current_anima.get("color_bucket", "")),
		"stage": int(_current_anima.get("stage", 1)),
	})
	_upsert_roster(_current_anima)
	_refresh_stats()
	_populate_collection()
	await _incubator.burst()
	await _anima.summon_reveal()
	_refresh_care()
	if not care_synced:
		await _sync_active_care(false)
	_set_busy(false)
	_say(tr("COLLECTION_SUMMON_SUCCESS") % LocaleManager.display_name(_current_anima), true)


func _open_scan() -> void:
	_collection_view.close_sheet()
	_switch_destination(BottomNav.SCAN)


func _retry_roster() -> void:
	if _busy:
		return
	_set_busy(true)
	_set_home_shell_state(&"loading")
	_say(tr("STATUS_LOADING_COLLECTION"))
	var loaded := await _reload_roster()
	if loaded and not _roster.is_empty():
		var active := _active_row()
		await _present_row(active if not active.is_empty() else _roster[0])
	elif loaded:
		_set_home_shell_state(&"empty")
		_say(tr("STATUS_FIRST_SCAN"))
	else:
		_set_home_shell_state(&"error")
		_say(tr("STATUS_ROSTER_ERROR"))
	_set_busy(false)


func _show_delete_confirmation(anima_id: String) -> void:
	var details_row := _profile_anima if not _profile_anima.is_empty() else _current_anima
	if (
		_busy
		or anima_id.is_empty()
		or anima_id != str(details_row.get("id", ""))
	):
		return
	_pending_delete_id = anima_id
	_delete_anima_dialog.dialog_text = tr("ANIMA_DELETE_CONFIRM") % LocaleManager.display_name(
		details_row
	)
	_delete_anima_dialog.popup_centered()
	_delete_anima_dialog.get_cancel_button().grab_focus()


func _delete_confirmed() -> void:
	var anima_id := _pending_delete_id
	var details_row := _profile_anima if not _profile_anima.is_empty() else _current_anima
	if _busy or anima_id.is_empty() or anima_id != str(details_row.get("id", "")):
		return
	var deleted_name := LocaleManager.display_name(details_row)
	var deleted_active := anima_id == str(_current_anima.get("id", ""))
	_pending_delete_id = ""
	_set_busy(true)
	var res := await Backend.delete_anima(anima_id)
	if not res.ok or typeof(res.data) != TYPE_ARRAY or (res.data as Array).is_empty():
		_set_busy(false)
		_say(tr("ANIMA_DELETE_ERROR"), true)
		return

	var kept: Array[Dictionary] = []
	for row in _roster:
		if str(row.get("id", "")) != anima_id:
			kept.append(row)
	_roster = kept
	_profile_anima = {}
	if deleted_active:
		_current_anima = {}
		GameState.remember_anima({})
		_anima.sprite_frames = null
		_anima.visible = false
	await _reload_roster()
	if deleted_active and not _roster.is_empty():
		await _present_row(_roster[0])
	elif deleted_active:
		_refresh_stats()
		_refresh_care()
		_populate_collection()
		_switch_destination(BottomNav.HOME)
	else:
		_refresh_stats()
		_populate_collection()
		_switch_destination(BottomNav.COLLECTION)
	_set_busy(false)
	_say(tr("ANIMA_DELETE_SUCCESS") % deleted_name, true)


func _delete_canceled() -> void:
	_pending_delete_id = ""


func _show_hatch_rename(anima_id: String) -> void:
	if _busy or anima_id.is_empty() or anima_id != str(_current_anima.get("id", "")):
		return
	_pending_rename_id = anima_id
	_rename_anima_input.text = str(_current_anima.get("nickname", "")).strip_edges()
	_popup_rename()


func _popup_rename() -> void:
	if _pending_rename_id.is_empty():
		return
	_rename_anima_dialog.popup_centered()
	_rename_anima_input.grab_focus()
	_rename_anima_input.select_all()


func _rename_confirmed() -> void:
	var anima_id := _pending_rename_id
	var nickname := _rename_anima_input.text.strip_edges()
	if anima_id.is_empty() or anima_id != str(_current_anima.get("id", "")):
		return
	if nickname.is_empty():
		_say(tr("ANIMA_RENAME_EMPTY"), true)
		call_deferred("_popup_rename")
		return
	if _busy:
		call_deferred("_popup_rename")
		return

	_set_busy(true)
	var res := await Backend.rename_anima(anima_id, nickname)
	if not res.ok or typeof(res.data) != TYPE_ARRAY or (res.data as Array).is_empty():
		_set_busy(false)
		_say(tr("ANIMA_RENAME_ERROR"), true)
		call_deferred("_popup_rename")
		return

	_pending_rename_id = ""
	_current_anima["nickname"] = nickname
	_upsert_roster(_current_anima)
	var remembered := GameState.last_anima.duplicate(true)
	if str(remembered.get("id", "")) == anima_id:
		remembered["nickname"] = nickname
		GameState.remember_anima(remembered)
	_refresh_stats()
	_populate_collection()
	_set_busy(false)
	_say(tr("ANIMA_RENAME_SUCCESS") % nickname, true)


func _rename_submitted(_text: String) -> void:
	_rename_anima_dialog.hide()
	_rename_confirmed()


func _rename_canceled() -> void:
	_pending_rename_id = ""


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


func _perform_care(action: String) -> void:
	if _busy or _current_anima.is_empty():
		return
	if not GameState.pending_care.is_empty():
		_say(tr("ERROR_CARE_PENDING"), true)
		return

	var anima_id := str(_current_anima.get("id", ""))
	if anima_id.is_empty():
		return

	# Reaksi ini menyatakan intent pemain, bukan hasil transaksi. Meter, Bits,
	# sleep, dan care_score tetap menunggu row authoritative dari server.
	_home_view.set_busy(true)
	var pending := GameState.begin_care(anima_id, action)
	_anima.care_feedback(action)
	await _send_pending_care(pending, true)
	_home_view.set_busy(_busy)


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
		if _apply_care_response(GameState.as_dict(res.data)):
			_say(_care_success_message(action), show_feedback)
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
		_apply_care_response(GameState.as_dict(res.data))
	elif show_error:
		print("care sync error: %s" % res.error)
		_say(tr("ERROR_CARE_SYNC"), true)


func _apply_care_response(data: Dictionary) -> bool:
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
	_populate_collection()
	return true


func _care_success_message(action: String) -> String:
	match action:
		"feed":
			return tr("FEEDBACK_FEED")
		"clean":
			return tr("FEEDBACK_CLEAN")
		"play":
			return tr("FEEDBACK_PLAY")
		"sleep":
			return tr("FEEDBACK_SLEEP")
		"wake":
			return tr("FEEDBACK_WAKE")
		_:
			return tr("FEEDBACK_SYNCED")


func _care_error_message(error: String) -> String:
	match error:
		"NO_BITS":
			return tr("ERROR_NO_BITS")
		"NO_ENERGY":
			return tr("ERROR_NO_ENERGY")
		"BOND_FULL":
			return tr("ERROR_BOND_FULL")
		"NEED_FULL":
			return tr("ERROR_NEED_FULL")
		"ALREADY_SLEEPING":
			return tr("ERROR_ALREADY_SLEEPING")
		"NOT_SLEEPING":
			return tr("ERROR_NOT_SLEEPING")
		"ANIMA_NOT_READY":
			return tr("ERROR_ANIMA_NOT_READY")
		"ANIMA_NOT_FOUND":
			return tr("ERROR_ANIMA_NOT_FOUND")
		_:
			print("care error: %s" % error)
			return tr("ERROR_CARE_GENERIC")


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
	_dialog.title = tr("FILE_DIALOG_TITLE")
	_dialog.ok_button_text = tr("FILE_DIALOG_ACCEPT")
	_dialog.filters = PackedStringArray(["*.jpg,*.jpeg,*.png ; %s" % tr("FILE_DIALOG_FILTER")])
	if _picker != null:
		return
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


func _on_pick_pressed() -> void:
	if _busy:
		return
	_switch_destination(BottomNav.SCAN)
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
	_say(tr("STATUS_CAMERA_READ_ERROR"))


func _on_camera_denied(_permission: String) -> void:
	# resendPermission() tercantum di dokumentasi plugin tapi private di .aar yang
	# dirilis, jadi ia tidak bisa dipanggil dari sini. Permintaan izin berikutnya
	# menempel pada getCameraImage() berikutnya — jadi menekan tombolnya lagi
	# memang jalan pemulihannya, dan pemain harus diberi tahu itu. Tanpa kalimat
	# ini, satu penolakan terlihat seperti tombol yang rusak permanen.
	_say(tr("STATUS_CAMERA_PERMISSION"))


func _on_picker_error(message: String) -> void:
	print("camera error: %s" % message)
	_say(tr("STATUS_CAMERA_ERROR"))


## Jalur desktop. Tidak ada resize di sini, dan itu disengaja: FileDialog memberi
## file apa adanya, yang justru dibutuhkan saat menguji foto eval ukuran asli.
func _scan_file(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		print("photo read error: %s" % path)
		_say(tr("STATUS_PHOTO_READ_ERROR"))
		return
	_scan_bytes(bytes, path.get_extension().to_lower())


# ---------------------------------------------------------------- scan

func _scan_bytes(bytes: PackedByteArray, extension: String) -> void:
	if _busy:
		return
	_switch_destination(BottomNav.SCAN)
	_set_busy(true)

	if bytes.size() > MAX_FOTO_BYTE:
		# Ditolak di sini juga, bukan hanya oleh bucket: 6 MB yang ditolak setelah
		# terkirim adalah kuota data pemain yang terbuang tanpa alasan.
		_say(tr("STATUS_PHOTO_TOO_LARGE") % LocaleManager.format_megabytes(bytes.size()))
		_set_busy(false)
		return

	var is_png := extension == "png"
	_show_preview(bytes, is_png)
	var scan := GameState.begin_scan("png" if is_png else "jpg")

	_scan_view.set_phase(&"analyzing")
	_say(tr("STATUS_UPLOADING"))
	var up := await Backend.upload_photo(
		str(scan["photo_path"]), bytes, "image/png" if is_png else "image/jpeg"
	)
	if not up.ok:
		GameState.finish_scan()
		print("upload error: %s" % up.error)
		_say(tr("STATUS_UPLOAD_ERROR"))
		_restore_previous_anima()
		_set_busy(false)
		return

	# Fase satu. Belasan detik tanpa apa pun di layar sudah terasa seperti macet,
	# padahal ini bagian yang paling cepat.
	_say(tr("STATUS_ANALYZING"))
	var res := await Backend.create_anima(str(scan["photo_path"]), str(scan["idempotency_key"]))
	await _handle_create_result(res)
	_set_busy(false)


func _handle_create_result(res: Dictionary) -> void:
	await Backend.fetch_profile()
	_refresh_header()

	if not res.ok:
		match res.error:
			"NO_SCAN_CHARGE":
				_say(tr("STATUS_NO_SCAN_CHARGE"))
			"NO_CORE":
				# Hasil Vision sudah dibayar dan disimpan server sebagai Temuan
				# Tertunda, jadi ini bukan kerugian — pemain tidak perlu memfoto
				# ulang benda yang mungkin sudah tidak ada di dekatnya.
				_say(tr("STATUS_NO_CORE"))
			"SPEND_CAP":
				_say(tr("STATUS_SPEND_CAP"))
			_:
				print("create_anima error: %s" % res.error)
				_say(tr("STATUS_SCAN_ERROR"))
		GameState.finish_scan()
		_restore_previous_anima()
		return

	var data := GameState.as_dict(res.data)

	if str(data.get("gate", "")) == "rejected":
		_say(
			tr("STATUS_GATE_REJECTED") % LocaleManager.gate_reason(str(data.get("reason", "")))
		)
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
		_say(tr("STATUS_MISSING_ANIMA_ID"))
		_restore_previous_anima()
		return

	await _wait_for_hatch(anima_id)


# ---------------------------------------------------------------- inkubasi

func _wait_for_hatch(anima_id: String) -> void:
	_start_incubation()
	_say(tr("STATUS_SYNTHESIZING"))
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
				_say(tr("STATUS_GENERATION_FAILED"))
				await Backend.fetch_profile()
				_refresh_header()
				GameState.finish_scan()
				_restore_previous_anima()
				return

	# Bukan kegagalan: webhook mungkin masih jalan. Scan-nya tetap tersimpan.
	_say(tr("STATUS_GENERATION_PENDING"))
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
	var hatching := _incubator.is_active()
	var loaded := await _prepare_anima_art(
		species_key, color_bucket, stage, sheet_path, manifest
	)
	if not bool(loaded.get("ok", false)):
		if complete_scan:
			_restore_previous_anima()
		return
	_anima.apply(loaded)
	_anima.visible = not hatching

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
	_scan_view.clear_preview()
	_switch_destination(BottomNav.HOME)
	if hatching:
		_say(tr("STATUS_HATCHED"))
		await _incubator.burst()
		await _anima.hatch_reveal()
	else:
		_incubator.stop()
		_anima.visible = true
	if complete_scan:
		await _sync_active_care(false)
	_say(tr("STATUS_ANIMA_READY") % LocaleManager.display_name(_current_anima), true)
	if complete_scan:
		call_deferred("_show_hatch_rename", anima_id)


func _prepare_anima_art(
	species_key: String,
	color_bucket: String,
	stage: int,
	sheet_path: String = "",
	manifest: Dictionary = {}
) -> Dictionary:
	if species_key.is_empty() or color_bucket.is_empty():
		_say(tr("STATUS_SPECIES_DATA_ERROR"))
		return {"ok": false}

	if not GameState.has_sprite(species_key, color_bucket, stage):
		_say(tr("STATUS_DOWNLOADING_ART"))
		if manifest.is_empty() or sheet_path.is_empty():
			var art := await Backend.fetch_species_art(species_key, color_bucket, stage)
			if not art.ok or typeof(art.data) != TYPE_ARRAY or (art.data as Array).is_empty():
				print("art library error: %s" % art.error)
				_say(tr("STATUS_ART_LIBRARY_ERROR"))
				return {"ok": false}
			var row := GameState.as_dict((art.data as Array)[0])
			sheet_path = str(row.get("sheet_path", ""))
			manifest = GameState.as_dict(row.get("manifest"))

		var download := await Backend.download_sheet(sheet_path)
		if not download.ok:
			print("art download error: %s" % download.error)
			_say(tr("STATUS_ART_DOWNLOAD_ERROR"))
			return {"ok": false}

		var stored := GameState.store_sprite(
			species_key, color_bucket, stage, manifest, download.bytes
		)
		if not stored.ok:
			print("art save error: %s" % stored.error)
			_say(tr("STATUS_ART_SAVE_ERROR"))
			return {"ok": false}

	var loaded := AnimaLoader.load_from_manifest(
		GameState.manifest_path(species_key, color_bucket, stage)
	)
	if not loaded.get("ok", false):
		print("art load error: %s" % loaded.get("error", "?"))
		_say(tr("STATUS_ART_LOAD_ERROR"))
	return loaded


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
	_anima.visible = false
	_current_anima = anima.duplicate(true)
	_refresh_stats()
	_refresh_care()
	# last_anima hanya menyimpan pilihan terakhir, bukan care server-authoritative.
	# Menampilkan art cache di sini selalu memulai pose Idle dan membuat Anima yang
	# sedang tidur berkedip bangun sampai roster selesai dimuat. Art baru boleh
	# terlihat setelah _present() memiliki row server dan menerapkan pose care.


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
	if not is_instance_valid(_collection_view):
		return
	# ponytail: pass pertama membuat thumbnail cached secara sinkron. Plafon
	# sekitar 100 Anima lokal; kalau roster nyata melewatinya, simpan thumbnail
	# 128px terpisah saat sheet diunduh dan virtualisasikan daftar.
	var active_id := str(_current_anima.get("id", GameState.last_anima.get("id", "")))
	_collection_view.set_rows(_roster, active_id, _thumbnail_for)


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
	var details_row := _profile_anima if not _profile_anima.is_empty() else _current_anima
	_details_view.set_anima(
		details_row,
		_thumbnail_for(details_row) if not details_row.is_empty() else null
	)
	_home_view.set_anima(_current_anima, _busy)
	_first_anima_effect.set_active(_home_view.shell_state() == &"empty")
	_bottom_nav.set_busy(_busy, _details_available())


func _set_home_shell_state(state: StringName) -> void:
	_home_view.set_shell_state(state)
	_first_anima_effect.set_active(state == &"empty")
	if state != &"ready":
		_anima.visible = false


func _refresh_care() -> void:
	_schedule_sleep_completion()
	var has_care := typeof(_current_anima.get("care")) == TYPE_DICTIONARY
	if not has_care:
		_home_view.set_anima(_current_anima, _busy)
		return

	var sleeping := _is_sleeping(_current_anima)
	var dormant := _has_timestamp(_current_anima.get("dormant_since"))
	_home_view.update_care(_current_anima, _busy)
	if _profile_anima.is_empty():
		_details_view.set_anima(_current_anima, _thumbnail_for(_current_anima))
	if _anima.sprite_frames != null:
		_anima.apply_care_state(sleeping, dormant)


func _schedule_sleep_completion() -> void:
	if not is_instance_valid(_sleep_completion_timer):
		return
	_sleep_completion_timer.stop()
	var delay := sleep_completion_delay(_current_anima)
	if delay > 0.0:
		_sleep_completion_timer.start(delay)


func _sync_sleep_completion() -> void:
	if _sleep_sync_in_flight or not _is_sleeping(_current_anima):
		return
	if _busy or not GameState.pending_care.is_empty():
		_sleep_completion_timer.start(1.0)
		return

	var anima_id := str(_current_anima.get("id", ""))
	_sleep_sync_in_flight = true
	_home_view.set_busy(true)
	await _sync_active_care(false)
	_sleep_sync_in_flight = false
	if is_instance_valid(_home_view):
		_home_view.set_busy(_busy)
	if str(_current_anima.get("id", "")) != anima_id:
		_schedule_sleep_completion()
	elif _is_sleeping(_current_anima):
		# Jaringan bisa gagal atau jam server belum melewati batas persis.
		_sleep_completion_timer.start(SLEEP_SYNC_RETRY_SEC)


static func sleep_completion_delay(row: Dictionary) -> float:
	if not _has_timestamp(row.get("sleep_started_at")):
		return -1.0
	var started := _timestamp_seconds(row.get("sleep_started_at"))
	var synced := _timestamp_seconds(row.get("care_synced_at"))
	if started <= 0.0 or synced <= 0.0:
		return -1.0
	var elapsed := maxf(0.0, synced - started)
	return maxf(
		0.05,
		CARE_RULES.SLEEP_FULL_HOURS * 3600.0 - elapsed + SLEEP_SYNC_EPSILON_SEC
	)


static func _timestamp_seconds(value: Variant) -> float:
	var timestamp := str(value)
	if timestamp.is_empty():
		return -1.0
	return float(Time.get_unix_time_from_datetime_string(timestamp))


func _is_sleeping(row: Dictionary) -> bool:
	return _has_timestamp(row.get("sleep_started_at"))


static func _has_timestamp(value: Variant) -> bool:
	return value != null and not str(value).is_empty()


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

	_apply_margins(_safe_margin, insets, BASE_MARGIN, 24.0)
	_stage.position = stage_position_for(viewport_size, insets)


static func stage_position_for(viewport_size: Vector2, insets: Vector4) -> Vector2:
	var safe_top := insets.y
	var safe_bottom := viewport_size.y - insets.w
	return Vector2(viewport_size.x * 0.5, lerpf(safe_top, safe_bottom, 0.60))


func _apply_margins(node: MarginContainer, insets: Vector4, side: float, vertical: float) -> void:
	node.add_theme_constant_override("margin_left", int(side + insets.x))
	node.add_theme_constant_override("margin_top", int(vertical + insets.y))
	node.add_theme_constant_override("margin_right", int(side + insets.z))
	node.add_theme_constant_override("margin_bottom", int(vertical + insets.w))


func _switch_destination(destination: StringName, profile_row: Dictionary = {}) -> void:
	if destination == BottomNav.ANIMA and not profile_row.is_empty():
		_profile_anima = profile_row.duplicate(true)
	if destination == BottomNav.ANIMA and not _details_available():
		destination = BottomNav.HOME
	var previous := _destination
	if previous == BottomNav.COLLECTION and destination != BottomNav.COLLECTION:
		_collection_view.close_sheet()
	if destination == BottomNav.COLLECTION and previous != BottomNav.COLLECTION:
		_collection_view.begin_visit()
	if destination == BottomNav.ANIMA:
		if profile_row.is_empty():
			_profile_anima = _current_anima.duplicate(true)
	_destination = destination
	_home_view.visible = destination == BottomNav.HOME
	_scan_view.visible = destination == BottomNav.SCAN
	_collection_view.visible = destination == BottomNav.COLLECTION
	_details_view.visible = destination == BottomNav.ANIMA
	_bottom_nav.set_active(destination)
	if destination != BottomNav.HOME:
		_toast_revision += 1
		_status_panel.visible = false
	if destination == BottomNav.SCAN:
		if not _busy and not _incubator.is_active() and not _scan_view.has_preview():
			_scan_view.set_phase(&"idle")
			_scan_view.set_status(tr("STATUS_SCAN_READY"))

	var stage_destination := destination == BottomNav.HOME or (
		destination == BottomNav.SCAN and _incubator.is_active()
	)
	_stage.visible = stage_destination
	if destination == BottomNav.HOME:
		_anima.visible = _anima.sprite_frames != null and not _incubator.is_active()
	elif destination != BottomNav.SCAN:
		_anima.visible = false

	if destination == BottomNav.COLLECTION and not _roster_error.is_empty() and not _busy:
		_reload_roster()
	if destination == BottomNav.ANIMA:
		_refresh_stats()
	UiJuice.reveal(_active_view())


func _active_view() -> Control:
	match _destination:
		BottomNav.SCAN:
			return _scan_view
		BottomNav.COLLECTION:
			return _collection_view
		BottomNav.ANIMA:
			return _details_view
		_:
			return _home_view


func _details_available() -> bool:
	var row := _profile_anima if not _profile_anima.is_empty() else _current_anima
	return (
		not row.is_empty()
		and not GameState.as_dict(row.get("base_stats")).is_empty()
	)


func _refresh_localized_ui(_locale: String = "") -> void:
	_setup_picker()
	_delete_anima_dialog.title = tr("ANIMA_DELETE_TITLE")
	_delete_anima_dialog.ok_button_text = tr("ANIMA_DELETE_CONFIRM_ACTION")
	_delete_anima_dialog.cancel_button_text = tr("ACTION_CANCEL")
	_rename_anima_dialog.title = tr("ANIMA_RENAME_TITLE")
	_rename_anima_dialog.dialog_text = tr("ANIMA_RENAME_PROMPT")
	_rename_anima_dialog.ok_button_text = tr("ANIMA_RENAME_SAVE")
	_rename_anima_dialog.cancel_button_text = tr("ANIMA_RENAME_SKIP")
	_rename_anima_input.placeholder_text = tr("ANIMA_RENAME_PLACEHOLDER")
	_refresh_header()
	_refresh_stats()
	_refresh_care()
	_populate_collection()


func _show_core_info() -> void:
	UiJuice.show_overlay(_core_info_overlay, _core_info_panel)
	_core_info_close.grab_focus()


func _hide_core_info() -> void:
	await UiJuice.hide_overlay(_core_info_overlay, _core_info_panel)
	if is_instance_valid(_core_info_button):
		_core_info_button.grab_focus()


# ---------------------------------------------------------------- UI kecil

## Menampilkan foto yang akan dipindai, sekaligus mencetak ukurannya. Dimensi di
## log itu pemeriksaan termurah untuk resize dan rotasi: potret yang keluar
## sebagai lanskap berarti auto_rotate_image gagal di perangkat itu, dan tanpa ini
## kegagalannya cuma muncul sebagai stat yang aneh berbulan-bulan kemudian.
func _show_preview(bytes: PackedByteArray, is_png: bool) -> void:
	var image := Image.new()
	var err := image.load_png_from_buffer(bytes) if is_png else image.load_jpg_from_buffer(bytes)
	if err != OK:
		_scan_view.clear_preview()
		return
	_scan_view.show_preview(ImageTexture.create_from_image(image))
	# Foto dan Anima lama sama-sama hidup di area tengah. Menyembunyikan Anima
	# selama preview membuat orientasi foto terbaca jelas dan mencegah dua subjek
	# saling menutupi; Anima muncul lagi hanya setelah art berhasil dipresentasikan.
	_anima.visible = false
	_stage.visible = false
	print("foto: %d x %d, %.0f KB" % [image.get_width(), image.get_height(), bytes.size() / 1024.0])


func _start_incubation() -> void:
	_scan_view.clear_preview()
	_scan_view.set_phase(&"synthesizing")
	_first_anima_effect.set_active(false)
	_anima.visible = false
	_stage.visible = _destination == BottomNav.SCAN
	_incubator.start()


func _restore_previous_anima() -> void:
	_incubator.stop()
	_scan_view.clear_preview()
	_scan_view.set_phase(&"idle")
	_stage.visible = _destination == BottomNav.HOME
	_anima.visible = _destination == BottomNav.HOME and _anima.sprite_frames != null
	if _current_anima.is_empty():
		_set_home_shell_state(&"empty")


func _say(text: String, transient: bool = false) -> void:
	_toast_revision += 1
	var revision := _toast_revision
	_status.text = text
	_scan_view.set_status(text)
	if _destination == BottomNav.SCAN:
		_status_panel.visible = false
	else:
		_status_panel.visible = true
		UiJuice.pop(_status_panel, 1.025)
	print(text)
	if transient and _status_panel.visible:
		_hide_toast_later(revision)


func _hide_toast_later(revision: int) -> void:
	await get_tree().create_timer(2.8).timeout
	if revision == _toast_revision and is_instance_valid(_status_panel):
		_status_panel.visible = false


func _refresh_header() -> void:
	var p := GameState.profile
	if p.is_empty():
		_scan_count.text = tr("VALUE_UNAVAILABLE")
		_core_count.text = tr("VALUE_UNAVAILABLE")
		_bits_count.text = tr("VALUE_UNAVAILABLE")
		return
	_scan_count.text = LocaleManager.format_integer(int(p.get("scan_charges", 0)))
	_core_count.text = LocaleManager.format_integer(int(p.get("genesis_cores", 0)))
	_bits_count.text = LocaleManager.format_integer(int(p.get("bits", 0)))
	UiJuice.pop(_top_hud, 1.012)


func _set_busy(busy: bool) -> void:
	_busy = busy
	_scan_view.set_busy(busy)
	_home_view.set_busy(busy)
	_collection_view.set_busy(busy)
	_details_view.set_busy(busy)
	_bottom_nav.set_busy(busy, _details_available())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _core_info_overlay.visible:
			_hide_core_info()
			get_viewport().set_input_as_handled()
			return
		if _collection_view.is_sheet_open():
			_collection_view.close_sheet()
			get_viewport().set_input_as_handled()
			return
		if _destination != BottomNav.HOME:
			_switch_destination(BottomNav.HOME)
			get_viewport().set_input_as_handled()
			return
	if (
		_destination == BottomNav.HOME
		and not _busy
		and event is InputEventMouseButton
		and event.pressed
		and _anima.sprite_frames != null
	):
		_anima.hop()


func _capture_and_quit(path: String) -> void:
	# Let transient feedback clear so visual snapshots show the layout underneath,
	# not whichever boot message happened to be last.
	await get_tree().create_timer(3.0).timeout
	for _i in 2:
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
		_say(tr("STATUS_HATCH_DEMO_MISSING"))
		return
	_switch_destination(BottomNav.SCAN)
	_set_busy(true)
	_start_incubation()
	_say(tr("STATUS_INCUBATOR_DEMO"))
	await get_tree().create_timer(1.8).timeout
	_switch_destination(BottomNav.HOME)
	await _incubator.burst()
	await _anima.hatch_reveal()
	_set_busy(false)
	_say(tr("STATUS_HATCH_DEMO_DONE"), true)


func _run_collection_sheet_demo() -> void:
	var demo := _current_anima.duplicate(true)
	if demo.is_empty():
		demo = {
			"species_key": "demo_companion",
			"color_bucket": "cool_blue",
			"stage": 1,
			"element": "spark",
			"rarity": 4,
		}
	demo.merge({
		"id": "collection-sheet-demo",
		"nickname": "Velumi",
		"base_stats": {"hp": 74, "atk": 62, "def": 58, "spd": 81, "special": 77},
		"care": {"hunger": 68, "energy": 84, "hygiene": 57, "bond": 72},
	}, true)
	var rows: Array[Dictionary] = [demo]
	_collection_view.set_rows(rows, str(_current_anima.get("id", "")), _thumbnail_for)
	_switch_destination(BottomNav.COLLECTION)
	_collection_view.show_preview(demo, false)


func _run_empty_demo() -> void:
	_current_anima = {}
	_profile_anima = {}
	_collection_view.set_rows([], "", _thumbnail_for)
	_switch_destination(BottomNav.HOME)
	_set_home_shell_state(&"empty")


func _run_summon_demo() -> void:
	if _anima.sprite_frames == null:
		_say(tr("STATUS_HATCH_DEMO_MISSING"))
		return
	_switch_destination(BottomNav.HOME)
	_set_busy(true)
	await _anima.summon_dissolve()
	await _incubator.start_portal()
	await _incubator.burst()
	await _anima.summon_reveal()
	_refresh_care()
	_set_busy(false)
