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
@onready var _animas_chip = %AnimasChip
@onready var _cores_chip = %CoresChip
@onready var _bits_chip = %BitsChip
@onready var _shell_modal = %ShellModal
@onready var _home_view: HomeView = %HomeView
@onready var _scan_view: ScanView = %ScanView
@onready var _battle_view = %BattleView
@onready var _collection_view: CollectionView = %CollectionView
@onready var _details_view: AnimaDetailsView = %AnimaDetailsView
@onready var _bottom_nav: BottomNav = %BottomNav
@onready var _level_up_banner: Control = %LevelUpBanner
@onready var _level_up_title: Label = %LevelUpTitle
@onready var _level_up_label: Label = %LevelUpLabel

var _busy := false
var _roster: Array[Dictionary] = []
var _current_anima: Dictionary = {}
var _profile_anima: Dictionary = {}
var _roster_error := ""
var _placeholder_icon: Texture2D = null
var _thumbnail_cache: Dictionary = {}
var _destination: StringName = BottomNav.HOME
var _toast_revision := 0
var _level_up_revision := 0
var _level_up_tween: Tween
var _last_care_delta := 0
var _battle_reward_revision := 0
var _sleep_completion_timer: Timer = null
var _sleep_sync_in_flight := false
var _pending_delete_id := ""
var _pending_rename_id := ""
var _pending_rename_text := ""
var _modal_context := &""
var _last_anima_press_ms := -1000
var _last_anima_press_position := Vector2(-1000.0, -1000.0)

## Singleton plugin Android, null di desktop dan di test headless.
var _picker: Object = null


func _ready() -> void:
	_sleep_completion_timer = Timer.new()
	_sleep_completion_timer.name = "SleepCompletionTimer"
	_sleep_completion_timer.one_shot = true
	add_child(_sleep_completion_timer)
	_sleep_completion_timer.timeout.connect(_sync_sleep_completion)
	_scan_view.scan_requested.connect(_on_pick_pressed)
	_battle_view.start_requested.connect(_start_battle)
	_battle_view.action_requested.connect(_battle_action_requested)
	_battle_view.resume_requested.connect(_retry_battle)
	_battle_view.forfeit_requested.connect(_forfeit_battle)
	_battle_view.reward_status_refresh_requested.connect(_refresh_battle_reward_status)
	_home_view.care_requested.connect(_perform_care)
	_home_view.first_scan_requested.connect(_open_scan)
	_home_view.retry_requested.connect(_retry_roster)
	_collection_view.preview_requested.connect(_sync_collection_preview)
	_collection_view.profile_requested.connect(_show_collection_profile)
	_collection_view.summon_requested.connect(_summon_collection_anima)
	_collection_view.first_scan_requested.connect(_open_scan)
	_collection_view.retry_requested.connect(_retry_roster)
	_details_view.rename_requested.connect(_show_rename)
	_details_view.delete_requested.connect(_show_delete_confirmation)
	_details_view.help_requested.connect(_show_details_help)
	_bottom_nav.destination_selected.connect(_switch_destination)
	_shell_modal.confirmed.connect(_modal_confirmed)
	_shell_modal.canceled.connect(_modal_canceled)
	_animas_chip.pressed.connect(_open_collection)
	_cores_chip.pressed.connect(_show_core_info)
	_bits_chip.pressed.connect(_show_bits_info)
	LocaleManager.locale_changed.connect(_refresh_localized_ui)
	_configure_resource_chips()
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
			_scan_view.set_phase(&"analyzing")
		if arg == "--collection":
			_switch_destination(BottomNav.COLLECTION)
		if arg == "--stats":
			_switch_destination(BottomNav.ANIMA)
		if arg == "--core-info":
			_show_core_info()
		if arg == "--bits-info":
			_show_bits_info()
		if arg == "--rename-demo" and not _current_anima.is_empty():
			_show_rename(str(_current_anima.get("id", "")))
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
		if arg == "--collection-sheet-loading-demo":
			_run_collection_sheet_demo(true)
		if arg == "--profile-demo":
			_run_profile_help_demo(false)
		if arg == "--profile-help-demo":
			_run_profile_help_demo()
		if arg == "--home-tap-demo" and _anima.sprite_frames != null:
			await _run_home_tap_demo()
		if arg == "--level-up-demo":
			_celebrate_level_up(4, 3)
		if arg == "--empty-demo":
			_run_empty_demo()
		if arg == "--summon-demo":
			await _run_summon_demo()
		if arg == "--battle-demo":
			_run_battle_demo()
		if arg == "--battle-pending-demo":
			_run_battle_demo()
			_battle_view.begin_action("surge")
		if arg == "--battle-effective-demo":
			_run_battle_demo("active", false, 1.5)
		if arg == "--battle-result-demo":
			_run_battle_demo("forfeited")
		if arg == "--battle-win-demo":
			_run_battle_demo("won")
		if arg == "--battle-training-active-demo":
			_run_battle_demo("active", true)
		if arg == "--battle-training-demo":
			_run_battle_training_demo()
		if arg.begins_with("--screenshot="):
			await _capture_and_quit(arg.trim_prefix("--screenshot="))


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_RESUMED or not is_node_ready():
		return
	if is_instance_valid(_sleep_completion_timer) and _is_sleeping(_current_anima):
		_sleep_completion_timer.stop()
		call_deferred("_sync_sleep_completion")
	if _destination == BottomNav.BATTLE:
		call_deferred("_refresh_battle_reward_status")


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
	if not GameState.pending_battle.is_empty() and GameState.pending_scan.is_empty():
		_switch_destination(BottomNav.BATTLE)
		await _resume_battle()


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
	_modal_context = &"delete"
	_shell_modal.open_confirm(
		tr("ANIMA_DELETE_TITLE"),
		tr("ANIMA_DELETE_CONFIRM") % LocaleManager.display_name(details_row),
		tr("ANIMA_DELETE_CONFIRM_ACTION"),
		tr("ACTION_CANCEL"),
		true
	)


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


func _show_rename(anima_id: String) -> void:
	var target := _current_anima
	if anima_id == str(_profile_anima.get("id", "")):
		target = _profile_anima
	if _busy or anima_id.is_empty() or anima_id != str(target.get("id", "")):
		return
	_pending_rename_id = anima_id
	_pending_rename_text = str(target.get("nickname", "")).strip_edges()
	_popup_rename()


func _popup_rename() -> void:
	if _pending_rename_id.is_empty():
		return
	_modal_context = &"rename"
	_shell_modal.open_input(
		tr("ANIMA_RENAME_TITLE"),
		tr("ANIMA_RENAME_PROMPT"),
		_pending_rename_text,
		tr("ANIMA_RENAME_SAVE"),
		tr("ACTION_CANCEL"),
		tr("ANIMA_RENAME_PLACEHOLDER")
	)


func _rename_confirmed(submitted_text: String) -> void:
	var anima_id := _pending_rename_id
	var nickname := submitted_text.strip_edges()
	_pending_rename_text = submitted_text
	var target := _current_anima
	if anima_id == str(_profile_anima.get("id", "")):
		target = _profile_anima
	if anima_id.is_empty() or anima_id != str(target.get("id", "")):
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
	target["nickname"] = nickname
	if anima_id == str(_current_anima.get("id", "")):
		_current_anima["nickname"] = nickname
	if anima_id == str(_profile_anima.get("id", "")):
		_profile_anima["nickname"] = nickname
	_upsert_roster(target)
	var remembered := GameState.last_anima.duplicate(true)
	if str(remembered.get("id", "")) == anima_id:
		remembered["nickname"] = nickname
		GameState.remember_anima(remembered)
	_refresh_stats()
	_populate_collection()
	_set_busy(false)
	_say(tr("ANIMA_RENAME_SUCCESS") % nickname, true)


func _modal_confirmed(text: String) -> void:
	var context := _modal_context
	_modal_context = &""
	match context:
		&"delete":
			_delete_confirmed()
		&"rename":
			_rename_confirmed(text)
		&"core_info":
			_cores_chip.grab_action_focus()
		&"bits_info":
			_bits_chip.grab_action_focus()


func _modal_canceled() -> void:
	var context := _modal_context
	_modal_context = &""
	if context == &"delete":
		_pending_delete_id = ""
	elif context == &"rename":
		_pending_rename_id = ""
		_pending_rename_text = ""
	elif context == &"core_info":
		_cores_chip.grab_action_focus()
	elif context == &"bits_info":
		_bits_chip.grab_action_focus()


func _show_details_help(title: String, body: String) -> void:
	_modal_context = &"details_help"
	_shell_modal.open_info(title, body, tr("CORE_INFO_CLOSE"))


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
			if show_feedback and not _level_up_banner.visible:
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

	var previous_score := -1
	_last_care_delta = 0
	if str(_current_anima.get("id", "")) == anima_id:
		previous_score = int(_current_anima.get("care_score", -1))

	if data.has("bits"):
		GameState.profile["bits"] = int(data.get("bits", 0))
		_refresh_header()
	_upsert_roster(row)

	if str(_current_anima.get("id", "")) == anima_id:
		_current_anima = row
		_refresh_stats()
		_refresh_care()
		var new_score := int(row.get("care_score", 0))
		if previous_score >= 0:
			_last_care_delta = new_score - previous_score
		_maybe_celebrate_level(previous_score, new_score)
	_populate_collection()
	return true


func _care_success_message(action: String) -> String:
	match action:
		"feed":
			return tr("FEEDBACK_FEED")
		"clean":
			return tr("FEEDBACK_CLEAN")
		"play":
			return tr("FEEDBACK_PLAY") if _last_care_delta > 0 else tr("FEEDBACK_PLAY_CAPPED")
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


# ---------------------------------------------------------------- battle

func _refresh_battle_reward_status() -> void:
	if _destination != BottomNav.BATTLE:
		return
	_battle_reward_revision += 1
	var revision := _battle_reward_revision
	var session_before: Dictionary = _battle_view.session_data()
	var session_id := str(session_before.get("id", ""))
	var session_version := int(session_before.get("version", 0))
	var payload := {}
	if not session_id.is_empty():
		payload["session_id"] = session_id
	var res := await Backend.battle_anima("status", payload)
	if revision != _battle_reward_revision or _destination != BottomNav.BATTLE:
		return
	var session_after: Dictionary = _battle_view.session_data()
	if (
		str(session_after.get("id", "")) != session_id
		or int(session_after.get("version", 0)) != session_version
	):
		return
	if not res.ok:
		_battle_view.set_daily_reward_error()
		return
	var daily_reward := GameState.as_dict(res.data)
	if daily_reward.is_empty():
		_battle_view.set_daily_reward_error()
		return
	_battle_view.set_daily_reward(daily_reward)


func _start_battle() -> void:
	if _busy or _current_anima.is_empty():
		return
	_battle_reward_revision += 1
	_set_busy(true)
	_battle_view.set_loading()
	var res := await Backend.battle_anima("start", {
		"anima_id": str(_current_anima.get("id", "")),
	})
	if not res.ok:
		_battle_view.set_error(res.error)
		_set_busy(false)
		return

	var session := GameState.as_dict(res.data)
	if session.is_empty():
		_battle_view.set_error("BATTLE_NOT_FOUND")
		_set_busy(false)
		return
	GameState.remember_battle(
		str(session.get("id", "")),
		int(session.get("turn_number", 1)),
		int(session.get("version", 1))
	)
	await _show_battle_session(session)
	await _sync_active_care(false)
	_set_busy(false)


func _resume_battle() -> void:
	if _busy:
		return
	_battle_reward_revision += 1
	var pending := GameState.pending_battle.duplicate(true)
	var session_id := str(pending.get("session_id", ""))
	if session_id.is_empty():
		_battle_view.set_lobby(_current_anima)
		return

	_set_busy(true)
	_battle_view.set_loading("BATTLE_RESUMING")
	var res := await Backend.battle_anima("resume", {"session_id": session_id})
	if not res.ok and res.error == "BATTLE_NOT_FOUND":
		GameState.finish_battle()
		_battle_view.set_lobby(_current_anima)
		_set_busy(false)
		return
	if not res.ok:
		_battle_view.set_error(res.error)
		_set_busy(false)
		return

	var session := GameState.as_dict(res.data)
	if not await _show_battle_session(session):
		_set_busy(false)
		return
	var replay_action := str(pending.get("action", ""))
	var should_replay := (
		not replay_action.is_empty()
		and str(session.get("status", "")) == "active"
		and int(session.get("turn_number", 0)) == int(pending.get("expected_turn", -1))
		and int(session.get("version", 0)) == int(pending.get("expected_version", -1))
	)
	if should_replay:
		_set_busy(false)
		await _submit_pending_battle(pending)
	else:
		GameState.confirm_battle_response(session)
		if str(session.get("status", "")) != "active":
			await _refresh_battle_authority(session)
		_set_busy(false)


func _retry_battle() -> void:
	if GameState.pending_battle.is_empty():
		await _start_battle()
	else:
		await _resume_battle()


func _battle_action_requested(action: String) -> void:
	if _busy:
		return
	var session: Dictionary = _battle_view.session_data()
	if session.is_empty() or str(session.get("status", "")) != "active":
		return
	var pending := GameState.begin_battle_action(
		str(session.get("id", "")),
		int(session.get("turn_number", 1)),
		int(session.get("version", 1)),
		action
	)
	await _submit_pending_battle(pending)


func _submit_pending_battle(pending: Dictionary) -> void:
	if pending.is_empty():
		return
	_battle_reward_revision += 1
	_battle_view.begin_action(str(pending.get("action", "")))
	_set_busy(true)
	var res := await Backend.battle_anima("turn", {
		"session_id": str(pending.get("session_id", "")),
		"expected_turn": int(pending.get("expected_turn", 1)),
		"expected_version": int(pending.get("expected_version", 1)),
		"action": str(pending.get("action", "")),
		"idempotency_key": str(pending.get("idempotency_key", "")),
	})
	if not res.ok:
		if res.error == "STALE_BATTLE" or res.error == "BATTLE_FINISHED":
			_set_busy(false)
			await _resume_battle()
			return
		if res.code >= 400:
			var session: Dictionary = _battle_view.session_data()
			if not session.is_empty():
				GameState.remember_battle(
					str(session.get("id", "")),
					int(session.get("turn_number", 1)),
					int(session.get("version", 1))
				)
		_battle_view.set_error(res.error)
		_set_busy(false)
		return

	var data := GameState.as_dict(res.data)
	var next_session := GameState.as_dict(data.get("session"))
	var events: Array = data.get("events", []) if typeof(data.get("events")) == TYPE_ARRAY else []
	if next_session.is_empty():
		_battle_view.set_error("BATTLE_NOT_FOUND")
		_set_busy(false)
		return
	await _battle_view.play_events(events, next_session)
	GameState.confirm_battle_response(next_session)
	await _apply_battle_reward(GameState.as_dict(data.get("reward")), next_session)
	_set_busy(false)


func _forfeit_battle() -> void:
	if _busy:
		return
	_battle_reward_revision += 1
	var session: Dictionary = _battle_view.session_data()
	var session_id := str(session.get("id", GameState.pending_battle.get("session_id", "")))
	if session_id.is_empty():
		return
	_set_busy(true)
	var res := await Backend.battle_anima("forfeit", {"session_id": session_id})
	if res.ok:
		var closed := GameState.as_dict(res.data)
		GameState.finish_battle()
		_battle_view.set_session(closed)
	else:
		_battle_view.set_error(res.error)
	_set_busy(false)


func _show_battle_session(session: Dictionary) -> bool:
	if session.is_empty():
		_battle_view.set_error("BATTLE_NOT_FOUND")
		return false
	var player_snapshot := GameState.as_dict(session.get("player_snapshot"))
	var bot_snapshot := GameState.as_dict(session.get("bot_snapshot"))
	var player_loaded := await _prepare_battle_art(player_snapshot)
	if not bool(player_loaded.get("ok", false)):
		_battle_view.set_error("BATTLE_ERROR_GENERIC")
		return false
	var bot_loaded := await _prepare_battle_art(bot_snapshot)
	if not bool(bot_loaded.get("ok", false)):
		_battle_view.set_error("BATTLE_ERROR_GENERIC")
		return false
	_battle_view.set_session(session, player_loaded, bot_loaded)
	return true


func _prepare_battle_art(snapshot: Dictionary) -> Dictionary:
	return await _prepare_anima_art(
		str(snapshot.get("species_key", "")),
		str(snapshot.get("color_bucket", "")),
		int(snapshot.get("stage", 1)),
		str(snapshot.get("sheet_path", "")),
		GameState.as_dict(snapshot.get("manifest")),
		false
	)


func _apply_battle_reward(reward: Dictionary, session: Dictionary) -> void:
	var bits_delta := int(reward.get("bits", 0))
	var care_delta := int(reward.get("care_score", 0))
	var wins_delta := int(reward.get("battle_wins", 0))
	if bits_delta == 0 and care_delta == 0 and wins_delta == 0:
		return
	# Replay sesudah restart bisa membawa delta reward yang sama sementara profil
	# sudah memuat saldo baru. Baca row authoritative agar UI tidak menambah dua kali.
	await _refresh_battle_authority(session)


func _refresh_battle_authority(session: Dictionary) -> void:
	var anima_id := str(session.get("player_anima_id", ""))
	var previous_score := (
		int(_current_anima.get("care_score", -1))
		if str(_current_anima.get("id", "")) == anima_id
		else -1
	)
	await Backend.fetch_profile()
	await _reload_roster()
	for row in _roster:
		if str(row.get("id", "")) != anima_id:
			continue
		if str(_current_anima.get("id", "")) == anima_id:
			_current_anima = row.duplicate(true)
		break
	_refresh_header()
	_refresh_stats()
	_refresh_care()
	_populate_collection()
	_maybe_celebrate_level(previous_score, int(_current_anima.get("care_score", 0)))


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
	await _sync_active_care(false)
	if _is_sleeping(_current_anima):
		_say(tr("STATUS_ANIMA_SLEEPING") % LocaleManager.display_name(_current_anima), true)
	else:
		_say(tr("STATUS_ANIMA_READY") % LocaleManager.display_name(_current_anima), true)
	if complete_scan:
		call_deferred("_show_rename", anima_id)


func _prepare_anima_art(
	species_key: String,
	color_bucket: String,
	stage: int,
	sheet_path: String = "",
	manifest: Dictionary = {},
	report_status: bool = true
) -> Dictionary:
	if species_key.is_empty() or color_bucket.is_empty():
		if report_status:
			_say(tr("STATUS_SPECIES_DATA_ERROR"))
		return {"ok": false}

	if not GameState.has_sprite(species_key, color_bucket, stage):
		if report_status:
			_say(tr("STATUS_DOWNLOADING_ART"))
		if manifest.is_empty() or sheet_path.is_empty():
			var art := await Backend.fetch_species_art(species_key, color_bucket, stage)
			if not art.ok or typeof(art.data) != TYPE_ARRAY or (art.data as Array).is_empty():
				print("art library error: %s" % art.error)
				if report_status:
					_say(tr("STATUS_ART_LIBRARY_ERROR"))
				return {"ok": false}
			var row := GameState.as_dict((art.data as Array)[0])
			sheet_path = str(row.get("sheet_path", ""))
			manifest = GameState.as_dict(row.get("manifest"))

		var download := await Backend.download_sheet(sheet_path)
		if not download.ok:
			print("art download error: %s" % download.error)
			if report_status:
				_say(tr("STATUS_ART_DOWNLOAD_ERROR"))
			return {"ok": false}

		var stored := GameState.store_sprite(
			species_key, color_bucket, stage, manifest, download.bytes
		)
		if not stored.ok:
			print("art save error: %s" % stored.error)
			if report_status:
				_say(tr("STATUS_ART_SAVE_ERROR"))
			return {"ok": false}

	var loaded := AnimaLoader.load_from_manifest(
		GameState.manifest_path(species_key, color_bucket, stage)
	)
	if not loaded.get("ok", false):
		print("art load error: %s" % loaded.get("error", "?"))
		if report_status:
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
	_refresh_anima_count()
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
	if _battle_view.session_data().is_empty() and GameState.pending_battle.is_empty():
		_battle_view.set_lobby(_current_anima)
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
	if _battle_view.session_data().is_empty() and GameState.pending_battle.is_empty():
		_battle_view.set_lobby(_current_anima)
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


func _switch_destination(
	destination: StringName,
	profile_row: Dictionary = {},
	refresh_battle_reward: bool = true
) -> void:
	_battle_reward_revision += 1
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
	_battle_view.visible = destination == BottomNav.BATTLE
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
	if (
		destination == BottomNav.BATTLE
		and GameState.pending_battle.is_empty()
		and refresh_battle_reward
	):
		_battle_view.set_lobby(_current_anima)
		_refresh_battle_reward_status()

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
		BottomNav.BATTLE:
			return _battle_view
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
	_configure_resource_chips()
	_details_view.refresh_localized_ui()
	_refresh_header()
	_refresh_stats()
	_refresh_care()
	_populate_collection()


func _show_core_info() -> void:
	_modal_context = &"core_info"
	_shell_modal.open_info(
		tr("CORE_INFO_TITLE"),
		tr("CORE_INFO_BODY"),
		tr("CORE_INFO_CLOSE")
	)


func _show_bits_info() -> void:
	_modal_context = &"bits_info"
	_shell_modal.open_info(
		tr("BITS_INFO_TITLE"),
		tr("BITS_INFO_BODY"),
		tr("CORE_INFO_CLOSE")
	)


func _open_collection() -> void:
	_switch_destination(BottomNav.COLLECTION)


func _configure_resource_chips() -> void:
	_animas_chip.set_name_text(tr("RESOURCE_ANIMAS"))
	_animas_chip.set_interactive(true, tr("COLLECTION_TITLE"))
	_cores_chip.set_name_text(tr("RESOURCE_CORES"))
	_cores_chip.set_interactive(true, tr("CORE_INFO_TITLE"))
	_bits_chip.set_name_text(tr("RESOURCE_BITS"))
	_bits_chip.set_interactive(true, tr("BITS_INFO_TITLE"))


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


func _maybe_celebrate_level(previous_score: int, new_score: int) -> void:
	if previous_score < 0:
		return
	var new_level: int = CARE_RULES.leveled_up(previous_score, new_score)
	if new_level > 0:
		_celebrate_level_up(new_level, CARE_RULES.level_from_exp(previous_score))


# ponytail: one shell banner, not a per-screen fanfare. Plafon: no particles;
# reuse Super Effective typography. Upgrade to Incubator-style burst if form
# jumps (16/36) later get evolve art.
func _celebrate_level_up(level: int, previous_level: int) -> void:
	if not is_instance_valid(_level_up_banner):
		return
	_status_panel.visible = false
	_level_up_title.text = tr("LEVEL_UP")
	if CARE_RULES.form_key(level) != CARE_RULES.form_key(previous_level):
		_level_up_label.text = tr("LEVEL_UP_FORM") % [
			LocaleManager.level_label(level),
			LocaleManager.form_name(level),
		]
	else:
		_level_up_label.text = tr("LEVEL_UP_TO") % LocaleManager.format_integer(level)
	_level_up_banner.visible = true
	_level_up_banner.pivot_offset = _level_up_banner.size * 0.5
	_home_view.pulse_progress()
	if is_instance_valid(_anima) and _anima.visible:
		_anima.celebrate_level_up()
	Input.vibrate_handheld(70)
	if is_instance_valid(_level_up_tween):
		_level_up_tween.kill()
	if UiMotion.reduced_motion:
		_level_up_banner.modulate = Color.WHITE
		_level_up_banner.scale = Vector2.ONE
	else:
		_level_up_banner.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_level_up_banner.scale = Vector2(0.72, 0.72)
		_level_up_tween = create_tween()
		_level_up_tween.tween_property(_level_up_banner, "modulate:a", 1.0, 0.10)
		_level_up_tween.parallel().tween_property(
			_level_up_banner, "scale", Vector2(1.06, 1.06), 0.18
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_level_up_tween.chain().tween_property(_level_up_banner, "scale", Vector2.ONE, 0.12)
	_level_up_revision += 1
	var revision := _level_up_revision
	_hide_level_up_later(revision)


func _hide_level_up_later(revision: int) -> void:
	await get_tree().create_timer(1.8).timeout
	if revision != _level_up_revision or not is_instance_valid(_level_up_banner):
		return
	if UiMotion.reduced_motion:
		_level_up_banner.visible = false
		return
	if is_instance_valid(_level_up_tween):
		_level_up_tween.kill()
	_level_up_tween = create_tween()
	_level_up_tween.tween_property(_level_up_banner, "modulate:a", 0.0, 0.22)
	await _level_up_tween.finished
	if revision == _level_up_revision and is_instance_valid(_level_up_banner):
		_level_up_banner.visible = false
		_level_up_banner.modulate = Color.WHITE
		_level_up_banner.scale = Vector2.ONE


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
		_animas_chip.set_value_text(tr("VALUE_UNAVAILABLE"))
		_cores_chip.set_value_text(tr("VALUE_UNAVAILABLE"))
		_bits_chip.set_value_text(tr("VALUE_UNAVAILABLE"))
		return
	_cores_chip.set_value_text(LocaleManager.format_integer(int(p.get("genesis_cores", 0))))
	_bits_chip.set_value_text(LocaleManager.format_integer(int(p.get("bits", 0))))
	UiJuice.pop(_top_hud, 1.012)


func _refresh_anima_count() -> void:
	if is_instance_valid(_animas_chip):
		_animas_chip.set_value_text(LocaleManager.format_integer(_roster.size()))


func _set_busy(busy: bool) -> void:
	_busy = busy
	_scan_view.set_busy(busy)
	_battle_view.set_busy(busy)
	_home_view.set_busy(busy)
	_collection_view.set_busy(busy)
	_details_view.set_busy(busy)
	_bottom_nav.set_busy(busy, _details_available())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _collection_view.is_sheet_open():
			_collection_view.close_sheet()
			get_viewport().set_input_as_handled()
			return
		if _destination != BottomNav.HOME:
			_switch_destination(BottomNav.HOME)
			get_viewport().set_input_as_handled()
			return
	_try_home_anima_tap(event)


func _try_home_anima_tap(event: InputEvent) -> void:
	if _destination != BottomNav.HOME or _busy or _anima.sprite_frames == null:
		return
	var press_position := Vector2(-1.0, -1.0)
	if event is InputEventScreenTouch and event.pressed:
		press_position = event.position
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		press_position = event.position
	else:
		return

	var now := Time.get_ticks_msec()
	if (
		now - _last_anima_press_ms < 180
		and press_position.distance_to(_last_anima_press_position) < 24.0
	):
		return
	_last_anima_press_ms = now
	_last_anima_press_position = press_position
	if _anima.hit_test(press_position):
		_anima.react_to_tap()
		get_viewport().set_input_as_handled()


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


func _run_collection_sheet_demo(show_loading: bool = false) -> void:
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
	if show_loading:
		_collection_view.show_preview_loading(demo)
	else:
		_collection_view.show_preview(demo, false)


## Tap demo lewat push_input, bukan react_to_tap() langsung: yang dulu rusak adalah
## routing GUI, dan hanya event sungguhan yang membuktikan tap sampai ke sprite.
func _run_home_tap_demo() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = _anima.get_global_transform_with_canvas() * _anima.offset
	get_viewport().push_input(event)
	await get_tree().create_timer(0.09).timeout
	print("home tap demo: tap=%s reaction=%s" % [event.position, _anima.position])


func _run_profile_help_demo(show_help: bool = true) -> void:
	var demo := _current_anima.duplicate(true)
	if demo.is_empty():
		demo = {
			"id": "profile-help-demo",
			"nickname": "Velumi",
			"species_key": "demo_companion",
			"color_bucket": "cool_blue",
			"stage": 1,
			"element": "spark",
			"rarity": 4,
			"care_score": 28,
			"base_stats": {"hp": 74, "atk": 62, "def": 58, "spd": 81, "special": 77},
		}
	_switch_destination(BottomNav.ANIMA, demo)
	_refresh_stats()
	if show_help:
		_show_details_help(tr("STAT_SPD"), tr("STAT_SPD_HELP"))


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


func _run_battle_demo(
	status: String = "active", training: bool = false, effectiveness: float = 0.0
) -> void:
	var placeholder := PlaceholderSheet.build()
	var texture := ImageTexture.create_from_image(placeholder["image"])
	var loaded := AnimaLoader.build(texture, placeholder["manifest"])
	var session := {
		"id": "battle-demo",
		"status": status,
		"turn_number": 3,
		"version": 2,
		"player_snapshot": {
			"anima_id": "battle-demo-player",
			"name": str(_current_anima.get("nickname", tr("ANIMA_FALLBACK_NAME"))),
			"element": "spark",
			"stage": 1,
		},
		"bot_snapshot": {
			"anima_id": "battle-demo-bot",
			"element": "flow",
			"stage": 1,
		},
		"daily_reward": {
			"earned": 7 if training else (3 if status == "won" else 2),
			"limit": 3,
			"remaining": 0 if training or status == "won" else 1,
			"rewarded": status == "won" and not training,
		},
		"state": {
			"status": status,
			"player": {"hp": 162, "max_hp": 240, "momentum": 2},
			"bot": {"hp": 118, "max_hp": 228, "momentum": 1},
		},
	}
	_switch_destination(BottomNav.BATTLE, {}, false)
	_battle_view.set_session(session, loaded, loaded)
	if not is_zero_approx(effectiveness):
		_battle_view.call("_show_effectiveness", effectiveness)


func _run_battle_training_demo() -> void:
	_switch_destination(BottomNav.BATTLE, {}, false)
	_battle_view.set_lobby(_current_anima)
	_battle_view.set_daily_reward({
		"earned": 3,
		"limit": 3,
		"remaining": 0,
		"rewarded": false,
		"server_now": "2026-08-13T12:00:00Z",
		"reset_at": "2026-08-14T00:00:00Z",
	})
