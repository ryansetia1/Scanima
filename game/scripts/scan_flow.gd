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
## Galeri sekarang tersedia lewat PhotoSourceSheet; kamera tetap default di perangkat
## yang punya lensa, galeri hanya saat pemain memilihnya.

## ponytail: polling 2 detik, bukan Realtime. Plafon ~500 hatch bersamaan;
## upgrade ke Supabase Realtime kalau kena.

## Dipancarkan saat response turn tiba. Turn disimulasikan lokal lebih dulu supaya
## animasi mulai di frame yang sama dengan tap, sementara request-nya jalan
## berbarengan; sinyal ini yang menyatukan keduanya lagi.
signal _battle_turn_settled
signal _team_turn_settled
signal _summon_settled

const POLL_INTERVAL_SEC := 2.0
const POLL_TIMEOUT_SEC := 180.0
const EVOLUTION_POLL_INTERVAL_SEC := 5.0
const EVOLUTION_POLL_TIMEOUT_SEC := 10.0 * 60.0
const EVOLUTION_POLL_RETRY_SEC := 15.0
const SYNTHESIS_POLL_INTERVAL_SEC := 5.0
const SYNTHESIS_POLL_TIMEOUT_SEC := 10.0 * 60.0
const SYNTHESIS_POLL_RETRY_SEC := 15.0
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
const HUD_TOP_PAD := 24.0
const HOME_GROUND_PORTRAIT_RATIO := HomeBackground.PLATFORM_TARGET_PORTRAIT_RATIO
const HOME_GROUND_LANDSCAPE_RATIO := HomeBackground.PLATFORM_TARGET_LANDSCAPE_RATIO
## Tinggi badan pada tinggi referensi 120 cm, diukur terhadap tinggi art Home.
## Dikalibrasi ke **median roster**, bukan satu sampel: kalibrasi pertama memakai
## satu Rookie 517 px, dan sheet itu ternyata yang terbesar di seluruh roster —
## sisanya 219–401 px, median 312. Akibatnya terukur 22 Agustus 2026: delapan
## dari sembilan Anima membengkak, sampai +81% untuk Drowake. Median tinggi badan
## roster 90 cm, jadi 0,23 memetakan Anima 90 cm kembali ke ~310 px yang memang
## sudah dilihat pemain.
const HOME_BODY_SPAN_RATIO := 0.23
const HOME_BODY_SPAN_MIN_RATIO := 0.12
const HOME_BODY_SPAN_MAX_RATIO := 0.42
## Home memakai kurva sendiri, lebih tegas daripada `BattleScale.BODY_HEIGHT_CURVE`
## 0,42, dan arena sengaja tidak ikut berubah. Alasannya berbeda: di arena selalu
## ada lawan sebagai pembanding, sedangkan di lobby hanya ada satu Anima, jadi
## selisih tinggi harus terbaca tanpa pembanding. Dengan 0,42 rentang nyata
## 55–225 cm hanya menjadi 1,8x di layar dan enam Anima 55–95 cm tampak seukuran;
## 0,62 melebarkannya menjadi 2,4x tanpa menyentuh clamp.
const HOME_BODY_HEIGHT_CURVE := 0.62
const TOAST_GAP := 8.0
const SLEEP_SYNC_RETRY_SEC := 30.0
const SLEEP_SYNC_EPSILON_SEC := 1.0
## Tap-to-wake: cara kedua membangunkan Anima selain tombol Wake, dengan target
## acak per sesi tidur supaya tidak bisa dihafal.
const WAKE_TAPS_MIN := 3
const WAKE_TAPS_MAX := 6
const STAT_ORDER := ["hp", "atk", "def", "spd", "special"]
const STAT_LABEL_KEYS := {
	"hp": "STAT_HP",
	"atk": "STAT_ATK",
	"def": "STAT_DEF",
	"spd": "STAT_SPD",
	"special": "STAT_SPECIAL",
}
const SEEKER_PROFILE_DEST := &"seeker_profile"
const ANIMA_PROFILE_DEST := &"anima_profile"
const ATLAS_DEST := &"atlas"
const SYNTHESIS_DEST := &"synthesis"
const TROPHY_ART_DIR := "user://trophies"
const SHOP_ICON := preload("res://assets/icons/scanima/shop.svg")
const BAG_ICON := preload("res://assets/icons/scanima/bag.svg")
const BATTLE_EVENT := preload("res://scripts/battle_event.gd")

@onready var _stage: Node2D = %Stage
@onready var _first_anima_effect: FirstAnimaEffect = %FirstAnimaEffect
@onready var _incubator: IncubatorEffect = %Incubator
@onready var _anima: AnimaPresenter = %Anima
@onready var _status: Label = %Status
@onready var _dialog: FileDialog = %PhotoDialog
@onready var _status_panel: PanelContainer = %StatusPanel
@onready var _safe_margin: MarginContainer = %SafeMargin
@onready var _top_hud: PanelContainer = %TopHud
@onready var _hud_anima_name: Label = %HudAnimaName
@onready var _hud_anima_meta: Label = %HudAnimaMeta
@onready var _bottom_section: HBoxContainer = %BottomSection
@onready var _anima_info: VBoxContainer = %AnimaInfo
@onready var _brand: Label = %Brand
@onready var _cores_chip = %CoresChip
@onready var _bits_chip: ResourceChip = %BitsChip
@onready var _bag_button: ResourceChip = %BagButton
@onready var _shop_button: ResourceChip = %ShopButton
@onready var _menu_popover: MenuPopover = %MenuPopover
@onready var _shell_modal = %ShellModal
@onready var _shop_sheet = %ShopSheet
@onready var _battle_pick_sheet = %BattlePickSheet
@onready var _photo_source_sheet: PhotoSourceSheet = %PhotoSourceSheet
@onready var _seeker_menu_sheet: SeekerMenuSheet = %SeekerMenuSheet
@onready var _seeker_onboarding_sheet: SeekerOnboardingSheet = %SeekerOnboardingSheet
@onready var _home_view: HomeView = %HomeView
@onready var _home_background: HomeBackground = %HomeBackground
@onready var _scan_view: ScanView = %ScanView
@onready var _battle_view = %BattleView
@onready var _team_battle_view: TeamBattleView = _battle_view.get_node("TeamBattleView")
@onready var _expedition_view: ExpeditionView = _battle_view.get_node("ExpeditionView")
@onready var _collection_view: CollectionView = %CollectionView
@onready var _synthesis_view: SynthesisLabView = %SynthesisLabView
@onready var _details_view: AnimaDetailsView = %AnimaDetailsView
@onready var _seeker_profile_view: SeekerProfileView = %SeekerProfileView
@onready var _atlas_view: AtlasView = %AtlasView
@onready var _bottom_nav: BottomNav = %BottomNav

var _busy := false
var _hud_anima_tapped_frame := -1
var _booting := true
var _boot_auth_success_mode := ""
var _roster: Array[Dictionary] = []
var _catalog: Array = []
var _catalog_synced := false
var _inventory: Array = []
var _current_anima: Dictionary = {}
var _profile_anima: Dictionary = {}
var _roster_error := ""
## Urutan tombol pilihan sign-in terakhir; handler-nya butuh tahu aksi mana yang
## berdiri di slot utama karena urutannya bergantung pada isi roster guest.
var _sign_in_move_first := false
var _placeholder_icon: Texture2D = null
var _thumbnail_cache: Dictionary = {}
var _destination: StringName = BottomNav.HOME
var _overlay_return_destination: StringName = BottomNav.HOME
var _profile_return_destination: StringName = BottomNav.COLLECTION
var _pending_atlas_publish_id := ""
var _pending_gallery_appeal_id := ""
## Anima yang menunggu consent Publish di seberang round trip OAuth, beserta UID
## pemiliknya saat intent dibuat: `{anima_id, uid}`. Sengaja tidak dipersist —
## kalau app mati saat OAuth, intent-nya gugur dan pemain menekan Publish lagi,
## lebih baik daripada consent yang muncul entah dari mana.
var _publish_after_sign_in: Dictionary = {}
var _toast_revision := 0
var _expedition_level_queue: Array[Dictionary] = []
var _expedition_level_sequence_active := false
var _last_care_delta := 0
var _battle_reward_revision := 0
var _battle_turn_result: Dictionary = {}
var _battle_turn_in_flight := false
var _summon_result := false
var _summon_in_flight := false
var _team_turn_result: Dictionary = {}
var _team_turn_in_flight := false
var _team_battle_team: Dictionary = {}
var _team_battle_candidates: Array = []
var _team_battle_daily: Dictionary = {}
var _team_defense_published := false
var _team_battle_demo_active := false
var _team_art_cache: Dictionary = {}
var _trophy_icon_cache: Dictionary = {}
var _expedition_controller: ExpeditionController
var _music: MusicDirector
var _home_ground_shadow: Sprite2D
var _anima_body: Node2D
var _gallery_status_revision := 0
var _sleep_completion_timer: Timer = null
var _sleep_sync_in_flight := false
var _pending_delete_id := ""
var _pending_rename_id := ""
var _pending_rename_text := ""
var _pending_evolve_row: Dictionary = {}
var _evolution_chamber_active := false
var _evolution_resume_in_flight := false
var _evolution_poll_in_flight := false
var _evolution_art_error_reported := false
var _synthesis_resume_in_flight := false
var _synthesis_poll_in_flight := false
var _synthesis_art_error_reported := false
var _synthesis_return_destination: StringName = BottomNav.COLLECTION
var _synthesis_history_revision := 0
var _evolution_history_revision := 0
var _synthesis_history_texture_cache: Dictionary = {}
var _outcome_dialog_queue: Array[Dictionary] = []
var _active_outcome_dialog: Dictionary = {}
var _pending_synthesis_payload: Dictionary = {}
var _pending_retreat := ""
var _modal_context := &""
var _last_anima_press_ms := -1000
var _last_anima_press_position := Vector2(-1000.0, -1000.0)
var _wake_taps := 0
var _wake_taps_target := 0
var _last_known_cores := -1
var _update_required := false
var _chapter_announcements: Dictionary = {}
var _pending_chapter_popup: Array = []
var _chapter_announcement_revision := 0
var _chapter_push: ChapterPush

## Singleton plugin Android, null di desktop dan di test headless.
var _picker: Object = null


## Relay gulir sentuh dipasang di sini, bukan di `_ready()`: seluruh anak shell
## sudah masuk pohon sebelum `_ready()` berjalan, jadi memasangnya di sana akan
## melewatkan setiap Control yang lahir bersama scene.
func _enter_tree() -> void:
	UiJuice.install_touch_scroll(get_tree())


func _ready() -> void:
	# Boot dibuka dengan layar Loading sejak frame pertama: sebelum ini pemain
	# melihat shell kosong lalu Home setengah terisi selama empat round trip, dan
	# boot hangat dari cache tidak pernah menampilkan layarnya sama sekali.
	# Deferred karena `root` masih menyiapkan anak scene utama selama `_ready()`,
	# jadi `add_child` di titik ini ditolak; flush-nya tetap jatuh sebelum frame
	# pertama digambar. Yang menutupnya `_set_busy(false)` milik `_boot()`.
	LoadingScreen.show_screen.call_deferred("STATUS_LOADING", true)
	_chapter_push = ChapterPush.new()
	_chapter_push.name = "ChapterPush"
	add_child(_chapter_push)
	_chapter_push.enabled_changed.connect(_on_chapter_push_enabled)
	_chapter_push.chapter_message_received.connect(_refresh_chapter_announcements)
	_chapter_push.failed.connect(_on_chapter_push_failed)
	_chapter_push.configure(GameState.chapter_push_enabled())
	_anima_body = _make_anima_body_anchor()
	_home_ground_shadow = _make_home_ground_shadow(_anima_body)
	_anima.pose_changed.connect(_sync_home_body)
	_anima.visibility_changed.connect(_sync_home_body)
	_sync_home_body()
	_team_battle_view.set_thumbnail_provider(_thumbnail_for)
	_expedition_view.set_thumbnail_provider(_thumbnail_for)
	_sleep_completion_timer = Timer.new()
	_sleep_completion_timer.name = "SleepCompletionTimer"
	_sleep_completion_timer.one_shot = true
	add_child(_sleep_completion_timer)
	_sleep_completion_timer.timeout.connect(_sync_sleep_completion)
	_scan_view.scan_requested.connect(_on_pick_pressed)
	_scan_view.sign_in_requested.connect(_show_sign_in_confirmation)
	_battle_view.start_requested.connect(_start_battle)
	_battle_view.choose_anima_requested.connect(_open_battle_anima_picker)
	_battle_view.team_mode_requested.connect(_open_team_battle_mode)
	_battle_view.expedition_mode_requested.connect(func() -> void:
		await _expedition_controller.open()
	)
	_battle_view.action_requested.connect(_battle_action_requested)
	_battle_view.item_picker_requested.connect(_open_battle_item_picker)
	_battle_view.resume_requested.connect(_retry_battle)
	_battle_view.exit_requested.connect(_leave_battle)
	_battle_view.forfeit_requested.connect(_confirm_retreat.bind("duel"))
	_battle_view.reward_status_refresh_requested.connect(_refresh_battle_reward_status)
	_team_battle_view.back_requested.connect(_close_team_battle_mode)
	_team_battle_view.save_team_requested.connect(_save_team_battle_roster)
	_team_battle_view.defense_requested.connect(_set_team_defense)
	_team_battle_view.refresh_requested.connect(_refresh_team_battle_candidates)
	_team_battle_view.start_requested.connect(_start_team_battle)
	_team_battle_view.action_requested.connect(_team_battle_action_requested)
	_team_battle_view.item_picker_requested.connect(_open_battle_item_picker)
	_team_battle_view.forfeit_requested.connect(_confirm_retreat.bind("team"))
	_team_battle_view.retry_requested.connect(_retry_team_battle)
	_team_battle_view.arena_open_changed.connect(_on_immersive_arena_changed)
	_expedition_view.combat_open_changed.connect(_on_immersive_arena_changed)
	_battle_view.arena_open_changed.connect(_on_immersive_arena_changed)
	_expedition_controller = ExpeditionController.new()
	_expedition_controller.name = "ExpeditionController"
	add_child(_expedition_controller)
	_expedition_controller.configure(_expedition_view, _battle_view)
	_expedition_view.forfeit_requested.connect(_confirm_retreat.bind("expedition"))
	_expedition_view.abandon_requested.connect(_confirm_expedition_abandon)
	_expedition_controller.item_picker_requested.connect(_open_battle_item_picker)
	_expedition_controller.inventory_refresh_requested.connect(_refresh_inventory)
	_expedition_controller.authority_refresh_requested.connect(_refresh_team_battle_authority)
	_expedition_controller.reward_presented.connect(_apply_expedition_reward)
	_expedition_controller.announcements_changed.connect(_apply_chapter_announcements)
	_home_view.care_requested.connect(_perform_care)
	_home_view.care_blocked.connect(_on_care_blocked)
	_home_view.first_scan_requested.connect(_open_scan)
	_home_view.retry_requested.connect(_retry_roster)
	_brand.mouse_filter = Control.MOUSE_FILTER_STOP
	_brand.gui_input.connect(_on_brand_input)
	_anima_info.mouse_filter = Control.MOUSE_FILTER_STOP
	_anima_info.gui_input.connect(_on_hud_anima_input)
	for inner in _anima_info.find_children("*", "Control", true, false):
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collection_view.preview_requested.connect(_sync_collection_preview)
	_collection_view.atlas_preview_requested.connect(_sync_collection_atlas_preview)
	_collection_view.profile_requested.connect(_show_collection_profile)
	_collection_view.summon_requested.connect(_summon_collection_anima)
	_collection_view.first_scan_requested.connect(_open_scan)
	_collection_view.retry_requested.connect(_retry_roster)
	_collection_view.atlas_requested.connect(_open_atlas)
	_collection_view.synthesis_requested.connect(_open_synthesis_lab)
	_synthesis_view.back_requested.connect(_close_synthesis_lab)
	_synthesis_view.preview_requested.connect(_preview_synthesis)
	_synthesis_view.attempt_requested.connect(_attempt_synthesis)
	_synthesis_view.result_requested.connect(_show_synthesis_result)
	_synthesis_view.set_thumbnail_provider(_thumbnail_for)
	_details_view.rename_requested.connect(_show_rename)
	_details_view.delete_requested.connect(_show_delete_confirmation)
	_details_view.help_requested.connect(_show_details_help)
	_details_view.gallery_publish_requested.connect(_toggle_gallery_publish)
	_details_view.gallery_rejection_info_requested.connect(_show_gallery_rejection_info)
	_details_view.evolve_requested.connect(_show_evolve_confirmation)
	_details_view.synthesis_requested.connect(_open_synthesis_lab)
	_bottom_nav.destination_selected.connect(_on_bottom_nav_destination)
	_shell_modal.confirmed.connect(_modal_confirmed)
	_shell_modal.choice_selected.connect(_modal_choice_selected)
	_shell_modal.canceled.connect(_modal_canceled)
	_shop_sheet.buy_requested.connect(_buy_catalog_item)
	_shop_sheet.use_requested.connect(_use_catalog_item)
	_shop_sheet.shop_cta_requested.connect(_open_shop_from_empty)
	_battle_pick_sheet.profile_requested.connect(_show_collection_profile)
	_battle_pick_sheet.battle_requested.connect(_battle_pick_start)
	_photo_source_sheet.camera_requested.connect(_request_camera_photo)
	_photo_source_sheet.gallery_requested.connect(_request_gallery_photo)
	_cores_chip.pressed.connect(_show_core_info)
	_bits_chip.pressed.connect(_show_bits_info)
	_bag_button.pressed.connect(_on_bag_pressed)
	_shop_button.pressed.connect(_open_shop)
	_menu_popover.profile_requested.connect(_open_seeker_profile)
	_menu_popover.atlas_requested.connect(_open_atlas)
	_menu_popover.settings_requested.connect(_open_settings)
	_seeker_menu_sheet.account_requested.connect(_show_account_action)
	_seeker_menu_sheet.help_requested.connect(_show_seeker_help)
	_seeker_menu_sheet.delete_account_requested.connect(_show_delete_account_confirmation)
	_seeker_menu_sheet.music_changed.connect(_set_music_enabled)
	_seeker_menu_sheet.chapter_push_changed.connect(_set_chapter_push)
	_seeker_onboarding_sheet.submit_requested.connect(_complete_seeker_profile)
	_seeker_profile_view.back_requested.connect(_return_from_overlay)
	_seeker_profile_view.help_requested.connect(_show_details_help)
	_seeker_profile_view.rename_requested.connect(_show_rename_seeker)
	_atlas_view.back_requested.connect(_return_from_overlay)
	_atlas_view.collection_requested.connect(_open_collection)
	_atlas_view.toast_requested.connect(_say)
	AuthFlow.auth_succeeded.connect(_on_auth_succeeded)
	AuthFlow.auth_failed.connect(_on_auth_failed)
	AuthFlow.existing_account_required.connect(_show_existing_account_warning)
	LocaleManager.locale_changed.connect(_refresh_localized_ui)
	_music = MusicDirector.new()
	_music.name = "MusicDirector"
	add_child(_music)
	_music.set_enabled(GameState.music_enabled())
	_music.cue_source = _music_cue
	_configure_resource_chips()
	_dialog.file_selected.connect(_scan_file)
	get_viewport().size_changed.connect(_layout_for_viewport)
	_layout_for_viewport()
	await get_tree().process_frame
	UiJuice.install_buttons(self)
	_sync_shop_chrome()
	UiJuice.reveal(_top_hud, 0.02)
	UiJuice.reveal(_home_view, 0.08)
	UiJuice.reveal(_bottom_nav, 0.14)
	_switch_destination(BottomNav.HOME)
	_setup_picker()
	await AuthFlow.ensure_recovered()
	_show_cached_anima()
	await _boot()
	_booting = false
	if not _boot_auth_success_mode.is_empty():
		_say(tr(_account_success_key(_boot_auth_success_mode)), true)
		_boot_auth_success_mode = ""

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
		if arg == "--scan-vibe-demo":
			_switch_destination(BottomNav.SCAN)
		if arg == "--collection":
			_switch_destination(BottomNav.COLLECTION)
		if arg == "--stats":
			_switch_destination(ANIMA_PROFILE_DEST)
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
		if arg == "--evolve-demo":
			await _run_evolve_demo()
		if arg == "--evolve-chamber-demo":
			await _run_evolve_chamber_demo()
		if arg == "--collection-sheet-demo":
			_run_collection_sheet_demo()
		if arg == "--collection-sheet-loading-demo":
			_run_collection_sheet_demo(true)
		if arg == "--profile-demo":
			_run_profile_help_demo(false)
		if arg == "--profile-help-demo":
			_run_profile_help_demo()
		if arg == "--synthesis-history-demo":
			_run_synthesis_history_demo(false)
		if arg == "--profile-menu-demo":
			_run_synthesis_history_demo(false)
			_open_profile_menu_demo.call_deferred()
		if arg == "--synthesis-history-loading-demo":
			_run_synthesis_history_demo(false, true)
		if arg == "--synthesis-history-help-demo":
			_run_synthesis_history_demo(true)
		if arg == "--home-tap-demo" and _anima.sprite_frames != null:
			await _run_home_tap_demo()
		if arg == "--feed-fly-demo":
			await _run_feed_fly_demo("feed")
		if arg == "--item-fly-demo":
			await _run_feed_fly_demo("item")
		if arg == "--level-up-demo":
			if _current_anima.is_empty():
				_current_anima = {
					"nickname": "Vitrelisk",
					"base_stats": {
						"hp": 50, "atk": 43, "def": 38, "spd": 51, "special": 44
					},
					"care_score": 15,
				}
			_celebrate_level_up(4, 3, 10, 15)
		if arg == "--loading-demo":
			LoadingScreen.show_screen("STATUS_LOADING", true)
		if arg == "--trophy-demo":
			_run_trophy_demo()
		if arg == "--atlas-demo":
			_run_atlas_demo()
		if arg == "--empty-demo":
			_run_empty_demo()
		if arg == "--summon-demo":
			await _run_summon_demo()
		if arg == "--battle-demo":
			_run_battle_demo()
		if arg == "--battle-small-demo":
			_run_battle_demo("active", false, 0.0, 50.0, 120.0)
		if arg == "--battle-normal-demo":
			_run_battle_demo("active", false, 0.0, 120.0, 120.0)
		if arg == "--battle-giant-demo":
			_run_battle_demo("active", false, 0.0, 120.0, 2000.0)
		if arg == "--battle-pending-demo":
			_run_battle_demo()
			_battle_view.begin_action("surge")
		if arg == "--battle-effective-demo":
			_run_battle_demo("active", false, 1.5)
		if arg == "--battle-guard-demo":
			_run_battle_demo()
			_loop_guard_shimmer_demo()
		if arg == "--battle-result-demo":
			_run_battle_demo("forfeited")
		if arg == "--battle-win-demo":
			_run_battle_demo("won")
		if arg == "--battle-blocked-demo":
			_run_battle_blocked_demo()
		if arg == "--battle-training-active-demo":
			_run_battle_demo("active", true)
		if arg == "--battle-training-demo":
			_run_battle_training_demo()
		if arg == "--team-battle-demo":
			_run_team_battle_demo()
		if arg == "--team-result-demo":
			_run_team_result_demo()
		if arg == "--boss-ace-demo":
			await _run_boss_ace_demo()
		if arg == "--boss-scale-demo":
			_run_boss_scale_demo()
		if arg.begins_with("--sugarworks-zone-demo="):
			_run_sugarworks_zone_demo(int(arg.trim_prefix("--sugarworks-zone-demo=")))
		if arg == "--sugarworks-fudge-demo":
			_run_sugarworks_zone_demo(3, true)
		if arg == "--sugarworks-giant-fudge-demo":
			_run_sugarworks_zone_demo(3, false, -1, int(BattleScale.BODY_HEIGHT_MAX_CM))
		if arg == "--sugarworks-giant-veridian-demo":
			_run_sugarworks_zone_demo(3, false, int(BattleScale.BODY_HEIGHT_MAX_CM), -1)
		if arg == "--sugarworks-giant-both-demo":
			_run_sugarworks_zone_demo(
				3, false, int(BattleScale.BODY_HEIGHT_MAX_CM), int(BattleScale.BODY_HEIGHT_MAX_CM)
			)
		if arg == "--expedition-demo":
			_run_expedition_demo()
		if arg == "--expedition-builder-demo":
			_run_expedition_builder_demo()
		if arg == "--chapter-announcement-demo":
			_run_chapter_announcement_demo()
		if arg.begins_with("--screenshot="):
			await _capture_and_quit(arg.trim_prefix("--screenshot="))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_node_ready():
			_handle_back(true)
		return
	if what != NOTIFICATION_APPLICATION_RESUMED or not is_node_ready():
		return
	if is_instance_valid(_sleep_completion_timer) and _is_sleeping(_current_anima):
		_sleep_completion_timer.stop()
		call_deferred("_sync_sleep_completion")
	if _destination == BottomNav.BATTLE:
		call_deferred("_refresh_battle_reward_status")
	if (
		not GameState.pending_evolution.is_empty()
		and not _evolution_resume_in_flight
		and not _evolution_poll_in_flight
	):
		call_deferred("_resume_pending_evolution", false)
	elif (
		GameState.pending_evolution.is_empty()
		and not _evolution_poll_in_flight
		and not _evolving_roster_row().is_empty()
	):
		_resume_server_evolution(_evolving_roster_row(), false)
	if not GameState.pending_synthesis.is_empty() and not _synthesis_poll_in_flight:
		call_deferred("_resume_pending_synthesis")
	call_deferred("_refresh_chapter_announcements")


# ---------------------------------------------------------------- boot

func _boot() -> void:
	_set_busy(true)
	# Layar Loading boot sudah dibuka di `_ready()` dan tetap menutupi keduanya.
	# Yang membedakan cache adalah state Home di bawahnya: yang sudah tercat tidak
	# dikosongkan, sebab refresh-nya menimpa angkanya sendiri saat Postgres
	# menjawab.
	var from_cache := _home_view.shell_state() == &"ready"
	if not from_cache:
		_set_home_shell_state(&"loading")

	var sesi := await Backend.ensure_session()
	if not sesi.ok:
		# Kegagalan di sini tidak boleh terlihat seperti app rusak biasa: kalau
		# refresh token ditolak, akun pemain berisiko tidak bisa dijangkau lagi.
		print("session error: %s" % sesi.error)
		if not from_cache:
			_set_home_shell_state(&"error")
		_say(tr("STATUS_ACCOUNT_ERROR"))
		_set_busy(false)
		return
	_apply_cached_mode_availability()
	_discover_team_battle()
	_expedition_controller.discover()

	var boot_epoch := GameState.session_epoch
	var profile_res := await Backend.fetch_profile()
	if not Backend.response_applies(profile_res, boot_epoch):
		return
	_apply_profile_refresh(profile_res)
	if not await _ensure_client_version():
		_set_busy(false)
		return
	# Link bisa selesai tepat sebelum app mati. Grant upgrade diulang sampai
	# marker server terisi; RPC-nya memegang lock dan idempoten.
	if (
		not GameState.is_anonymous()
		and not profile_value_present(GameState.profile, &"account_upgraded_at")
	):
		var upgraded := await Backend.seeker("upgrade")
		if not Backend.response_applies(upgraded, boot_epoch):
			return
		if upgraded.ok:
			GameState.profile.merge(GameState.as_dict(upgraded.data), true)
	await _refresh_catalog()
	if GameState.session_epoch != boot_epoch:
		return
	_refresh_header()
	var roster_loaded := await _reload_roster()
	if GameState.session_epoch != boot_epoch:
		return
	if not GameState.pending_care.is_empty():
		_say(tr("STATUS_RESUMING_CARE"))
		await _resume_pending_care()
	if not GameState.pending_purchase.is_empty():
		await _resume_pending_purchase()
	_set_busy(false)
	call_deferred("_refresh_chapter_announcements")

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
		# Roster cache tetap lebih berguna daripada layar error: yang gagal hanya
		# penyegarannya, dan angkanya sudah diproyeksikan dari sync terakhir.
		if not from_cache:
			_set_home_shell_state(&"error")
		_say(tr("STATUS_ROSTER_ERROR"))
	elif not _roster.is_empty():
		var active := _active_row()
		if active.is_empty():
			active = _roster[0]
		var pending_evolution_here := _pending_evolution_matches(str(active.get("id", "")))
		if CareRules.is_evolving(active) or pending_evolution_here:
			if pending_evolution_here:
				active["status"] = "evolving"
			_sync_evolution_row(active)
			_apply_evolution_chamber_for_row(active, _destination == BottomNav.HOME)
			_refresh_stats()
			_refresh_care()
			_populate_collection()
			_set_home_shell_state(&"ready")
		else:
			_set_busy(true)
			# Boot belum selesai sampai Anima-nya benar-benar di layar: art bisa
			# masih harus diunduh, dan itu berlaku juga untuk Home yang tercat dari
			# cache. Request ini menahan layar yang sama alih-alih mengedipkannya,
			# dan itu berlaku **karena** seluruh jarak dari `_set_busy(false)` di
			# atas sampai ke sini sinkron: fade-nya belum memproses satu frame pun,
			# jadi `request()` membatalkannya. Menyisipkan `await` di antaranya
			# memperlihatkan Home setengah terisi sebelum art datang.
			LoadingScreen.show_screen("STATUS_LOADING")
			await _present_row(active)
			_set_busy(false)
	else:
		_current_anima = {}
		GameState.remember_anima({})
		_anima.sprite_frames = null
		_set_home_shell_state(&"empty")
	if not GameState.pending_evolution.is_empty():
		call_deferred("_resume_pending_evolution", false)
	else:
		var evolving := _evolving_roster_row()
		if not evolving.is_empty():
			_resume_server_evolution(evolving, false)
	if not GameState.pending_synthesis.is_empty():
		call_deferred("_resume_pending_synthesis")
	# Battle yang tersimpan tetap menjadi bookmark sampai pemain memilih Continue.
	# Boot tidak mengambil alih Home atau me-replay intent jaringan secara otomatis.
	if GameState.pending_scan.is_empty():
		call_deferred("_maybe_prompt_seeker_onboarding")


func _reload_roster() -> bool:
	var account_epoch := GameState.session_epoch
	var res := await Backend.fetch_animas()
	if not Backend.response_applies(res, account_epoch):
		return false
	if not res.ok or typeof(res.data) != TYPE_ARRAY:
		_roster_error = res.error if not res.error.is_empty() else "balasan koleksi tidak sah"
		_collection_view.set_error()
		return false

	var rows: Array = res.data
	var ready: Array[Dictionary] = []
	for value in rows:
		var row := GameState.as_dict(value)
		if not str(row.get("id", "")).is_empty():
			ready.append(_overlay_pending_evolution(row))
	_roster = ready
	if is_instance_valid(_expedition_controller):
		_expedition_controller.set_roster(_roster)
	_team_battle_view.set_roster(_roster)
	_roster_error = ""
	_populate_collection()
	GameState.remember_boot_cache({"roster": _roster, "profile": GameState.profile})
	return true


func _summoned_id() -> String:
	var id := str(_current_anima.get("id", ""))
	if not id.is_empty():
		return id
	id = str(GameState.profile.get("active_anima_id", ""))
	if not id.is_empty():
		return id
	return str(GameState.last_anima.get("id", ""))


func _active_row() -> Dictionary:
	var wanted := str(GameState.profile.get("active_anima_id", ""))
	if wanted.is_empty():
		wanted = str(GameState.last_anima.get("id", ""))
	if wanted.is_empty():
		return {}
	for row in _roster:
		if str(row.get("id", "")) == wanted:
			return row
	return {}


func _sprite_stage_for_row(row: Dictionary) -> int:
	return CareRules.committed_stage(row)


func _sync_collection_preview(row: Dictionary, revision: int) -> void:
	var account_epoch := GameState.session_epoch
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return
	var res := await Backend.care_anima(anima_id, "sync")
	if not Backend.response_applies(res, account_epoch):
		return
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
	_profile_return_destination = (
		_destination
		if _destination in [BottomNav.HOME, BottomNav.COLLECTION, BottomNav.BATTLE, SYNTHESIS_DEST]
		else BottomNav.COLLECTION
	)
	_switch_destination(ANIMA_PROFILE_DEST, row)


func _open_synthesis_lab(preselected: Dictionary = {}) -> void:
	if not _synthesis_enabled():
		_say(tr("SYNTHESIS_FEATURE_DISABLED"), true)
		return
	if _destination != SYNTHESIS_DEST:
		_synthesis_return_destination = (
			_destination
			if _destination in [BottomNav.COLLECTION, ANIMA_PROFILE_DEST]
			else BottomNav.COLLECTION
		)
	_switch_destination(SYNTHESIS_DEST)
	_synthesis_view.set_rows(_roster, str(preselected.get("id", "")))
	if not GameState.pending_synthesis.is_empty() and not _synthesis_poll_in_flight:
		call_deferred("_resume_pending_synthesis")


func _close_synthesis_lab() -> void:
	if _synthesis_view.close_picker():
		return
	_switch_destination(_synthesis_return_destination)


func _preview_synthesis(payload: Dictionary) -> void:
	var account_epoch := GameState.session_epoch
	if payload.is_empty() or not _synthesis_enabled():
		return
	_synthesis_view.set_busy(true)
	var res := await Backend.synthesize_anima("preview", payload)
	_synthesis_view.set_busy(false)
	if not Backend.response_applies(res, account_epoch):
		return
	if res.ok and typeof(res.data) == TYPE_DICTIONARY:
		_synthesis_view.apply_preview(GameState.as_dict(res.data))
	else:
		_synthesis_view.show_error_key(_synthesis_error_key(str(res.error)))


func _attempt_synthesis(payload: Dictionary) -> void:
	if payload.is_empty() or not _synthesis_enabled() or _busy:
		return
	if not GameState.pending_synthesis.is_empty():
		_say(tr("SYNTHESIS_ALREADY_ACTIVE"), true)
		return
	_pending_synthesis_payload = payload.duplicate(true)
	_modal_context = &"synthesis_attempt"
	_shell_modal.open_confirm(
		tr("SYNTHESIS_CONFIRM_TITLE"),
		tr("SYNTHESIS_CONFIRM_BODY") % [
			LocaleManager.format_integer(1),
			LocaleManager.format_integer(250),
		],
		tr("SYNTHESIS_CONFIRM_ACTION"),
		tr("ACTION_CANCEL")
	)


func _synthesis_attempt_confirmed() -> void:
	var payload := _pending_synthesis_payload.duplicate(true)
	_pending_synthesis_payload = {}
	if payload.is_empty() or not _synthesis_enabled() or _busy:
		return
	if not GameState.pending_synthesis.is_empty():
		_say(tr("SYNTHESIS_ALREADY_ACTIVE"), true)
		return
	var pending := GameState.begin_synthesis(
		str(payload.get("source_a_id", "")),
		int(payload.get("source_a_stage", 0)),
		str(payload.get("source_b_id", "")),
		int(payload.get("source_b_stage", 0)),
		str(payload.get("mode", ""))
	)
	_synthesis_art_error_reported = false
	_synthesis_view.show_generating(pending)
	await _send_pending_synthesis("attempt")


func _resume_pending_synthesis() -> void:
	if GameState.pending_synthesis.is_empty():
		return
	await _send_pending_synthesis("resume")


func _send_pending_synthesis(operation: String) -> void:
	var account_epoch := GameState.session_epoch
	if _synthesis_resume_in_flight or _synthesis_poll_in_flight:
		return
	var pending := GameState.pending_synthesis.duplicate(true)
	if pending.is_empty():
		return
	_synthesis_resume_in_flight = true
	var payload := pending.duplicate(true)
	var res := await Backend.synthesize_anima(operation, payload)
	_synthesis_resume_in_flight = false
	if not Backend.response_applies(res, account_epoch):
		return
	var body := GameState.as_dict(res.data)
	if res.ok:
		if body.has("resonance_succeeded") and not bool(body.get("resonance_succeeded", false)):
			GameState.finish_synthesis()
			await _reload_roster()
			if _destination == SYNTHESIS_DEST:
				_synthesis_view.set_rows(_roster)
				_synthesis_view.show_resonance_failure(body)
			_queue_synthesis_failure_dialog(
				tr("SYNTHESIS_RESONANCE_FAILED_TITLE"),
				tr("SYNTHESIS_RESONANCE_FAILED_BODY") % [
					LocaleManager.format_integer(int(body.get("chance", 0))),
					LocaleManager.format_integer(int(body.get("calibration", 0))),
				]
			)
			return
		var generation_id := str(body.get("generation_id", pending.get("generation_id", "")))
		var result_id := str(body.get("result_anima_id", pending.get("result_anima_id", "")))
		GameState.note_synthesis_started(generation_id, result_id)
		if _destination == SYNTHESIS_DEST:
			_synthesis_view.show_generating(GameState.pending_synthesis)
		if result_id.is_empty():
			_say(tr("SYNTHESIS_PENDING"), true)
			call_deferred("_retry_pending_synthesis")
			return
		await _wait_for_synthesis(result_id)
		return

	var code := str(body.get("error", res.error))
	# Sesi kedaluwarsa (401) dan gerbang versi client (426) bukan keputusan server
	# tentang Synthesis ini; keduanya bisa muncul sesudah Core + Bits terdebit.
	# Membuang idempotency key di situ berarti Result yang sudah dibayar tidak
	# bisa di-resume lagi, jadi keduanya diperlakukan seperti 5xx.
	var server_verdict: bool = (
		res.code >= 400 and res.code < 500 and res.code != 401 and res.code != 426
	)
	if server_verdict:
		GameState.finish_synthesis()
		var profile_res := await Backend.fetch_profile()
		if not Backend.response_applies(profile_res, account_epoch):
			return
		_apply_profile_refresh(profile_res)
		_refresh_header()
		var error_key := _synthesis_error_key(code)
		if _destination == SYNTHESIS_DEST:
			_synthesis_view.set_rows(_roster)
			_synthesis_view.show_error_key(error_key)
		if error_key == "SYNTHESIS_TECHNICAL_FAILURE":
			_queue_synthesis_failure_dialog(
				tr("SYNTHESIS_FAILED_DIALOG_TITLE"),
				tr(error_key)
			)
		else:
			_say(tr(error_key), true)
	else:
		if _destination == SYNTHESIS_DEST:
			_synthesis_view.show_generating(GameState.pending_synthesis)
		_say(tr("SYNTHESIS_PENDING"), true)
		call_deferred("_retry_pending_synthesis")


func _retry_pending_synthesis() -> void:
	await get_tree().create_timer(SYNTHESIS_POLL_RETRY_SEC).timeout
	if (
		not GameState.pending_synthesis.is_empty()
		and not _synthesis_resume_in_flight
		and not _synthesis_poll_in_flight
	):
		call_deferred("_resume_pending_synthesis")


func _wait_for_synthesis(result_anima_id: String) -> void:
	var account_epoch := GameState.session_epoch
	if _synthesis_poll_in_flight or result_anima_id.is_empty():
		return
	_synthesis_poll_in_flight = true
	var remaining := SYNTHESIS_POLL_TIMEOUT_SEC
	while remaining > 0.0 and not GameState.pending_synthesis.is_empty():
		await get_tree().create_timer(SYNTHESIS_POLL_INTERVAL_SEC).timeout
		if GameState.session_epoch != account_epoch:
			_synthesis_poll_in_flight = false
			return
		remaining -= SYNTHESIS_POLL_INTERVAL_SEC
		var res := await Backend.fetch_anima(result_anima_id)
		if not Backend.response_applies(res, account_epoch):
			_synthesis_poll_in_flight = false
			return
		if not res.ok or typeof(res.data) != TYPE_ARRAY:
			continue
		var rows: Array = res.data
		if rows.is_empty():
			continue
		var row := normalize_anima_data(GameState.as_dict(rows[0]))
		match str(row.get("status", "")):
			"ready":
				if await _complete_synthesis(row):
					_synthesis_poll_in_flight = false
					return
			"failed":
				_synthesis_poll_in_flight = false
				await _fail_synthesis_client()
				return
	_synthesis_poll_in_flight = false
	_say(tr("SYNTHESIS_PENDING"), true)
	call_deferred("_retry_pending_synthesis")


func _complete_synthesis(row: Dictionary) -> bool:
	var anima_id := str(row.get("id", ""))
	var loaded := await _prepare_anima_art(
		str(row.get("species_key", "")),
		str(row.get("color_bucket", "")),
		1,
		str(row.get("sheet_path", "")),
		GameState.as_dict(row.get("manifest")),
		false,
		anima_id,
		1
	)
	if not bool(loaded.get("ok", false)):
		# Polling terus berjalan supaya art-nya bisa datang di percobaan berikutnya,
		# tapi toast-nya sekali saja: Result sudah ada di server, dan mengulang
		# pesan yang sama tiap 5 detik hanya menutupi layar.
		if not _synthesis_art_error_reported:
			_say(tr("STATUS_ART_DOWNLOAD_ERROR"), true)
			_synthesis_art_error_reported = true
		return false
	_synthesis_art_error_reported = false
	var account_epoch := GameState.session_epoch
	GameState.finish_synthesis()
	_upsert_roster(row)
	var profile_res := await Backend.fetch_profile()
	if not Backend.response_applies(profile_res, account_epoch):
		return false
	_apply_profile_refresh(profile_res)
	_refresh_header()
	_populate_collection()
	GameState.remember_boot_cache({"roster": _roster, "profile": GameState.profile})
	var portrait := _thumbnail_for(row)
	if _destination == SYNTHESIS_DEST:
		_synthesis_view.set_rows(_roster)
		_synthesis_view.show_result(row, portrait)
	_queue_synthesis_success_dialog(row, portrait)
	return true


func _fail_synthesis_client() -> void:
	var account_epoch := GameState.session_epoch
	GameState.finish_synthesis()
	var profile_res := await Backend.fetch_profile()
	if not Backend.response_applies(profile_res, account_epoch):
		return
	_apply_profile_refresh(profile_res)
	_refresh_header()
	if _destination == SYNTHESIS_DEST:
		_synthesis_view.set_rows(_roster)
		_synthesis_view.show_error_key("SYNTHESIS_TECHNICAL_FAILURE")
	_queue_synthesis_failure_dialog(
		tr("SYNTHESIS_FAILED_DIALOG_TITLE"),
		tr("SYNTHESIS_TECHNICAL_FAILURE")
	)


func _queue_synthesis_failure_dialog(title: String, body: String) -> void:
	_enqueue_outcome_dialog({
		"kind": "synthesis_failure",
		"title": title,
		"body": body,
	})


func _queue_synthesis_success_dialog(row: Dictionary, portrait: Texture2D) -> void:
	_enqueue_outcome_dialog({
		"kind": "synthesis_success",
		"row": row.duplicate(true),
		"portrait": portrait,
	})


func _enqueue_outcome_dialog(dialog: Dictionary) -> void:
	var queued := dialog.duplicate(false)
	queued["session_epoch"] = GameState.session_epoch
	_outcome_dialog_queue.append(queued)
	_present_next_outcome_dialog()


func _present_next_outcome_dialog() -> void:
	if _shell_modal.visible:
		return
	while not _outcome_dialog_queue.is_empty():
		var dialog: Dictionary = _outcome_dialog_queue.pop_front()
		if int(dialog.get("session_epoch", -1)) != GameState.session_epoch:
			continue
		_active_outcome_dialog = dialog
		match str(dialog.get("kind", "")):
			"synthesis_success":
				var row := GameState.as_dict(dialog.get("row"))
				_modal_context = &"synthesis_success"
				Sfx.play(Sfx.CUE_LEVEL_UP)
				_shell_modal.open_result(
					tr("SYNTHESIS_COMPLETE_TITLE"),
					tr("SYNTHESIS_COMPLETE_BODY"),
					tr("SYNTHESIS_VIEW_RESULT"),
					LocaleManager.display_name(row),
					dialog.get("portrait") as Texture2D,
					false
				)
				return
			"synthesis_failure":
				_modal_context = &"synthesis_failure"
				_shell_modal.open_info(
					str(dialog.get("title", tr("SYNTHESIS_FAILED_DIALOG_TITLE"))),
					str(dialog.get("body", tr("SYNTHESIS_TECHNICAL_FAILURE"))),
					tr("CORE_INFO_CLOSE"),
					"",
					false
				)
				return
			"evolution_success":
				var row := GameState.as_dict(dialog.get("row"))
				_modal_context = &"evolution_success"
				Sfx.play(Sfx.CUE_LEVEL_UP)
				_shell_modal.open_result_choice(
					tr("EVOLUTION_COMPLETE_TITLE"),
					_evolution_success_copy(row),
					tr("COLLECTION_SUMMON"),
					tr("ANIMA_RENAME_ACTION"),
					LocaleManager.display_name(row),
					dialog.get("portrait") as Texture2D,
					false
				)
				return
			"evolution_failure":
				_present_evolution_failure_outcome(dialog)
				return
			"level_up":
				_present_level_up_outcome(dialog)
				return
		_active_outcome_dialog = {}


func _present_queued_dialogs_after_modal() -> void:
	if _outcome_dialog_queue.is_empty():
		return
	await get_tree().create_timer(0.20).timeout
	_present_next_outcome_dialog()


func _show_synthesis_result(row: Dictionary) -> void:
	if row.is_empty():
		return
	_profile_return_destination = SYNTHESIS_DEST
	_switch_destination(ANIMA_PROFILE_DEST, row)
	call_deferred("_show_rename", str(row.get("id", "")), LocaleManager.display_name(row))


func _history_source_names() -> Dictionary:
	var names := {}
	for row in _roster:
		var anima_id := str(row.get("id", ""))
		if anima_id.is_empty():
			continue
		names[anima_id] = LocaleManager.display_name(row)
	return names


func _refresh_synthesis_history() -> void:
	_synthesis_history_revision += 1
	var revision := _synthesis_history_revision
	var row := _profile_anima if not _profile_anima.is_empty() else _current_anima
	var anima_id := str(row.get("id", ""))
	var local_history := GameState.as_dict(row.get("synthesis_history"))
	var textures := _cached_synthesis_history_textures(anima_id)
	_details_view.set_history_source_names(_history_source_names())
	_details_view.set_synthesis_history(local_history, textures)
	if anima_id.is_empty() or local_history.is_empty():
		_details_view.set_synthesis_history_loading(false)
		return
	# Cache langsung dicat; request ini hanya me-refresh metadata dan mengisi slot
	# yang belum ada, jadi reopen Profile tidak kembali ke skeleton.
	_details_view.set_synthesis_history_loading(textures.size() < 2)
	var account_epoch := GameState.session_epoch
	var res := await Backend.synthesize_anima("history", {"result_anima_id": anima_id})
	if not Backend.response_applies(res, account_epoch):
		return
	if revision != _synthesis_history_revision:
		return
	if not res.ok:
		_details_view.set_synthesis_history_loading(false)
		return
	var history := GameState.as_dict(GameState.as_dict(res.data).get("history"))
	if history.is_empty():
		_details_view.set_synthesis_history_loading(false)
		return
	var source_a := GameState.as_dict(history.get("source_a"))
	var source_b := GameState.as_dict(history.get("source_b"))
	if not textures.has("source_a"):
		textures["source_a"] = await _synthesis_history_texture(
			str(source_a.get("thumbnail_url", "")),
			_synthesis_history_cache_id(anima_id, "source_a")
		)
	if not textures.has("source_b"):
		textures["source_b"] = await _synthesis_history_texture(
			str(source_b.get("thumbnail_url", "")),
			_synthesis_history_cache_id(anima_id, "source_b")
		)
	if revision == _synthesis_history_revision and anima_id == str(_profile_anima.get("id", "")):
		_details_view.set_synthesis_history(history, textures)
		_details_view.set_synthesis_history_loading(false)


## Silsilah bentuk untuk Profile. Thumbnail-nya melewati cache thumb yang sama
## dengan Synthesis History — keduanya crop Idle transparan per Anima, jadi tidak
## ada gunanya dua cache. Stage 1 tidak pernah memanggil server: ia belum punya
## bentuk sebelumnya, dan section-nya memang disembunyikan.
func _refresh_evolution_history() -> void:
	_evolution_history_revision += 1
	var revision := _evolution_history_revision
	var row := _profile_anima if not _profile_anima.is_empty() else _current_anima
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty() or CareRules.committed_stage(row) < 2:
		_details_view.set_evolution_history([])
		return
	_details_view.set_evolution_history_loading(true)
	var account_epoch := GameState.session_epoch
	var res := await Backend.evolution_history(anima_id)
	if not Backend.response_applies(res, account_epoch):
		return
	if revision != _evolution_history_revision:
		return
	if not res.ok:
		# Skeleton yang tidak pernah berhenti lebih buruk daripada section yang
		# absen: ia menjanjikan sesuatu yang tidak akan datang.
		_details_view.set_evolution_history_loading(false)
		return
	var forms: Array = GameState.as_dict(res.data).get("forms", [])
	if forms.size() < 2:
		_details_view.set_evolution_history([])
		return
	var textures: Dictionary = {}
	for entry: Variant in forms:
		var form := GameState.as_dict(entry)
		var stage := int(form.get("stage", 1))
		var texture := await _synthesis_history_texture(
			str(form.get("thumbnail_url", "")),
			_synthesis_history_cache_id(anima_id, "form_%d" % stage)
		)
		if texture != null:
			textures[str(stage)] = texture
	if revision != _evolution_history_revision:
		return
	if anima_id == str(_profile_anima.get("id", "")):
		_details_view.set_evolution_history(forms, textures)


func _cached_synthesis_history_textures(anima_id: String) -> Dictionary:
	var textures: Dictionary = {}
	if anima_id.is_empty():
		return textures
	for slot: String in ["source_a", "source_b"]:
		var cache_id := _synthesis_history_cache_id(anima_id, slot)
		var texture := _cached_synthesis_history_texture(cache_id)
		if texture != null:
			textures[slot] = texture
	return textures


func _cached_synthesis_history_texture(cache_id: String) -> Texture2D:
	if _synthesis_history_texture_cache.has(cache_id):
		return _synthesis_history_texture_cache[cache_id] as Texture2D
	var path := Backend.atlas_thumb_cache_path(cache_id)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return null
	var texture := ImageTexture.create_from_image(image)
	_synthesis_history_texture_cache[cache_id] = texture
	return texture


func _synthesis_history_cache_id(anima_id: String, slot: String) -> String:
	return "history_%s_%s_%s" % [
		GameState.uid().sha256_text().left(16),
		anima_id.sha256_text().left(24),
		slot,
	]


## History menerima crop Idle transparan yang sama dengan Atlas. Jangan key ulang
## warna di client: chroma reference untuk model bersifat lossy terhadap Anima hijau.
func _synthesis_history_texture(url: String, cache_id: String) -> Texture2D:
	var cached := _cached_synthesis_history_texture(cache_id)
	if cached != null or url.is_empty():
		return cached
	var account_epoch := GameState.session_epoch
	var res := await Backend.download_url(url)
	if not Backend.response_applies(res, account_epoch):
		return null
	if not res.ok or res.bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(res.bytes) != OK:
		return null
	Backend.store_atlas_thumb(cache_id, res.bytes)
	var texture := ImageTexture.create_from_image(image)
	_synthesis_history_texture_cache[cache_id] = texture
	return texture


func _synthesis_error_key(code: String) -> String:
	match code:
		"FEATURE_DISABLED":
			return "SYNTHESIS_FEATURE_DISABLED"
		"SYNTHESIS_LEVEL_TOO_LOW":
			return "SYNTHESIS_LEVEL_TOO_LOW"
		"SYNTHESIS_COOLDOWN":
			return "SYNTHESIS_COOLDOWN"
		"SYNTHESIS_MODE_USED":
			return "SYNTHESIS_MODE_USED"
		"SYNTHESIS_ALREADY_ACTIVE", "SYNTHESIS_IN_PROGRESS":
			return "SYNTHESIS_ALREADY_ACTIVE"
		"SYNTHESIS_FORM_LOCKED", "SYNTHESIS_FORM_INVALID":
			return "SYNTHESIS_FORM_LOCKED"
		"SYNTHESIS_STAGE_MISMATCH":
			return "SYNTHESIS_STAGE_MISMATCH"
		"ANIMA_DORMANT":
			return "SYNTHESIS_ANIMA_DORMANT"
		"ANIMA_IN_ACTIVE_COMBAT":
			return "SYNTHESIS_ANIMA_IN_COMBAT"
		"NO_CORE":
			return "STATUS_NEED_CORE"
		"NO_BITS":
			return "ERROR_NO_BITS"
		"SPEND_CAP":
			return "STATUS_SPEND_CAP"
		"SYNTHESIS_FAILED":
			return "SYNTHESIS_TECHNICAL_FAILURE"
		_:
			return "SYNTHESIS_ERROR"


func _summon_collection_anima(row: Dictionary, care_synced: bool) -> void:
	await _activate_anima(row, care_synced, false)


func _activate_anima(row: Dictionary, care_synced: bool, stay_on_tab: bool) -> bool:
	if row.is_empty() or _busy:
		return false
	if not GameState.pending_evolution.is_empty():
		_say(tr("EVOLUTION_ALREADY_ACTIVE"), true)
		return false
	if not GameState.pending_care.is_empty():
		_say(tr("ERROR_CARE_PENDING"), true)
		return false
	_set_busy(true)
	if not stay_on_tab:
		_collection_view.set_sheet_busy(true)
	var anima_id := str(row.get("id", ""))
	var loaded := await _prepare_anima_art(
		str(row.get("species_key", "")),
		str(row.get("color_bucket", "")),
		int(row.get("stage", 1)),
		str(row.get("sheet_path", "")),
		GameState.as_dict(row.get("manifest")),
		true,
		anima_id
	)
	if not bool(loaded.get("ok", false)):
		if not stay_on_tab:
			_collection_view.set_sheet_busy(false)
		_set_busy(false)
		return false
	var pending := GameState.begin_care(anima_id, "summon")

	if stay_on_tab:
		if not await _send_pending_care(pending, false):
			_set_busy(false)
			return false
		_adopt_companion(_roster_row(anima_id), row)
		_anima.apply(loaded)
		_refresh_care()
		if not care_synced:
			await _sync_active_care(false)
		_set_busy(false)
		return true

	# Portal menyala sementara request terbang. Art-nya sudah ada di cache lokal,
	# jadi satu-satunya yang benar-benar ditunggu adalah izin server sebelum
	# sprite ditukar — dan 0,46 detik dissolve + charge biasanya sudah menutupinya.
	_dispatch_summon(pending)
	_switch_destination(BottomNav.HOME)
	await _anima.summon_dissolve()
	await _incubator.start_portal()
	if not await _await_summon():
		_collection_view.set_sheet_busy(false)
		await _incubator.burst()
		await _anima.summon_reveal()
		# Companion lama bisa saja sedang tidur atau Dormant; reveal mengembalikan
		# transform-nya, `_refresh_care()` yang mengembalikan pose-nya.
		_refresh_care()
		_set_busy(false)
		return false

	_adopt_companion(_roster_row(anima_id), row)
	_anima.apply(loaded)
	_anima.visible = false
	await _incubator.burst()
	await _anima.summon_reveal()
	_refresh_care()
	if not care_synced:
		await _sync_active_care(false)
	_set_busy(false)
	_say(tr("COLLECTION_SUMMON_SUCCESS") % LocaleManager.display_name(_current_anima), true)
	return true


## Companion baru sudah disetujui server: `synced` adalah row hasil `care_anima`
## kalau roster sempat menerimanya, `fallback` row yang dipilih pemain.
func _adopt_companion(synced: Dictionary, fallback: Dictionary) -> void:
	_stop_evolution_chamber()
	_current_anima = normalize_anima_data(fallback if synced.is_empty() else synced)
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


func _dispatch_summon(pending: Dictionary) -> void:
	_summon_in_flight = true
	_summon_result = await _send_pending_care(pending, false)
	_summon_in_flight = false
	_summon_settled.emit()


func _await_summon() -> bool:
	if _summon_in_flight:
		await _summon_settled
	return _summon_result


func _open_battle_anima_picker() -> void:
	if _busy or not is_instance_valid(_battle_pick_sheet):
		return
	_battle_pick_sheet.open_picker(
		_roster,
		_summoned_id(),
		_thumbnail_for,
		_battle_view.is_training_lobby()
	)


func _battle_pick_start(row: Dictionary) -> void:
	if _busy or row.is_empty():
		return
	if is_instance_valid(_battle_pick_sheet):
		_battle_pick_sheet.close()
	var anima_id := str(row.get("id", ""))
	if anima_id != _summoned_id():
		var ok := await _activate_anima(row, false, true)
		if not ok:
			if _destination == BottomNav.BATTLE:
				_battle_view.set_lobby(_current_anima)
			return
	await _start_battle()


func _open_scan() -> void:
	_collection_view.close_sheet()
	_switch_destination(BottomNav.SCAN)


func _retry_roster() -> void:
	if _busy:
		return
	_set_busy(true)
	_set_home_shell_state(&"loading")
	LoadingScreen.show_screen("HOME_LOADING_META")
	_say(tr("STATUS_LOADING_COLLECTION"))
	var loaded := await _reload_roster()
	if loaded and not _roster.is_empty():
		var active := _active_row()
		await _present_row(active if not active.is_empty() else _roster[0])
	elif loaded:
		_set_home_shell_state(&"empty")
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
	var account_epoch := GameState.session_epoch
	var res := await Backend.delete_anima(anima_id)
	if not Backend.response_applies(res, account_epoch):
		return
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


func _show_evolve_confirmation(row: Dictionary) -> void:
	if (
		_busy
		or row.is_empty()
		or not _evolution_enabled()
		or not CareRules.evolution_ready(row)
	):
		return
	if not GameState.pending_evolution.is_empty():
		_say(tr("EVOLUTION_ALREADY_ACTIVE"), true)
		return
	_pending_evolve_row = row.duplicate(true)
	_modal_context = &"evolve"
	_shell_modal.open_confirm(
		tr("EVOLVE_CONFIRM_TITLE"),
		tr("EVOLVE_CONFIRM_BODY") % LocaleManager.display_name(row),
		tr("EVOLVE_CONFIRM_ACTION"),
		tr("ACTION_CANCEL")
	)


func _evolve_confirmed() -> void:
	var row := _pending_evolve_row
	_pending_evolve_row = {}
	if row.is_empty() or not _evolution_enabled() or not CareRules.evolution_ready(row):
		return
	if not GameState.pending_evolution.is_empty():
		_say(tr("EVOLUTION_ALREADY_ACTIVE"), true)
		return
	await _start_evolution_ritual(row)


func _start_evolution_ritual(row: Dictionary) -> void:
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return
	var prior_stage := CareRules.committed_stage(row)
	var pending := GameState.begin_evolution(anima_id, prior_stage)
	if pending.is_empty():
		_say(tr("EVOLUTION_ALREADY_ACTIVE"), true)
		return
	_evolution_art_error_reported = false
	row["status"] = "evolving"
	_sync_evolution_row(row)
	if anima_id == str(_current_anima.get("id", "")) and _anima.visible:
		await _anima.summon_dissolve()
	# Begin Evolution selalu mendarat di lobby Home: chamber adalah status global
	# yang hidup lebih lama daripada profile tempat ritual dimulai.
	_switch_destination(BottomNav.HOME)
	_refresh_stats()
	_populate_collection()
	_say(tr("EVOLUTION_STARTED") % LocaleManager.display_name(row), true)

	var account_epoch := GameState.session_epoch
	var res := await Backend.evolve_anima(anima_id, str(pending.get("idempotency_key", "")))
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok:
		var code := str(GameState.as_dict(res.data).get("error", res.error))
		if code == "FEATURE_DISABLED":
			GameState.finish_evolution()
			_stop_evolution_chamber()
			_say(tr("EVOLUTION_FEATURE_DISABLED"), true)
			await _restore_evolution_after_abort(anima_id)
			return
		var confirmed := await _fetch_evolution_row(anima_id)
		if not confirmed.is_empty():
			_sync_evolution_row(confirmed)
			var confirmed_stage := CareRules.committed_stage(confirmed)
			if str(confirmed.get("status", "")) == "ready" and confirmed_stage > prior_stage:
				if not await _complete_evolution(confirmed, true):
					await _wait_for_evolution(
						anima_id, prior_stage, confirmed_stage, true
					)
				return
			if not CareRules.is_evolving(confirmed):
				GameState.finish_evolution()
				_stop_evolution_chamber()
				_say(tr("EVOLUTION_START_ERROR"), true)
				await _restore_evolution_after_abort(anima_id)
				return
		# Transport/5xx can arrive after begin_evolution committed. Keep the same
		# key and poll authoritative state instead of risking a second paid job.
		await _wait_for_evolution(
			anima_id,
			prior_stage,
			int(pending.get("target_stage", prior_stage + 1))
		)
		return

	var body := GameState.as_dict(res.data)
	if typeof(res.data) != TYPE_DICTIONARY:
		body = {}
	var target_stage := int(body.get("target_stage", pending.get("target_stage", prior_stage + 1)))
	GameState.note_evolution_started(
		str(body.get("generation_id", "")),
		target_stage,
		str(body.get("suggested_name", ""))
	)
	await _wait_for_evolution(anima_id, prior_stage, target_stage)


func _resume_pending_evolution(restore_navigation: bool = true) -> void:
	if _evolution_resume_in_flight or _evolution_poll_in_flight:
		return
	var pending := GameState.pending_evolution
	if pending.is_empty():
		return
	_evolution_resume_in_flight = true
	var anima_id := str(pending.get("anima_id", ""))
	if anima_id.is_empty():
		GameState.finish_evolution()
		_evolution_resume_in_flight = false
		return
	var row := _roster_row(anima_id)
	if row.is_empty():
		row = await _fetch_evolution_row(anima_id)
	if row.is_empty():
		_evolution_resume_in_flight = false
		_say(tr("EVOLUTION_PENDING"), true)
		return
	_sync_evolution_row(row)
	var prior_stage := int(pending.get("prior_stage", CareRules.committed_stage(row)))
	var target_stage := int(pending.get("target_stage", prior_stage + 1))
	var stage := CareRules.committed_stage(row)
	if str(row.get("status", "")) == "ready" and stage > prior_stage:
		_evolution_resume_in_flight = false
		if not await _complete_evolution(row, restore_navigation):
			await _wait_for_evolution(
				anima_id, prior_stage, target_stage, restore_navigation
			)
		return
	if CareRules.is_evolving(row):
		_apply_evolution_chamber_for_row(row, _destination == BottomNav.HOME)
	var res := await Backend.evolve_anima(
		anima_id,
		str(pending.get("idempotency_key", "")),
		bool(pending.get("resume_only", false))
	)
	if res.ok and typeof(res.data) == TYPE_DICTIONARY:
		var body: Dictionary = res.data
		GameState.note_evolution_started(
			str(body.get("generation_id", pending.get("generation_id", ""))),
			int(body.get("target_stage", target_stage)),
			str(body.get("suggested_name", ""))
		)
		target_stage = int(GameState.pending_evolution.get("target_stage", target_stage))
	elif not res.ok:
		var code := str(GameState.as_dict(res.data).get("error", res.error))
		if code == "FEATURE_DISABLED":
			_evolution_resume_in_flight = false
			GameState.finish_evolution()
			_stop_evolution_chamber()
			_say(tr("EVOLUTION_FEATURE_DISABLED"), true)
			await _restore_evolution_after_abort(anima_id)
			return
		if code == "EVOLUTION_NOT_FOUND":
			_evolution_resume_in_flight = false
			var latest := await _fetch_evolution_row(anima_id)
			if latest.is_empty():
				await _wait_for_evolution(
					anima_id, prior_stage, target_stage, restore_navigation
				)
				return
			if (
				str(latest.get("status", "")) == "ready"
				and CareRules.committed_stage(latest) > prior_stage
			):
				if not await _complete_evolution(latest, restore_navigation):
					await _wait_for_evolution(
						anima_id, prior_stage, target_stage, restore_navigation
					)
				return
			if CareRules.is_evolving(latest):
				await _wait_for_evolution(
					anima_id, prior_stage, target_stage, restore_navigation
				)
				return
			await _fail_evolution(latest, restore_navigation)
			return
		if code in [
			"EVOLUTION_FAILED",
			"GENERATION_COMPLETION_TIMEOUT",
			"GENERATION_DISPATCH_TIMEOUT",
		]:
			_evolution_resume_in_flight = false
			await _fail_evolution(
				row,
				restore_navigation,
				"EVOLUTION_FAILED_BODY" if code == "EVOLUTION_FAILED"
					else "EVOLUTION_TIMEOUT_BODY"
			)
			return
	_evolution_resume_in_flight = false
	await _wait_for_evolution(anima_id, prior_stage, target_stage, restore_navigation)


func _wait_for_evolution(
	anima_id: String,
	prior_stage: int,
	target_stage: int,
	restore_navigation: bool = true
) -> void:
	if _evolution_poll_in_flight:
		return
	_evolution_poll_in_flight = true
	var account_epoch := GameState.session_epoch
	_say(tr("EVOLUTION_SYNTHESIZING"))
	var remaining_poll_sec := EVOLUTION_POLL_TIMEOUT_SEC
	while remaining_poll_sec > 0.0:
		await get_tree().create_timer(EVOLUTION_POLL_INTERVAL_SEC).timeout
		remaining_poll_sec -= EVOLUTION_POLL_INTERVAL_SEC
		var res := await Backend.fetch_anima(anima_id)
		if not Backend.response_applies(res, account_epoch):
			return
		if not res.ok or typeof(res.data) != TYPE_ARRAY:
			continue
		var rows: Array = res.data
		if rows.is_empty():
			continue
		var row := normalize_anima_data(GameState.as_dict(rows[0]))
		var status := str(row.get("status", ""))
		var stage := CareRules.committed_stage(row)
		if status == "evolving":
			_sync_evolution_row(row)
			continue
		if status == "ready" and stage >= target_stage:
			if await _complete_evolution(row, restore_navigation):
				_evolution_poll_in_flight = false
				return
			continue
		if status == "failed" or (status == "ready" and stage <= prior_stage):
			_evolution_poll_in_flight = false
			await _fail_evolution(row, restore_navigation)
			return

	_evolution_poll_in_flight = false
	_say(tr("EVOLUTION_PENDING"))
	var evolving_row := _roster_row(anima_id)
	if not evolving_row.is_empty():
		_apply_evolution_chamber_for_row(evolving_row, _destination == BottomNav.HOME)
	await get_tree().create_timer(EVOLUTION_POLL_RETRY_SEC).timeout
	if (
		_pending_evolution_matches(anima_id)
		and not _evolution_resume_in_flight
		and not _evolution_poll_in_flight
	):
		call_deferred("_resume_pending_evolution", restore_navigation)


func _complete_evolution(
	row: Dictionary,
	_restore_navigation: bool
) -> bool:
	var anima_id := str(row.get("id", ""))
	var was_active := anima_id == str(_current_anima.get("id", ""))
	var chamber_active := _evolution_chamber_active and was_active
	_sync_evolution_row(row)
	var art_stage := CareRules.committed_stage(row)
	var loaded := await _prepare_anima_art(
		str(row.get("species_key", "")),
		str(row.get("color_bucket", "")),
		art_stage,
		str(row.get("sheet_path", "")),
		GameState.as_dict(row.get("manifest")),
		false,
		anima_id,
		art_stage
	)
	if not bool(loaded.get("ok", false)):
		if not _evolution_art_error_reported:
			_say(tr("STATUS_ART_DOWNLOAD_ERROR"), true)
			_evolution_art_error_reported = true
		if chamber_active:
			_apply_evolution_chamber_for_row(row, _destination == BottomNav.HOME)
		return false
	var suggested := await _evolution_suggested_name(anima_id)
	GameState.finish_evolution()
	_evolution_art_error_reported = false
	_sync_evolution_row(row)
	GameState.remember_boot_cache({"roster": _roster, "profile": GameState.profile})
	if was_active and bool(loaded.get("ok", false)):
		_anima.apply(loaded)
		if chamber_active:
			await _incubator.burst()
			await _anima.hatch_reveal()
		else:
			_anima.visible = true
	_stop_evolution_chamber()
	_refresh_stats()
	_refresh_care()
	_populate_collection()
	_enqueue_outcome_dialog({
		"kind": "evolution_success",
		"row": row.duplicate(true),
		"portrait": _thumbnail_for(row),
		"suggested_name": suggested,
		"was_active": was_active,
	})
	return true


func _evolution_suggested_name(anima_id: String) -> String:
	var pending := GameState.pending_evolution
	var name := str(pending.get("suggested_name", "")).strip_edges()
	if not name.is_empty():
		return name
	var key := str(pending.get("idempotency_key", ""))
	if anima_id.is_empty() or key.is_empty():
		return ""
	var account_epoch := GameState.session_epoch
	var res := await Backend.evolve_anima(anima_id, key, false)
	if not Backend.response_applies(res, account_epoch):
		return ""
	if not res.ok or typeof(res.data) != TYPE_DICTIONARY:
		return ""
	return str(res.data.get("suggested_name", "")).strip_edges()


func _fail_evolution(
	row: Dictionary,
	restore_navigation: bool,
	body_key: String = "EVOLUTION_FAILED_BODY"
) -> void:
	GameState.finish_evolution()
	_evolution_art_error_reported = false
	var anima_id := str(row.get("id", ""))
	var was_active := anima_id == str(_current_anima.get("id", ""))
	_stop_evolution_chamber()
	await _reload_roster()
	if was_active:
		var refreshed := _roster_row(anima_id)
		if not refreshed.is_empty():
			await _present_row(refreshed)
	elif restore_navigation:
		_refresh_stats()
		_populate_collection()
	_queue_evolution_failure_dialog(anima_id, LocaleManager.display_name(row), body_key)


# A toast is the wrong shape for this one: the ritual runs for minutes in the
# background, so the player is rarely looking when it lands, and the only way
# back in is a button that lives two screens away. The dialog carries the retry.
func _queue_evolution_failure_dialog(
	anima_id: String,
	display_name: String,
	body_key: String
) -> void:
	_enqueue_outcome_dialog({
		"kind": "evolution_failure",
		"anima_id": anima_id,
		"display_name": display_name,
		"body_key": body_key,
	})


func _present_evolution_failure_outcome(queued: Dictionary) -> void:
	var anima_id := str(queued.get("anima_id", ""))
	var row := _roster_row(anima_id)
	var body := tr(str(queued.get("body_key", "EVOLUTION_FAILED_BODY"))) % str(
		queued.get("display_name", "")
	)
	# Retry only when the server would accept one; otherwise the locked outcome
	# still explains what happened and exposes one explicit Close action.
	if row.is_empty() or not _evolution_enabled() or not CareRules.evolution_ready(row):
		_modal_context = &"evolution_failure_info"
		_shell_modal.open_info(
			tr("EVOLUTION_FAILED_DIALOG_TITLE"), body, tr("CORE_INFO_CLOSE"), "", false
		)
		return
	_pending_evolve_row = row.duplicate(true)
	_modal_context = &"evolution_failure"
	_shell_modal.open_confirm(
		tr("EVOLUTION_FAILED_DIALOG_TITLE"),
		body,
		tr("ACTION_RETRY"),
		tr("CORE_INFO_CLOSE"),
		false,
		false
	)


func _evolution_success_copy(row: Dictionary) -> String:
	var parts: PackedStringArray = [
		tr("EVOLUTION_SUCCESS") % [
			LocaleManager.display_name(row),
			LocaleManager.form_name_for_row(row),
		]
	]
	var strike := LocaleManager.move_name(row, "strike")
	var surge := LocaleManager.move_name(row, "surge")
	var strike_fx := str(row.get("strike_effect_id", "")).strip_edges()
	var surge_fx := str(row.get("surge_effect_id", "")).strip_edges()
	if not strike_fx.is_empty() or not surge_fx.is_empty():
		parts.append(
			tr("EVOLUTION_SUCCESS_MOVES") % [
				strike,
				surge,
				LocaleManager.effect_name(strike_fx) if not strike_fx.is_empty() else tr("VALUE_UNAVAILABLE"),
				LocaleManager.effect_name(surge_fx) if not surge_fx.is_empty() else tr("VALUE_UNAVAILABLE"),
			]
		)
	return "\n".join(parts)


func _summon_evolution_outcome(row: Dictionary) -> void:
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return
	if anima_id != _summoned_id():
		await _activate_anima(row, false, false)
		return
	if _busy:
		return
	_set_busy(true)
	_switch_destination(BottomNav.HOME)
	_anima.visible = false
	await _incubator.start_portal()
	await _incubator.burst()
	await _anima.summon_reveal()
	_refresh_care()
	_set_busy(false)


func _apply_evolution_chamber_for_row(row: Dictionary, on_home: bool) -> void:
	var anima_id := str(row.get("id", ""))
	if (
		not on_home
		or row.is_empty()
		or (
			not CareRules.is_evolving(row)
			and not _pending_evolution_matches(anima_id)
		)
	):
		_stop_evolution_chamber()
		return
	_evolution_chamber_active = true
	_first_anima_effect.set_active(false)
	_anima.visible = false
	_stage.visible = _destination == BottomNav.HOME
	_incubator.align_visual_center(_anima.body_center_global())
	_incubator.start_evolution()
	_home_view.set_evolution(row)
	_update_hud_identity()


func _stop_evolution_chamber() -> void:
	if not _evolution_chamber_active:
		return
	_evolution_chamber_active = false
	_incubator.stop()
	if _destination == BottomNav.HOME:
		if not _current_anima.is_empty():
			_home_view.set_anima(_current_anima, _busy)
			_update_hud_identity()
		if _anima.sprite_frames != null:
			_anima.visible = true


func _fetch_evolution_row(anima_id: String) -> Dictionary:
	var account_epoch := GameState.session_epoch
	var fetched := await Backend.fetch_anima(anima_id)
	if not Backend.response_applies(fetched, account_epoch):
		return {}
	if (
		not fetched.ok
		or typeof(fetched.data) != TYPE_ARRAY
		or (fetched.data as Array).is_empty()
	):
		return {}
	return normalize_anima_data(GameState.as_dict((fetched.data as Array)[0]))


func _restore_evolution_after_abort(anima_id: String) -> void:
	_evolution_art_error_reported = false
	await _reload_roster()
	var restored := _roster_row(anima_id)
	if anima_id == str(_current_anima.get("id", "")) and not restored.is_empty():
		await _present_row(restored)
	else:
		if anima_id == str(_profile_anima.get("id", "")) and not restored.is_empty():
			_profile_anima = restored.duplicate(true)
		_refresh_stats()
		_refresh_care()
		_populate_collection()


func _sync_evolution_row(row: Dictionary) -> void:
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return
	var normalized := _overlay_pending_evolution(normalize_anima_data(row))
	_upsert_roster(normalized)
	if anima_id == str(_current_anima.get("id", "")):
		_current_anima = normalized.duplicate(true)
	if anima_id == str(_profile_anima.get("id", "")):
		_profile_anima = normalized.duplicate(true)


func _evolving_roster_row() -> Dictionary:
	for row in _roster:
		if CareRules.is_evolving(row):
			return row
	return {}


func _resume_server_evolution(row: Dictionary, restore_navigation: bool) -> void:
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return
	if GameState.pending_evolution.is_empty():
		GameState.begin_evolution(anima_id, CareRules.committed_stage(row), true)
	call_deferred("_resume_pending_evolution", restore_navigation)


func _pending_evolution_matches(anima_id: String) -> bool:
	return (
		not anima_id.is_empty()
		and not GameState.pending_evolution.is_empty()
		and str(GameState.pending_evolution.get("anima_id", "")) == anima_id
	)


func _overlay_pending_evolution(row: Dictionary) -> Dictionary:
	var overlaid := row.duplicate(true)
	if _pending_evolution_matches(str(overlaid.get("id", ""))):
		overlaid["status"] = "evolving"
	return overlaid


func _evolution_enabled() -> bool:
	return bool(GameState.client_config.get("feature_evolution", false))


func _synthesis_enabled() -> bool:
	return bool(GameState.client_config.get("feature_synthesis", false))


func _show_rename(anima_id: String, draft: String = "") -> void:
	var target := _current_anima
	if anima_id == str(_profile_anima.get("id", "")):
		target = _profile_anima
	elif anima_id != str(_current_anima.get("id", "")):
		target = _roster_row(anima_id)
		if not target.is_empty():
			_profile_anima = target
	if _busy or anima_id.is_empty() or anima_id != str(target.get("id", "")):
		return
	_pending_rename_id = anima_id
	var text := draft.strip_edges()
	_pending_rename_text = (
		text if not text.is_empty() else str(target.get("nickname", "")).strip_edges()
	)
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
		tr("ANIMA_RENAME_PLACEHOLDER"),
		AnimaDetailsView.NAME_MAX_LENGTH
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
	if not AnimaDetailsView.is_valid_anima_name(nickname):
		_say(tr("ANIMA_RENAME_INVALID"), true)
		call_deferred("_popup_rename")
		return
	if _busy:
		call_deferred("_popup_rename")
		return

	_set_busy(true)
	var account_epoch := GameState.session_epoch
	var res := await Backend.rename_anima(anima_id, nickname)
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok or typeof(res.data) != TYPE_ARRAY or (res.data as Array).is_empty():
		_set_busy(false)
		_say(_anima_rename_error(str(res.error)), true)
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
	call_deferred("_maybe_prompt_seeker_onboarding")


## Trigger `animas_validate_nickname` menjawab lewat PostgREST, jadi kode ini
## sampai apa adanya di `res.error` — sama seperti kontrak error seeker.
func _anima_rename_error(error: String) -> String:
	match error:
		"INVALID_ANIMA_NAME":
			return tr("ANIMA_RENAME_INVALID")
		"ANIMA_NAME_RESERVED":
			return tr("ANIMA_RENAME_RESERVED")
		_:
			return tr("ANIMA_RENAME_ERROR")


func _modal_confirmed(text: String) -> void:
	var context := _modal_context
	var outcome := _active_outcome_dialog
	_modal_context = &""
	if context in [
		&"level_up", &"expedition_level_up", &"synthesis_success",
		&"synthesis_failure", &"evolution_failure", &"evolution_failure_info"
	]:
		_active_outcome_dialog = {}
	match context:
		&"delete":
			_delete_confirmed()
		&"evolve", &"evolution_failure":
			_evolve_confirmed()
		&"synthesis_attempt":
			_synthesis_attempt_confirmed()
		&"rename":
			_rename_confirmed(text)
		&"confirm_transfer_guest":
			_start_google_transfer()
		&"restore_google":
			_start_google_separate()
		&"sign_out":
			_sign_out()
		&"delete_account":
			_delete_account()
		&"rename_seeker":
			_rename_seeker(text)
		&"atlas_publish":
			_commit_atlas_publish(_pending_atlas_publish_id, true)
		&"atlas_publish_signin":
			_show_sign_in_confirmation()
		&"gallery_appeal":
			_commit_gallery_appeal(_pending_gallery_appeal_id)
		&"chapter_announcement":
			_ack_chapter_popup(true)
		&"retreat":
			_retreat_confirmed()
		&"expedition_abandon":
			if is_instance_valid(_expedition_controller):
				_expedition_controller.abandon()
		&"expedition_level_up":
			_show_next_expedition_level_up()
		&"synthesis_success":
			if int(outcome.get("session_epoch", -1)) == GameState.session_epoch:
				_show_synthesis_result(GameState.as_dict(outcome.get("row")))
	call_deferred("_present_queued_dialogs_after_modal")


func _modal_choice_selected(choice: String) -> void:
	var context := _modal_context
	var outcome := _active_outcome_dialog
	_modal_context = &""
	if context == &"evolution_success":
		_active_outcome_dialog = {}
		if int(outcome.get("session_epoch", -1)) != GameState.session_epoch:
			call_deferred("_present_queued_dialogs_after_modal")
			return
		var row := GameState.as_dict(outcome.get("row"))
		if choice == "primary":
			await _summon_evolution_outcome(row)
			call_deferred("_present_queued_dialogs_after_modal")
			return
		await get_tree().create_timer(0.20).timeout
		_show_rename(
			str(row.get("id", "")),
			str(outcome.get("suggested_name", LocaleManager.display_name(row)))
		)
		return
	if context != &"sign_in_google":
		return
	if sign_in_choice_moves_guest(choice, _sign_in_move_first):
		_show_transfer_confirmation()
	else:
		_start_google_separate()
	call_deferred("_present_queued_dialogs_after_modal")


func _modal_canceled() -> void:
	var context := _modal_context
	_modal_context = &""
	if context in [
		&"level_up", &"expedition_level_up", &"synthesis_success",
		&"synthesis_failure", &"evolution_failure", &"evolution_failure_info"
	]:
		_active_outcome_dialog = {}
	if context == &"delete":
		_pending_delete_id = ""
	elif context == &"evolve" or context == &"evolution_failure":
		_pending_evolve_row = {}
	elif context == &"synthesis_attempt":
		_pending_synthesis_payload = {}
	elif context == &"rename":
		_pending_rename_id = ""
		_pending_rename_text = ""
		call_deferred("_maybe_prompt_seeker_onboarding")
	elif context == &"atlas_publish":
		_pending_atlas_publish_id = ""
	elif context == &"atlas_publish_signin":
		_publish_after_sign_in = {}
	elif context == &"gallery_appeal":
		_pending_gallery_appeal_id = ""
	elif context == &"chapter_announcement":
		_ack_chapter_popup(false)
	elif context == &"retreat":
		_pending_retreat = ""
	elif context == &"expedition_level_up":
		_show_next_expedition_level_up()
	call_deferred("_present_queued_dialogs_after_modal")


func _show_details_help(title: String, body: String) -> void:
	_modal_context = &"details_help"
	_shell_modal.open_info(title, body, tr("CORE_INFO_CLOSE"))


func _refresh_chapter_announcements() -> void:
	_chapter_announcement_revision += 1
	var revision := _chapter_announcement_revision
	var account_epoch := GameState.session_epoch
	var res := await Backend.expedition("announcements")
	if not Backend.response_applies(res, account_epoch):
		return
	if revision != _chapter_announcement_revision:
		return
	if res.ok:
		_apply_chapter_announcements(GameState.as_dict(res.data), false)
	elif res.error == "FEATURE_DISABLED":
		_apply_chapter_announcements({}, false)


func _apply_chapter_announcements(
	announcements: Dictionary,
	advance_revision: bool = true
) -> void:
	if advance_revision:
		_chapter_announcement_revision += 1
	_chapter_announcements = announcements.duplicate(true)
	var unread: Array = (
		announcements.get("unread", [])
		if typeof(announcements.get("unread")) == TYPE_ARRAY else []
	)
	_pending_chapter_popup = (
		announcements.get("home_popup", []).duplicate(true)
		if typeof(announcements.get("home_popup")) == TYPE_ARRAY else []
	)
	var has_new := not unread.is_empty()
	_bottom_nav.set_battle_badge(has_new)
	_battle_view.set_expedition_new(has_new)
	call_deferred("_maybe_show_chapter_popup")


func _maybe_show_chapter_popup() -> void:
	if (
		_pending_chapter_popup.is_empty()
		or _destination != BottomNav.HOME
		or _busy
		or _update_required
		or _shell_modal.visible
		or _seeker_onboarding_sheet.visible
		or (
			not _roster.is_empty()
			and not profile_value_present(GameState.profile, &"seeker_name")
		)
	):
		return
	var titles := PackedStringArray()
	var descriptions := PackedStringArray()
	for value in _pending_chapter_popup:
		var summary := GameState.as_dict(GameState.as_dict(value).get("summary"))
		var title := str(summary.get("title", tr("EXPEDITION_CHAPTER")))
		var description := str(summary.get("description", ""))
		titles.append(title)
		if not description.is_empty():
			descriptions.append(description)
	var body := (
		tr("CHAPTER_ANNOUNCEMENT_ONE") % [
			titles[0] if not titles.is_empty() else tr("EXPEDITION_CHAPTER"),
			descriptions[0] if not descriptions.is_empty() else tr("EXPEDITION_CHAPTER_READY"),
		]
		if _pending_chapter_popup.size() == 1
		else tr("CHAPTER_ANNOUNCEMENT_MANY") % [
			LocaleManager.format_integer(_pending_chapter_popup.size()),
			", ".join(titles),
		]
	)
	_modal_context = &"chapter_announcement"
	_shell_modal.open_info(
		tr("CHAPTER_ANNOUNCEMENT_TITLE"),
		body,
		tr("CHAPTER_ANNOUNCEMENT_OPEN")
	)


func _ack_chapter_popup(open_expedition: bool) -> void:
	var popup := _pending_chapter_popup.duplicate(true)
	_pending_chapter_popup = []
	var chapter_ids: Array[String] = []
	for value in popup:
		var chapter_id := str(GameState.as_dict(value).get("chapter_id", ""))
		if not chapter_id.is_empty():
			chapter_ids.append(chapter_id)
	if not chapter_ids.is_empty():
		_chapter_announcement_revision += 1
		var revision := _chapter_announcement_revision
		var account_epoch := GameState.session_epoch
		var res := await Backend.expedition("ack_home_popup", {"chapter_ids": chapter_ids})
		if not Backend.response_applies(res, account_epoch):
			return
		if res.ok and revision == _chapter_announcement_revision:
			_apply_chapter_announcements(GameState.as_dict(res.data), false)
	if open_expedition:
		_switch_destination(BottomNav.BATTLE)
		await _expedition_controller.open()


func _maybe_prompt_seeker_onboarding() -> void:
	if (
		_busy
		or _roster.is_empty()
		or profile_value_present(GameState.profile, &"seeker_name")
		or _shell_modal.visible
		or _seeker_onboarding_sheet.visible
	):
		return
	_seeker_onboarding_sheet.show_for_profile()


func _complete_seeker_profile(
	seeker_name: String,
	birth_year: Variant,
	gender: Variant
) -> void:
	if _busy:
		return
	_seeker_onboarding_sheet.set_busy(true)
	var account_epoch := GameState.session_epoch
	var res := await Backend.seeker("complete", {
		"seeker_name": seeker_name,
		"birth_year": birth_year,
		"gender": gender,
	})
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok:
		_seeker_onboarding_sheet.show_error(
			_seeker_error(res.error),
			&"birth_year" if res.error == "INVALID_BIRTH_YEAR" else &"name"
		)
		return
	GameState.profile.merge(GameState.as_dict(res.data), true)
	_seeker_onboarding_sheet.close()
	_refresh_header()
	_say(tr("SEEKER_CREATED"), true)
	call_deferred("_maybe_show_chapter_popup")


func _on_bottom_nav_destination(destination: StringName) -> void:
	if destination == BottomNav.MENU:
		if _menu_popover.visible:
			_menu_popover.close()
		else:
			_menu_popover.show_menu()
		return
	_menu_popover.close()
	_switch_destination(destination)


func _remember_overlay_origin() -> void:
	if _destination in [BottomNav.HOME, BottomNav.SCAN, BottomNav.BATTLE, BottomNav.COLLECTION]:
		_overlay_return_destination = _destination
	# Opening Atlas/Seeker Profile from on top of the Anima Profile isn't a
	# base destination itself, so without this the return target stayed
	# whatever base screen was last visited -- which could be a stale
	# Collection visit from earlier in the session even when this whole chain
	# actually started at Home. Chaining through Profile's own already-correct
	# return keeps one Back press landing where the player actually came from.
	elif _destination == ANIMA_PROFILE_DEST:
		_overlay_return_destination = _profile_return_destination


func _return_from_overlay() -> void:
	_switch_destination(_overlay_return_destination)


func _open_atlas() -> void:
	_remember_overlay_origin()
	_switch_destination(ATLAS_DEST)


func _toggle_gallery_publish(anima_id: String, publish: bool) -> void:
	if _busy or anima_id.is_empty():
		return
	# `gallery/publish` menolak guest sebelum apa pun terjadi, jadi menawarkan
	# tombolnya lalu menjawab toast adalah jalan buntu. Guest mendapat penjelasan
	# singkat plus jalan keluarnya; consent asli tetap menunggu akun Google.
	if publish and GameState.is_anonymous():
		_publish_after_sign_in = {"anima_id": anima_id, "uid": GameState.uid()}
		_modal_context = &"atlas_publish_signin"
		_shell_modal.open_confirm(
			tr("GALLERY_PUBLISH"),
			tr("ATLAS_PUBLISH_SIGN_IN_BODY"),
			tr("SEEKER_SIGN_IN_GOOGLE"),
			tr("ACTION_CANCEL")
		)
		return
	if publish:
		_pending_atlas_publish_id = anima_id
		_modal_context = &"atlas_publish"
		var target := _roster_row(anima_id)
		_shell_modal.open_confirm(
			tr("ATLAS_PUBLISH_TITLE"),
			(
				tr("ATLAS_PUBLISH_SYNTHESIS_CONSENT")
				if not GameState.as_dict(target.get("synthesis_history")).is_empty()
				else tr("ATLAS_PUBLISH_CONSENT")
			),
			tr("ATLAS_PUBLISH_ACTION"),
			tr("ACTION_CANCEL")
		)
		return
	await _commit_atlas_publish(anima_id, false)


func _commit_atlas_publish(anima_id: String, publish: bool) -> void:
	if _busy or anima_id.is_empty():
		return
	_pending_atlas_publish_id = ""
	_details_view.set_gallery_pending(true, publish)
	_set_busy(true)
	var operation := "publish" if publish else "unpublish"
	var target := _roster_row(anima_id)
	var payload := {"anima_id": anima_id}
	if publish and not GameState.as_dict(target.get("synthesis_history")).is_empty():
		payload["synthesis_source_consent"] = true
	var account_epoch := GameState.session_epoch
	var res := await Backend.atlas(operation, payload)
	if not Backend.response_applies(res, account_epoch):
		_details_view.set_gallery_pending(false)
		_set_busy(false)
		return
	if res.ok:
		var result := GameState.as_dict(res.data)
		if publish and str(result.get("moderation_status", "")) == "pending":
			# v2 dua-pass: masih tidak pasti sesudah opini kedua, bukan galat —
			# masuk antrean manual, bukan langsung terbit atau ditolak.
			_say(tr("GALLERY_SUBMITTED_FOR_REVIEW"), false)
		else:
			_say(tr("GALLERY_PUBLISHED") if publish else tr("GALLERY_UNPUBLISHED"), false)
		await _refresh_gallery_status(anima_id)
	else:
		_say(_gallery_error(res.error), true)
		if res.error == "GALLERY_MODERATION_REJECTED":
			# `appeal_available` must be stated, not left to default: a rejection
			# that just happened has no appeal on record yet, and defaulting to
			# false told the player they had "already requested a review" while
			# hiding the appeal they are in fact entitled to. The next
			# `my_status` refresh is what corrects it if that ever stops holding.
			_details_view.set_gallery_status({
				"available": false,
				"published": false,
				"rejected": true,
				"appeal_available": true,
			})
	_details_view.set_gallery_pending(false)
	_set_busy(false)


func _gallery_error(code: String) -> String:
	match code:
		"GOOGLE_IDENTITY_REQUIRED", "ACCOUNT_STILL_ANONYMOUS":
			return tr("GALLERY_LINK_REQUIRED")
		"GALLERY_MODERATION_REJECTED":
			return tr("GALLERY_MODERATION_REJECTED")
		"FEATURE_DISABLED":
			return tr("ATLAS_DISABLED")
		"ANIMA_NOT_TYPING_V2", "ANIMA_NOT_READY", "ANIMA_NO_ART":
			return tr("GALLERY_PUBLISH_UNAVAILABLE")
		"ENTRY_NOT_REJECTED":
			return tr("GALLERY_APPEAL_NOT_REJECTED")
		"APPEAL_ALREADY_USED":
			return tr("GALLERY_APPEAL_ALREADY_USED")
		"ATLAS_PUBLISH_SUSPENDED":
			return tr("GALLERY_PUBLISH_SUSPENDED")
		_:
			var key := "ERROR_%s" % code
			return tr(key) if tr(key) != key else tr("ATLAS_ERROR")


func _refresh_gallery_status(anima_id: String = "") -> void:
	var target_id := anima_id
	if target_id.is_empty():
		var row := _profile_anima if not _profile_anima.is_empty() else _current_anima
		target_id = str(row.get("id", ""))
	if target_id.is_empty():
		_details_view.set_gallery_status({"available": false})
		return
	_gallery_status_revision += 1
	var revision := _gallery_status_revision
	var account_epoch := GameState.session_epoch
	var res := await Backend.atlas("my_status", {"anima_id": target_id})
	if not Backend.response_applies(res, account_epoch):
		return
	if revision != _gallery_status_revision:
		return
	_details_view.set_gallery_status(_gallery_status_from_response(res))


## Bersama oleh Anima Profile (`_refresh_gallery_status`) dan preview sheet
## Collection (`_sync_collection_atlas_preview`) supaya keduanya membaca
## `my_status` dengan cara yang sama persis -- dua salinan parsing berarti dua
## tempat yang bisa diam-diam berbeda kalau bentuk respons berubah.
func _gallery_status_from_response(res: Dictionary) -> Dictionary:
	if not res.ok:
		return {"available": false}
	var data := GameState.as_dict(res.data)
	var entry := GameState.as_dict(data.get("entry"))
	var moderation_status := str(entry.get("moderation_status", ""))
	var moderation_rejected := moderation_status == "rejected"
	var under_review := moderation_status == "pending"
	var available := (
		bool(data.get("ready", false))
		and bool(data.get("typing_v2", false))
		and not moderation_rejected
		and not under_review
	)
	return {
		"available": available,
		"published": bool(entry.get("published", false)),
		"rejected": moderation_rejected,
		"under_review": under_review,
		"reject_category": _json_string_or_empty(entry.get("reject_category")),
		"reject_note": _json_string_or_empty(entry.get("reject_note")),
		"appeal_available": bool(entry.get("appeal_available", false)),
	}


## JSON null harus tetap jadi "" bukan literal "&lt;null&gt;" atau semacamnya --
## dipakai untuk field opsional dari my_status (reject_category/reject_note).
func _json_string_or_empty(value: Variant) -> String:
	return "" if value == null else str(value)


func _sync_collection_atlas_preview(row: Dictionary, revision: int) -> void:
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		return
	var account_epoch := GameState.session_epoch
	var res := await Backend.atlas("my_status", {"anima_id": anima_id})
	if not Backend.response_applies(res, account_epoch):
		return
	_collection_view.apply_atlas_status(_gallery_status_from_response(res), row, revision)


func _show_gallery_rejection_info(anima_id: String) -> void:
	if _busy or anima_id.is_empty():
		return
	var info := _details_view.get_gallery_rejection_info()
	var body := _gallery_reject_message(str(info.get("category", "")))
	var note := str(info.get("note", ""))
	if not note.is_empty():
		body += "\n\n" + tr("GALLERY_REJECT_STAFF_NOTE_LABEL") + " " + note
	if bool(info.get("appeal_available", false)):
		_pending_gallery_appeal_id = anima_id
		_modal_context = &"gallery_appeal"
		_shell_modal.open_confirm(
			tr("GALLERY_PUBLISH_REJECTED"),
			body,
			tr("GALLERY_APPEAL_ACTION"),
			tr("ACTION_CANCEL")
		)
	else:
		_modal_context = &"gallery_rejection_info"
		_shell_modal.open_info(
			tr("GALLERY_PUBLISH_REJECTED"),
			body + "\n\n" + tr("GALLERY_APPEAL_ALREADY_USED_INFO"),
			tr("CORE_INFO_CLOSE")
		)


func _gallery_reject_message(category: String) -> String:
	match category:
		"sexual":
			return tr("GALLERY_REJECT_REASON_SEXUAL")
		"gore":
			return tr("GALLERY_REJECT_REASON_GORE")
		"hate":
			return tr("GALLERY_REJECT_REASON_HATE")
		"ip_character":
			return tr("GALLERY_REJECT_REASON_IP_CHARACTER")
		_:
			return tr("GALLERY_REJECT_REASON_GENERIC")


func _commit_gallery_appeal(anima_id: String) -> void:
	_pending_gallery_appeal_id = ""
	if _busy or anima_id.is_empty():
		return
	_details_view.set_gallery_appeal_pending(true)
	_set_busy(true)
	var account_epoch := GameState.session_epoch
	var res := await Backend.atlas("appeal", {"anima_id": anima_id})
	if not Backend.response_applies(res, account_epoch):
		_details_view.set_gallery_appeal_pending(false)
		_set_busy(false)
		return
	if res.ok:
		_say(tr("GALLERY_APPEAL_SUBMITTED"), false)
		await _refresh_gallery_status(anima_id)
	else:
		_say(_gallery_error(res.error), true)
	_details_view.set_gallery_appeal_pending(false)
	_set_busy(false)


func _open_settings() -> void:
	if _busy:
		return
	_seeker_menu_sheet.show_menu(
		GameState.is_anonymous(),
		ChapterPush.available(),
		GameState.chapter_push_enabled(),
		GameState.music_enabled()
	)


func _on_brand_input(event: InputEvent) -> void:
	var is_tap: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		)
	)
	if is_tap and not _busy and not GameState.profile.is_empty():
		_open_seeker_profile()


## Same double-fire as need chips elsewhere: touch emulation hands the finger
## over twice, once as a screen touch and once as a synthetic mouse press. The
## second one is worse than a dead tap here -- it re-enters
## `_show_collection_profile` while Profile is already the destination, which
## resets the remembered origin and loses the Home entry that makes one Back
## land back on Home.
func _on_hud_anima_input(event: InputEvent) -> void:
	var is_tap: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		)
	)
	if not is_tap or _current_anima.is_empty():
		return
	var frame := Engine.get_process_frames()
	if frame == _hud_anima_tapped_frame:
		return
	_hud_anima_tapped_frame = frame
	_show_collection_profile(_current_anima)


func _open_seeker_profile() -> void:
	_remember_overlay_origin()
	_set_busy(true)
	LoadingScreen.show_screen("SEEKER_PROFILE_LOADING")
	var account_epoch := GameState.session_epoch
	var res := await Backend.seeker("profile")
	if not Backend.response_applies(res, account_epoch):
		return
	_set_busy(false)
	if not res.ok:
		_say(tr("SEEKER_PROFILE_ERROR"), true)
		return
	var profile := GameState.as_dict(res.data)
	GameState.profile.merge(profile, true)
	_refresh_header()
	_seeker_profile_view.set_profile(
		profile,
		_thumbnail_for(_current_anima) if not _current_anima.is_empty() else null
	)
	_paint_cached_trophies()
	_switch_destination(SEEKER_PROFILE_DEST)
	await _load_seeker_trophies()


## Daftar Core berubah paling sering sekali per chapter, jadi kunjungan kedua
## tidak boleh menunggu jaringan: nama datang dari boot cache dan art-nya dari
## disk, keduanya terpasang di frame yang sama dengan pindah layar. Kunjungan
## tanpa cache menampilkan skeleton di Trophy Showcase sampai server menjawab.
func _paint_cached_trophies() -> void:
	var cached: Variant = GameState.boot_cache.get("trophies")
	if typeof(cached) != TYPE_ARRAY:
		_seeker_profile_view.set_trophies_loading(true)
		return
	_seeker_profile_view.set_trophies(cached)
	for trophy in SeekerProfileView.trophy_entries(cached):
		var trophy_id := str(trophy.get("id", ""))
		_seeker_profile_view.set_trophy_art(trophy_id, _stored_trophy_art(trophy_id))


func _load_seeker_trophies() -> void:
	var account_epoch := GameState.session_epoch
	var res := await Backend.expedition("trophies")
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok:
		if typeof(GameState.boot_cache.get("trophies")) != TYPE_ARRAY:
			_seeker_profile_view.hide_trophies()
		return
	var rows: Variant = GameState.as_dict(res.data).get("trophies")
	if typeof(rows) != TYPE_ARRAY:
		rows = []
	GameState.remember_boot_cache({"trophies": rows})
	_seeker_profile_view.set_trophies(rows)
	for trophy in SeekerProfileView.trophy_entries(rows):
		var trophy_id := str(trophy.get("id", ""))
		var texture := _stored_trophy_art(trophy_id)
		if texture == null:
			texture = await _download_trophy_art(trophy_id, str(trophy.get("art_url", "")))
		_seeker_profile_view.set_trophy_art(trophy_id, texture)


## Art Core adalah aset chapter publik yang dikunci ke UUID trophy, jadi ia boleh
## bertahan lintas akun di device yang sama dan tidak ikut dibuang bersama cache
## boot milik akun sebelumnya.
func _stored_trophy_art(trophy_id: String) -> Texture2D:
	if _trophy_icon_cache.has(trophy_id):
		return _trophy_icon_cache[trophy_id]
	var path := TROPHY_ART_DIR.path_join("%s.png" % trophy_id)
	if trophy_id.is_empty() or not FileAccess.file_exists(path):
		return null
	return _decode_trophy_art(trophy_id, FileAccess.get_file_as_bytes(path))


func _download_trophy_art(trophy_id: String, art_url: String) -> Texture2D:
	if trophy_id.is_empty() or art_url.is_empty():
		return null
	var account_epoch := GameState.session_epoch
	var download := await Backend.download_url(art_url)
	if not Backend.response_applies(download, account_epoch):
		return null
	if not download.ok:
		return null
	var texture := _decode_trophy_art(trophy_id, download.bytes)
	if texture == null:
		return null
	DirAccess.make_dir_recursive_absolute(TROPHY_ART_DIR)
	var file := FileAccess.open(TROPHY_ART_DIR.path_join("%s.png" % trophy_id), FileAccess.WRITE)
	if file != null:
		file.store_buffer(download.bytes)
		file.close()
	return texture


func _decode_trophy_art(trophy_id: String, bytes: PackedByteArray) -> Texture2D:
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_trophy_icon_cache[trophy_id] = texture
	return texture


func _show_rename_seeker() -> void:
	_modal_context = &"rename_seeker"
	_shell_modal.open_input(
		tr("SEEKER_RENAME_TITLE"),
		tr("SEEKER_RENAME_BODY"),
		(
			str(GameState.profile.get("seeker_name", ""))
			if profile_value_present(GameState.profile, &"seeker_name")
			else ""
		),
		tr("SEEKER_RENAME_SAVE"),
		tr("ACTION_CANCEL"),
		tr("SEEKER_NAME_PLACEHOLDER")
	)


func _rename_seeker(value: String) -> void:
	if not SeekerOnboardingSheet.is_valid_seeker_name(value):
		_say(tr("SEEKER_NAME_INVALID"), true)
		return
	_set_busy(true)
	var account_epoch := GameState.session_epoch
	var res := await Backend.seeker("rename", {"seeker_name": value})
	if not Backend.response_applies(res, account_epoch):
		return
	_set_busy(false)
	if not res.ok:
		_say(
			tr("SEEKER_RENAME_COOLDOWN")
			if res.error == "SEEKER_NAME_COOLDOWN"
			else _seeker_error(res.error),
			true
		)
		return
	GameState.profile.merge(GameState.as_dict(res.data), true)
	_refresh_header()
	_say(tr("SEEKER_RENAME_SUCCESS") % str(GameState.profile.get("seeker_name", "")), true)
	await _open_seeker_profile()


func _show_account_action() -> void:
	_seeker_menu_sheet.close()
	if GameState.is_anonymous():
		_show_sign_in_confirmation()
		return
	if GameState.account_switch_blocked():
		_say(tr("SEEKER_SWITCH_BLOCKED"), true)
		return
	_modal_context = &"sign_out"
	_shell_modal.open_confirm(
		tr("SEEKER_SIGN_OUT_TITLE"),
		tr("SEEKER_SIGN_OUT_BODY"),
		tr("SEEKER_SIGN_OUT"),
		tr("ACTION_CANCEL")
	)


func _show_sign_in_confirmation() -> void:
	if _busy:
		_say(tr("SEEKER_SWITCH_BLOCKED"), true)
		return
	if not GameState.is_anonymous():
		_show_account_action()
		return
	if GameState.account_switch_blocked(true):
		_say(tr("SEEKER_SWITCH_BLOCKED"), true)
		return
	# Keep Guest Separate tidak menghapus apa pun, tapi ia meninggalkan seluruh Anima
	# guest di akun yang tidak lagi terlihat — dan guest hanya pernah punya satu Scan,
	# jadi yang ditinggalkan itu satu-satunya. Saat ada yang dipertaruhkan, Move yang
	# berdiri di slot utama dan copy-nya menyebut apa yang tertinggal plus jalan pulang.
	# Roster yang gagal dimuat tidak boleh membungkam peringatan itu, jadi
	# `guest_scan_used_at` ikut dibaca sebagai bukti kedua bahwa guest pernah punya
	# Anima; salah memperingatkan jauh lebih murah daripada diam.
	_sign_in_move_first = not _roster.is_empty() or _guest_scan_locked()
	var move_label := tr("SEEKER_MOVE_GUEST_PROGRESS")
	var separate_label := tr("SEEKER_KEEP_GUEST_SEPARATE")
	var body := (
		tr("SEEKER_SIGN_IN_CHOICE_BODY_ANIMA") if _sign_in_move_first
		else tr("SEEKER_SIGN_IN_CHOICE_BODY")
	)
	_modal_context = &"sign_in_google"
	_shell_modal.open_choice(
		tr("SEEKER_SIGN_IN_TITLE"),
		body,
		move_label if _sign_in_move_first else separate_label,
		separate_label if _sign_in_move_first else move_label,
		tr("ACTION_CANCEL")
	)


## Slot utama menampung Move saat guest punya Anima, Keep Separate saat tidak.
## Dipisah supaya urutan tombol dan aksi yang dijalankan tidak bisa hanyut
## sendiri-sendiri: membaliknya berarti Keep Separate diam-diam mentransfer akun.
static func sign_in_choice_moves_guest(choice: String, move_first: bool) -> bool:
	return (choice == "primary") == move_first


func _show_transfer_confirmation() -> void:
	_modal_context = &"confirm_transfer_guest"
	_shell_modal.open_confirm(
		tr("SEEKER_MOVE_CONFIRM_TITLE"),
		tr("SEEKER_MOVE_CONFIRM_BODY"),
		tr("SEEKER_MOVE_GUEST_PROGRESS"),
		tr("ACTION_CANCEL"),
		true
	)


func _start_google_separate() -> void:
	var res := await AuthFlow.start_google_separate()
	if not bool(res.get("ok", false)):
		_say(_account_switch_error(str(res.get("error", ""))), true)


func _start_google_transfer() -> void:
	var res := await AuthFlow.start_google_transfer()
	if not bool(res.get("ok", false)):
		_say(_account_switch_error(str(res.get("error", ""))), true)


func _start_google_link() -> void:
	_start_google_transfer()


func _show_existing_account_warning() -> void:
	_modal_context = &"restore_google"
	_shell_modal.open_confirm(
		tr("SEEKER_RESTORE_TITLE"),
		tr("SEEKER_RESTORE_WARNING"),
		tr("SEEKER_RESTORE_ACTION"),
		tr("ACTION_CANCEL")
	)


func _start_google_restore() -> void:
	_start_google_separate()


func _sign_out() -> void:
	_set_busy(true)
	var res := await AuthFlow.sign_out_to_guest()
	if not bool(res.get("ok", false)):
		_set_busy(false)
		_say(_account_switch_error(str(res.get("error", ""))), true)


func _account_switch_error(error: String) -> String:
	if error == "ACCOUNT_SWITCH_BLOCKED":
		return tr("SEEKER_SWITCH_BLOCKED")
	if error in [
		"DEVICE_GUEST_MISSING", "DEVICE_GUEST_NOT_ANONYMOUS",
		"DEVICE_GUEST_SAVE_FAILED", "DEVICE_GUEST_ACTIVATE_FAILED",
		"DEVICE_GUEST_RECOVERY_FAILED",
	]:
		return tr("SEEKER_GUEST_RECOVERY_ERROR")
	return tr("SEEKER_AUTH_ERROR")


func _on_auth_succeeded(mode: String, profile: Dictionary) -> void:
	var account_epoch := GameState.session_epoch
	if _booting:
		_boot_auth_success_mode = mode
		return
	_set_busy(true)
	_reset_account_presentation()
	_switch_destination(BottomNav.HOME)
	if not profile.is_empty():
		GameState.profile.merge(profile, true)
	else:
		var profile_res := await Backend.fetch_profile()
		if not Backend.response_applies(profile_res, account_epoch):
			return
		_apply_profile_refresh(profile_res)
	await _refresh_catalog()
	if GameState.session_epoch != account_epoch:
		return
	var loaded := await _reload_roster()
	if GameState.session_epoch != account_epoch:
		return
	_refresh_header()
	if loaded and not _roster.is_empty():
		var active := _active_row()
		await _present_row(active if not active.is_empty() else _roster[0])
	elif loaded:
		_current_anima = {}
		_set_home_shell_state(&"empty")
	_set_busy(false)
	_say(tr(_account_success_key(mode)), true)
	_resume_pending_publish()
	call_deferred("_maybe_prompt_seeker_onboarding")
	call_deferred("_refresh_chapter_announcements")


## Guest yang menekan Publish dikirim ke sign-in, jadi intent-nya harus selamat
## melewati round trip OAuth. Intent dikonsumsi **sebelum** pagarnya diperiksa —
## pola `pull` yang sama dipakai redirect pasca-login — supaya tidak ada jalur
## yang menyisakannya terkokang untuk sign-in berikutnya. UID pembuatnya dibawa
## serta alih-alih disimpulkan dari roster: transfer justru *didefinisikan*
## sebagai UID yang tidak berubah (`auth_flow` membatalkan pertukaran token kalau
## berbeda), jadi kecocokan UID menyatakan langsung "pemiliknya masih orang yang
## sama" dan `separate` gagal karena konstruksi, bukan karena kebetulan urutan
## muat roster. Ini kenyamanan UI; yang berwenang tetap `ANIMA_NOT_OWNED` di server.
func _resume_pending_publish() -> void:
	var intent := _publish_after_sign_in
	_publish_after_sign_in = {}
	if intent.is_empty() or GameState.is_anonymous():
		return
	if str(intent.get("uid", "")) != GameState.uid():
		return
	var anima_id := str(intent.get("anima_id", ""))
	var row := _roster_row(anima_id)
	if anima_id.is_empty() or row.is_empty():
		return
	_switch_destination(ANIMA_PROFILE_DEST, row)
	_toggle_gallery_publish(anima_id, true)


static func _account_success_key(mode: String) -> String:
	if mode == "separate":
		return "SEEKER_SIGNED_IN"
	if mode == "transfer":
		return "SEEKER_MOVED"
	return "SEEKER_SIGNED_OUT"


func _reset_account_presentation() -> void:
	_roster.clear()
	_catalog.clear()
	_catalog_synced = false
	_inventory.clear()
	_current_anima = {}
	_profile_anima = {}
	_roster_error = ""
	_thumbnail_cache.clear()
	_synthesis_history_texture_cache.clear()
	_outcome_dialog_queue.clear()
	_expedition_level_queue.clear()
	_expedition_level_sequence_active = false
	if not _active_outcome_dialog.is_empty() and is_instance_valid(_shell_modal):
		_shell_modal.close()
		_modal_context = &""
	_active_outcome_dialog = {}
	_team_battle_team = {}
	_team_battle_candidates.clear()
	_team_battle_daily = {}
	_team_defense_published = false
	_team_art_cache.clear()
	_synthesis_resume_in_flight = false
	_synthesis_poll_in_flight = false
	_battle_turn_in_flight = false
	_team_turn_in_flight = false
	if is_instance_valid(_expedition_controller):
		_expedition_controller.reset_account_context()
	if is_instance_valid(_atlas_view):
		_atlas_view.reset_account_context()
	_synthesis_history_revision += 1
	_evolution_history_revision += 1
	_chapter_announcement_revision += 1
	_gallery_status_revision += 1
	_chapter_announcement_revision += 1
	_anima.sprite_frames = null
	_anima.visible = false
	_battle_view.show_duel_mode()
	_battle_view.set_lobby({})
	_set_home_shell_state(&"loading")
	_populate_collection()
	_refresh_header()
	_sync_shop_chrome()


func _on_auth_failed(error: String) -> void:
	print("oauth error: %s" % error)
	_say(
		tr("SEEKER_UPGRADE_PENDING")
		if error == "OAUTH_UPGRADE_PENDING"
		else _account_switch_error(error),
		true
	)


func _show_delete_account_confirmation() -> void:
	_seeker_menu_sheet.close()
	if GameState.account_switch_blocked():
		_say(tr("SEEKER_SWITCH_BLOCKED"), true)
		return
	_modal_context = &"delete_account"
	_shell_modal.open_confirm(
		tr("ACCOUNT_DELETE_TITLE"),
		tr("ACCOUNT_DELETE_WARNING"),
		tr("ACCOUNT_DELETE_ACTION"),
		tr("ACTION_CANCEL"),
		true
	)


func _delete_account() -> void:
	if GameState.account_switch_blocked():
		_say(tr("SEEKER_SWITCH_BLOCKED"), true)
		return
	_set_busy(true)
	var preserve_guest := not GameState.is_anonymous() and GameState.device_guest_expected
	var guest: Dictionary = {}
	if preserve_guest:
		var prepared := await AuthFlow.prepare_device_guest()
		if not bool(prepared.get("ok", false)):
			_set_busy(false)
			_say(tr("SEEKER_GUEST_RECOVERY_ERROR"), true)
			return
		guest = GameState.as_dict(prepared.get("session"))
	var res := await Backend.seeker("delete_account", {"confirmation": "DELETE"})
	if not res.ok:
		_set_busy(false)
		_say(tr("ACCOUNT_DELETE_ERROR"), true)
		return
	if preserve_guest:
		if guest.is_empty() or not GameState.activate_stored_session(guest):
			GameState.clear_account_state(false)
			_reset_account_presentation()
			_set_busy(false)
			_say(tr("SEEKER_GUEST_RECOVERY_ERROR"), true)
			return
		GameState.discard_guest_local_state()
	else:
		GameState.clear_account_state(true)
		var signed_in := await Backend.sign_in_anonymous()
		if not bool(signed_in.get("ok", false)):
			_reset_account_presentation()
			_set_busy(false)
			_say(tr("STATUS_ACCOUNT_ERROR"), true)
			return
	await _on_auth_succeeded("guest", {})


func _show_seeker_help() -> void:
	_seeker_menu_sheet.close()
	_modal_context = &"seeker_help"
	_shell_modal.open_info(
		tr("SEEKER_HELP_TITLE"),
		tr("SEEKER_HELP_BODY"),
		tr("CORE_INFO_CLOSE")
	)


func _set_music_enabled(enabled: bool) -> void:
	GameState.set_music_enabled(enabled)
	if is_instance_valid(_music):
		_music.set_enabled(enabled)


func _set_chapter_push(enabled: bool) -> void:
	_chapter_push.set_enabled(enabled)


func _on_chapter_push_enabled(enabled: bool) -> void:
	GameState.set_chapter_push_enabled(enabled)
	_say(tr("CHAPTER_PUSH_ENABLED") if enabled else tr("CHAPTER_PUSH_DISABLED"), true)


func _on_chapter_push_failed() -> void:
	GameState.set_chapter_push_enabled(false)
	_say(tr("CHAPTER_PUSH_ERROR"), true)


func _seeker_error(error: String) -> String:
	match error:
		"SEEKER_NAME_TAKEN":
			return tr("SEEKER_NAME_TAKEN")
		"SEEKER_NAME_RESERVED":
			return tr("SEEKER_NAME_RESERVED")
		"INVALID_BIRTH_YEAR":
			return tr("SEEKER_BIRTH_YEAR_INVALID")
		_:
			return tr("SEEKER_NAME_INVALID")


func _present_row(row: Dictionary) -> void:
	await _present(
		str(row.get("id", "")),
		str(row.get("species_key", "")),
		str(row.get("color_bucket", "")),
		int(row.get("stage", 1)),
		str(row.get("sheet_path", "")),
		GameState.as_dict(row.get("manifest")),
		str(row.get("nickname", "")),
		row,
		false
	)


func _on_care_blocked(message: String) -> void:
	_say(message, true)


func _perform_care(action: String) -> void:
	if _busy or _current_anima.is_empty():
		return
	if CareRules.is_evolving(_current_anima):
		_say(tr("EVOLUTION_CARE_BLOCKED"), true)
		return
	if not GameState.pending_care.is_empty():
		_say(tr("ERROR_CARE_PENDING"), true)
		return
	if action == "feed":
		_open_feed_picker()
		return
	await _commit_care(action)


## Care Dock sengaja tidak diredupkan selama request: pemain sudah melihat
## hop-nya dan meternya bergerak, jadi tombol yang mati sesudahnya hanya terbaca
## sebagai loading. Yang menjaga jalur uang tetap satu adalah `pending_care` —
## dan pemeriksaannya duduk di sini, bukan di pemanggil, sebab Bag memanggil
## `_commit_care` langsung tanpa lewat Care Dock.
##
## `on_react`, kalau diisi, menggantikan `care_feedback()` langsung -- dipakai
## Bag supaya reaksi (bob/kilau/burst) menunggu ikon MENDARAT di tubuh Anima,
## bukan tampil di frame yang sama dengan sheet mulai menutup. Guard di atas
## tetap jalan lebih dulu, jadi aksi yang ditolak tidak menerbangkan apa pun.
func _commit_care(action: String, item_id: String = "", on_react: Callable = Callable()) -> void:
	var account_epoch := GameState.session_epoch
	var anima_id := str(_current_anima.get("id", ""))
	if anima_id.is_empty():
		return
	if CareRules.is_evolving(_current_anima):
		_say(tr("EVOLUTION_CARE_BLOCKED"), true)
		return
	if (action == "feed" or action == "use_item") and _is_sleeping(_current_anima):
		_say(tr("ERROR_SLEEPING_CONSUME"), true)
		return
	# Care Dock sudah menolak ini sebelum sheet-nya kebuka (home_view.gd
	# _request_feed), tapi Bag dibuka lewat BagButton juga tanpa lewat Care
	# Dock -- pagarnya harus di sini juga supaya kedua jalur benar-benar
	# tertutup, bukan cuma salah satunya. Tanpa ini animasi terbang tetap
	# main walau server menolak dan quantity tidak berkurang.
	if action == "feed" and CareRules.need_is_full(_current_anima.get("care"), "hunger"):
		_say(tr("ERROR_NEED_FULL"), true)
		return
	if action == "use_item" and CareRules.need_is_full(_current_anima.get("care"), "energy"):
		_say(tr("ERROR_NEED_FULL"), true)
		return
	if not GameState.pending_care.is_empty():
		_say(tr("ERROR_CARE_PENDING"), true)
		return
	var pending := GameState.begin_care(anima_id, action, item_id)
	if on_react.is_valid():
		on_react.call()
	else:
		_anima.care_feedback("item" if action == "use_item" else action)
	var care_before: Variant = _current_anima.get("care")
	_apply_optimistic_care(action, item_id)
	var committed := await _send_pending_care(pending, true)
	if GameState.session_epoch != account_epoch:
		return
	if not committed and care_before != null:
		_current_anima["care"] = care_before
		_refresh_care()


## Meter sesudah satu aksi care, dihitung dari aturan decay yang sama dengan
## Collection dan nilai efek katalog yang sudah dipegang client. Kosong berarti
## aksi itu tidak menggerakkan meter, jadi tidak ada yang dicat.
static func optimistic_care(
	row: Dictionary, active_id: String, action: String, item_id: String, catalog: Array
) -> Dictionary:
	if typeof(row.get("care")) != TYPE_DICTIONARY:
		return {}
	var care := CareRules.projected_care(row, active_id)
	match action:
		"clean":
			care["hygiene"] = minf(100.0, float(care["hygiene"]) + CareRules.CARE_RESTORE)
		"play":
			care["energy"] = maxf(0.0, float(care["energy"]) - CareRules.PLAY_ENERGY_COST)
		"feed", "use_item":
			var need := "hunger" if action == "feed" else "energy"
			var item: Dictionary = BattleSim.index_catalog(catalog).get(item_id, {})
			var restore := float(item.get("effect_value", 0.0))
			if restore <= 0.0:
				return {}
			care[need] = minf(100.0, float(care[need]) + restore)
		_:
			return {}
	return care


## Menggerakkan meter di frame yang sama dengan tap. Server tetap otoritas: row
## dari `care_anima` menimpa angka ini beberapa ratus milidetik kemudian, dan
## `_commit_care` mengembalikannya kalau aksinya ditolak.
func _apply_optimistic_care(action: String, item_id: String) -> void:
	var care := optimistic_care(
		_current_anima,
		str(GameState.profile.get("active_anima_id", "")),
		action,
		item_id,
		_catalog
	)
	if care.is_empty():
		return
	_current_anima["care"] = care
	_refresh_care()


func _resume_pending_care() -> void:
	var pending := GameState.pending_care.duplicate(true)
	if pending.is_empty():
		return
	await _send_pending_care(pending, false)


func _send_pending_care(pending: Dictionary, show_feedback: bool) -> bool:
	var account_epoch := GameState.session_epoch
	var action := str(pending.get("action", ""))
	var res := await Backend.care_anima(
		str(pending.get("anima_id", "")),
		action,
		str(pending.get("idempotency_key", "")),
		str(pending.get("item_id", ""))
	)
	if not Backend.response_applies(res, account_epoch):
		return false
	if res.ok:
		GameState.finish_care()
		if _apply_care_response(GameState.as_dict(res.data)):
			if action == "feed" or action == "use_item":
				_refresh_inventory()
			if show_feedback and not _shell_modal.visible:
				_say(_care_success_message(action), show_feedback)
			return true
		return false

	# Galat 4xx adalah keputusan server, bukan gangguan sementara. Menyimpan key
	# selamanya akan mengunci semua tombol care walau saldo/kondisinya berubah.
	if res.code >= 400 and res.code < 500:
		GameState.finish_care()
	_say(_care_error_message(res.error))
	return false


func _sync_active_care(show_error: bool) -> void:
	var account_epoch := GameState.session_epoch
	var anima_id := str(_current_anima.get("id", ""))
	if anima_id.is_empty():
		return
	var res := await Backend.care_anima(anima_id, "sync")
	if not Backend.response_applies(res, account_epoch):
		return
	if res.ok:
		_apply_care_response(GameState.as_dict(res.data))
	elif show_error:
		print("care sync error: %s" % res.error)
		_say(tr("ERROR_CARE_SYNC"), true)


func _summon_current_anima() -> void:
	var anima_id := str(_current_anima.get("id", ""))
	if anima_id.is_empty() or not GameState.pending_care.is_empty():
		await _sync_active_care(false)
		return
	var pending := GameState.begin_care(anima_id, "summon")
	if not await _send_pending_care(pending, false):
		await _sync_active_care(false)


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
	if data.has("active_anima_id"):
		GameState.profile["active_anima_id"] = str(data.get("active_anima_id", ""))
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
		"use_item":
			return tr("FEEDBACK_ENERGY_ITEM")
		"clean":
			return tr("FEEDBACK_CLEAN")
		"play":
			return tr("FEEDBACK_PLAY") if _last_care_delta > 0 else tr("FEEDBACK_PLAY_CAPPED")
		"sleep":
			return tr("FEEDBACK_SLEEP")
		"wake":
			return tr("FEEDBACK_WAKE")
		"summon":
			return tr("COLLECTION_SUMMON_SUCCESS") % LocaleManager.display_name(_current_anima)
		_:
			return tr("FEEDBACK_SYNCED")


func _care_error_message(error: String) -> String:
	match error:
		"NO_BITS":
			return tr("ERROR_NO_BITS")
		"NO_ITEM":
			return tr("ERROR_NO_ITEM")
		"INVALID_ITEM":
			return tr("ERROR_INVALID_ITEM")
		"PRICE_CHANGED":
			return tr("ERROR_PRICE_CHANGED")
		"STACK_FULL":
			return tr("ERROR_STACK_FULL")
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
	var account_epoch := GameState.session_epoch
	var session_before: Dictionary = _battle_view.session_data()
	var session_id := str(session_before.get("id", ""))
	var session_version := int(session_before.get("version", 0))
	var payload := {}
	if not session_id.is_empty():
		payload["session_id"] = session_id
	var res := await Backend.battle_anima("status", payload)
	if not Backend.response_applies(res, account_epoch):
		return
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
	LoadingScreen.show_screen("BATTLE_CONNECTING")
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
		_sync_shop_chrome()
		return

	_set_busy(true)
	_battle_view.set_loading("BATTLE_RESUMING")
	LoadingScreen.show_screen("BATTLE_RESUMING")
	var res := await Backend.battle_anima("resume", {"session_id": session_id})
	if not res.ok and res.error == "BATTLE_NOT_FOUND":
		GameState.finish_battle()
		_battle_view.set_lobby(_current_anima)
		_sync_shop_chrome()
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


## Result terminal butuh jalan keluar eksplisit. Tanpa ini session mati tetap
## terpasang di arena dan tap berikutnya mengirim turn yang sudah lewat.
func _leave_battle() -> void:
	if _busy:
		return
	_battle_view.set_lobby(_current_anima)
	_refresh_battle_reward_status()


func _battle_action_requested(action: String) -> void:
	if _busy:
		# begin_action sudah mengunci tombol; tanpa request itu membeku.
		_battle_view.set_busy(false)
		return
	var session: Dictionary = _battle_view.session_data()
	if session.is_empty() or str(session.get("status", "")) != "active":
		_battle_view.set_busy(false)
		return
	var pending := GameState.begin_battle_action(
		str(session.get("id", "")),
		int(session.get("turn_number", 1)),
		int(session.get("version", 1)),
		action
	)
	await _submit_pending_battle(pending)


## Simulasi turn dari state authoritative yang sudah ada di client. Kosong kalau
## state-nya belum lengkap atau aksinya ditolak aturan; pemanggil lalu jatuh ke
## jalur lama dan menunggu server.
func _predict_battle_turn(session: Dictionary, pending: Dictionary) -> Dictionary:
	var state := GameState.as_dict(session.get("state"))
	if state.is_empty() or str(state.get("status", "")) != "active":
		return {}
	if int(state.get("turn", 0)) != int(pending.get("expected_turn", -1)):
		return {}
	var outcome := BattleSim.resolve_turn(
		state,
		str(pending.get("action", "")),
		str(pending.get("idempotency_key", "")),
		str(pending.get("item_id", "")),
		BattleSim.index_catalog(_catalog)
	)
	if not bool(outcome.get("ok", false)):
		return {}
	var next_state: Dictionary = outcome["state"]
	var predicted := session.duplicate(true)
	predicted["state"] = next_state
	predicted["turn_number"] = int(next_state.get("turn", session.get("turn_number", 1)))
	predicted["status"] = str(next_state.get("status", "active"))
	return {"session": predicted, "events": outcome["events"]}


## Ringkasan turn seperti yang dilihat pemain: status, nomor turn, HP/PP petarung
## Duel, lalu log-nya lewat `BattleEvent.log_digest()`. Dipakai Duel maupun Team
## untuk membandingkan hasil server dengan animasi yang sudah terlanjur jalan;
## state Team menyimpan HP di dalam roster, jadi event-nya yang membawa angka itu.
func _turn_outcome_digest(state: Dictionary, events: Array) -> String:
	var player := GameState.as_dict(state.get("player"))
	var bot := GameState.as_dict(state.get("bot"))
	return "|".join(PackedStringArray([
		str(state.get("status", "")),
		str(int(float(state.get("turn", 0)))),
		str(int(float(player.get("hp", 0)))),
		str(int(float(bot.get("hp", 0)))),
		str(int(float(player.get("momentum", 0)))),
		str(int(float(bot.get("momentum", 0)))),
		BATTLE_EVENT.log_digest(events),
	]))


func _turn_outcome_matches(
	predicted: Dictionary, next_session: Dictionary, events: Array
) -> bool:
	if predicted.is_empty():
		return false
	var predicted_session: Dictionary = predicted["session"]
	return (
		_turn_outcome_digest(GameState.as_dict(predicted_session.get("state")), predicted["events"])
		== _turn_outcome_digest(GameState.as_dict(next_session.get("state")), events)
	)


func _dispatch_battle_turn(payload: Dictionary) -> void:
	_battle_turn_in_flight = true
	_battle_turn_result = await Backend.battle_anima("turn", payload)
	_battle_turn_in_flight = false
	_battle_turn_settled.emit()


func _await_battle_turn() -> Dictionary:
	if _battle_turn_in_flight:
		await _battle_turn_settled
	return _battle_turn_result


func _submit_pending_battle(pending: Dictionary) -> void:
	var account_epoch := GameState.session_epoch
	if pending.is_empty():
		return
	_battle_reward_revision += 1
	_battle_view.begin_action(str(pending.get("action", "")))
	_set_busy(true)
	var payload := {
		"session_id": str(pending.get("session_id", "")),
		"expected_turn": int(pending.get("expected_turn", 1)),
		"expected_version": int(pending.get("expected_version", 1)),
		"action": str(pending.get("action", "")),
		"idempotency_key": str(pending.get("idempotency_key", "")),
	}
	var item_id := str(pending.get("item_id", ""))
	if str(pending.get("action", "")) == "item" and not item_id.is_empty():
		payload["item_id"] = item_id

	# Animasi jalan dari hasil simulasi lokal sementara request-nya terbang.
	# Server tetap otoritas: state, reward, dan version-nya yang dipakai begitu
	# response tiba, dan turn yang sama dihitung ulang di sana.
	var session_before: Dictionary = _battle_view.session_data()
	var predicted := _predict_battle_turn(session_before, pending)
	_dispatch_battle_turn(payload)
	if not predicted.is_empty():
		await _battle_view.play_events(predicted["events"], predicted["session"])
		# play_events melepas tombolnya sendiri. Turn berikutnya baru boleh dikirim
		# setelah server memberi version-nya, jadi redupkan lagi kalau masih terbang.
		_battle_view.set_busy(_battle_turn_in_flight)
	var res := await _await_battle_turn()
	if not Backend.response_applies(res, account_epoch):
		return

	if not res.ok:
		# Turn yang tidak sampai ke server tidak boleh meninggalkan arena di masa
		# depan: tap berikutnya akan mengirim nomor turn yang belum pernah ada.
		if not predicted.is_empty() and not session_before.is_empty():
			_battle_view.set_session(session_before)
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
	next_session["last_reward"] = GameState.as_dict(data.get("reward"))
	var events: Array = data.get("events", []) if typeof(data.get("events")) == TYPE_ARRAY else []
	if next_session.is_empty():
		_battle_view.set_error("BATTLE_NOT_FOUND")
		_set_busy(false)
		return
	if _turn_outcome_matches(predicted, next_session, events):
		# Animasinya sudah jalan dari simulasi lokal; ini tinggal memasang row
		# authoritative supaya version/reward-nya yang dipakai turn berikutnya.
		# `_set_busy(false)` di bawah yang melepas tombolnya.
		_battle_view.set_session(next_session)
	else:
		await _battle_view.play_events(events, next_session)
	GameState.confirm_battle_response(next_session)
	# Katalog/profil boleh menyusul. Menahan _busy di sini membuat tap Special
	# berikutnya menampilkan Resolving tanpa pernah mengirim turn.
	_set_busy(false)
	if str(pending.get("action", "")) == "item":
		_refresh_inventory()
	await _apply_battle_reward(GameState.as_dict(data.get("reward")), next_session)


func _confirm_expedition_abandon() -> void:
	if _busy or (is_instance_valid(_shell_modal) and _shell_modal.visible):
		return
	_modal_context = &"expedition_abandon"
	_shell_modal.open_confirm(
		tr("EXPEDITION_ABANDON_TITLE"),
		tr("EXPEDITION_ABANDON_CONFIRM"),
		tr("EXPEDITION_ABANDON_ACTION"),
		tr("ACTION_CANCEL"),
		true
	)


func _confirm_retreat(kind: String) -> void:
	if _busy or (is_instance_valid(_shell_modal) and _shell_modal.visible):
		return
	_pending_retreat = kind
	_modal_context = &"retreat"
	_shell_modal.open_confirm(
		tr("BATTLE_RETREAT_TITLE"),
		tr(
			"BATTLE_RETREAT_CONFIRM_EXPEDITION"
			if kind == "expedition"
			else "BATTLE_RETREAT_CONFIRM"
		),
		tr("BATTLE_FORFEIT"),
		tr("ACTION_CANCEL"),
		true
	)


func _retreat_confirmed() -> void:
	var kind := _pending_retreat
	_pending_retreat = ""
	match kind:
		"duel":
			_forfeit_battle()
		"team":
			_forfeit_team_battle()
		"expedition":
			if is_instance_valid(_expedition_controller):
				_expedition_controller.forfeit()


func _forfeit_battle() -> void:
	if _busy:
		return
	_battle_reward_revision += 1
	var session: Dictionary = _battle_view.session_data()
	var session_id := str(session.get("id", GameState.pending_battle.get("session_id", "")))
	if session_id.is_empty():
		return
	_battle_view.show_retreat_banner()
	_set_busy(true)
	var res := await Backend.battle_anima("forfeit", {"session_id": session_id})
	if res.ok:
		var closed := GameState.as_dict(res.data)
		GameState.finish_battle()
		_battle_view.set_session(closed)
		_sync_shop_chrome()
	else:
		_battle_view.set_error(res.error)
	_set_busy(false)


# ---------------------------------------------------------------- Team Battle

func _apply_cached_mode_availability() -> void:
	_battle_view.set_team_available(GameState.team_battle_available())
	_battle_view.set_expedition_available(GameState.expedition_available())
	_battle_view.set_duel_pending(not GameState.pending_battle.is_empty())
	_battle_view.set_team_pending(not GameState.pending_team_battle.is_empty())
	_battle_view.set_expedition_pending(not GameState.pending_expedition.is_empty())


func _discover_team_battle() -> void:
	var account_epoch := GameState.session_epoch
	var res := await Backend.team_battle("status")
	if not Backend.response_applies(res, account_epoch):
		return
	if res.ok:
		GameState.set_team_battle_available(true)
		_battle_view.set_team_available(true)
		return
	if str(res.error) == "FEATURE_DISABLED":
		GameState.set_team_battle_available(false)
		_battle_view.set_team_available(false)


func _open_team_battle_mode() -> void:
	if _busy:
		return
	_battle_view.show_team_mode()
	if not GameState.pending_team_battle.is_empty():
		await _resume_team_battle()
		return
	await _load_team_battle_hub()


func _close_team_battle_mode() -> void:
	if _busy:
		return
	_battle_view.show_duel_mode()
	if not _battle_view.is_team_mode():
		_battle_view.set_lobby(_current_anima)
		_refresh_battle_reward_status()


func _load_team_battle_hub() -> void:
	var account_epoch := GameState.session_epoch
	_set_busy(true)
	_team_battle_view.set_loading()
	var res := await Backend.team_battle("teams")
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok:
		_team_battle_view.set_error(res.error)
		_set_busy(false)
		return
	var data := GameState.as_dict(res.data)
	var teams := _variant_array(data.get("teams"))
	_team_battle_team = _team_of_kind(teams, "team_battle")
	var defense := _team_of_kind(teams, "defense")
	_team_defense_published = bool(defense.get("published", false))
	# Team ownership begins in the builder: even a saved roster must be reviewed
	# before the first rival request, so stale/partial teams can be repaired.
	_team_battle_view.set_builder(_roster, _team_battle_team)
	_set_busy(false)


func _save_team_battle_roster(anima_ids: Array[String]) -> void:
	var account_epoch := GameState.session_epoch
	if (
		_busy
		or anima_ids.size() < TeamBattleView.MIN_TEAM_SIZE
		or anima_ids.size() > TeamBattleView.MAX_TEAM_SIZE
	):
		return
	_set_busy(true)
	_team_battle_view.set_loading("TEAM_SAVING")
	var res := await Backend.team_battle("save_team", {
		"kind": "team_battle",
		"anima_ids": anima_ids,
	})
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok:
		_team_battle_view.set_error(res.error)
		_set_busy(false)
		return
	_team_battle_team = GameState.as_dict(GameState.as_dict(res.data).get("team"))
	_set_busy(false)
	await _refresh_team_battle_candidates(str(_team_battle_team.get("id", "")))


func _set_team_defense(publish: bool, anima_ids: Array[String]) -> void:
	if (
		_busy
		or anima_ids.size() < TeamBattleView.MIN_TEAM_SIZE
		or anima_ids.size() > TeamBattleView.MAX_TEAM_SIZE
	):
		return
	_set_busy(true)
	if publish:
		_team_battle_view.set_loading("TEAM_PUBLISHING_DEFENSE")
	else:
		_team_battle_view.set_loading("TEAM_UNPUBLISHING_DEFENSE")
	var account_epoch := GameState.session_epoch
	if publish:
		var saved := await Backend.team_battle("save_team", {
			"kind": "defense",
			"anima_ids": anima_ids,
		})
		if not Backend.response_applies(saved, account_epoch):
			return
		if not saved.ok:
			_team_battle_view.set_error(saved.error)
			_set_busy(false)
			return
	var res := await Backend.team_battle("publish_defense", {"publish": publish})
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok:
		_team_battle_view.set_error(res.error)
		_set_busy(false)
		return
	_team_defense_published = publish
	_team_battle_view.set_lobby(
		_team_battle_team,
		_team_battle_daily,
		_team_battle_candidates,
		_team_defense_published
	)
	_set_busy(false)


func _refresh_team_battle_candidates(team_id: String = "") -> void:
	if _busy:
		return
	if team_id.is_empty():
		team_id = str(_team_battle_team.get("id", ""))
	if team_id.is_empty():
		_team_battle_view.set_builder(_roster, _team_battle_team)
		return
	_set_busy(true)
	_team_battle_view.set_loading("TEAM_FINDING_RIVALS")
	var account_epoch := GameState.session_epoch
	var status_res := await Backend.team_battle("status")
	if not Backend.response_applies(status_res, account_epoch):
		return
	_team_battle_daily = (
		GameState.as_dict(status_res.data) if status_res.ok else {}
	)
	var res := await Backend.team_battle("candidates", {"team_id": team_id})
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok:
		_team_battle_view.set_error(res.error)
		_set_busy(false)
		return
	var data := GameState.as_dict(res.data)
	var returned_team := GameState.as_dict(data.get("team"))
	if not returned_team.is_empty():
		_team_battle_team = returned_team
	_team_battle_candidates = _variant_array(data.get("candidates"))
	_team_battle_view.set_lobby(
		_team_battle_team,
		_team_battle_daily,
		_team_battle_candidates,
		_team_defense_published
	)
	_set_busy(false)


func _start_team_battle(team_id: String, candidate_id: String) -> void:
	if _busy or team_id.is_empty() or candidate_id.is_empty():
		return
	_set_busy(true)
	_team_battle_view.set_loading("TEAM_STARTING")
	LoadingScreen.show_screen("TEAM_STARTING")
	var res := await Backend.team_battle("start", {
		"team_id": team_id,
		"candidate_id": candidate_id,
	})
	if not res.ok:
		_team_battle_view.set_error(res.error)
		_set_busy(false)
		return
	var session := GameState.as_dict(res.data)
	if session.is_empty():
		_team_battle_view.set_error("TEAM_BATTLE_NOT_FOUND")
		_set_busy(false)
		return
	GameState.remember_team_battle(
		str(session.get("id", "")),
		int(session.get("turn_number", 1)),
		int(session.get("version", 1))
	)
	_team_art_cache = {}
	await _show_team_battle_session(session)
	await _reload_roster()
	_set_busy(false)


func _resume_team_battle() -> void:
	if _busy:
		return
	var pending := GameState.pending_team_battle.duplicate(true)
	var session_id := str(pending.get("session_id", ""))
	if session_id.is_empty():
		await _load_team_battle_hub()
		return
	_set_busy(true)
	_team_battle_view.set_loading("TEAM_RESUMING")
	LoadingScreen.show_screen("TEAM_RESUMING")
	var res := await Backend.team_battle("resume", {"session_id": session_id})
	if not res.ok and res.error in ["TEAM_BATTLE_NOT_FOUND", "INVALID_SESSION_ID"]:
		GameState.finish_team_battle()
		_set_busy(false)
		await _load_team_battle_hub()
		return
	if not res.ok:
		_team_battle_view.set_error(res.error)
		_set_busy(false)
		return
	var session := GameState.as_dict(res.data)
	if not await _show_team_battle_session(session):
		_set_busy(false)
		return
	var should_replay := (
		not str(pending.get("action", "")).is_empty()
		and str(session.get("status", "")) == "active"
		and int(session.get("turn_number", 0)) == int(pending.get("expected_turn", -1))
		and int(session.get("version", 0)) == int(pending.get("expected_version", -1))
	)
	if should_replay:
		_set_busy(false)
		await _submit_pending_team_battle(pending)
	else:
		GameState.confirm_team_battle_response(session)
		if str(session.get("status", "")) != "active":
			await _refresh_team_battle_authority()
		_set_busy(false)


func _retry_team_battle() -> void:
	if GameState.pending_team_battle.is_empty():
		_team_battle_view.set_builder(_roster, _team_battle_team)
	else:
		await _resume_team_battle()


func _team_battle_action_requested(action: String, switch_to_slot: int) -> void:
	if _busy or _team_battle_demo_active:
		_team_battle_view.set_busy(false)
		return
	var session := _team_battle_view.session_data()
	if session.is_empty() or str(session.get("status", "")) != "active":
		_team_battle_view.set_busy(false)
		return
	var pending := GameState.begin_team_battle_action(
		str(session.get("id", "")),
		int(session.get("turn_number", 1)),
		int(session.get("version", 1)),
		action,
		"",
		switch_to_slot
	)
	await _submit_pending_team_battle(pending)


## Sama seperti Duel. Turn yang memunculkan Switch ikut diprediksi selama sheet
## penggantinya sudah ada di arena — `_prepare_team_active_art()` memuat seluruh
## roster saat session dibuka, jadi biasanya sudah ada. `final_ace` tetap milik
## server: pelat dan dialog Boss-nya sekali per run, jadi tidak boleh ditebak.
func _predict_team_turn(session: Dictionary, pending: Dictionary) -> Dictionary:
	var state := GameState.as_dict(session.get("state"))
	if state.is_empty() or str(state.get("status", "")) != "active":
		return {}
	if int(state.get("turn", 0)) != int(pending.get("expected_turn", -1)):
		return {}
	var outcome := TeamSim.resolve_team_turn(
		state,
		str(pending.get("action", "")),
		str(pending.get("idempotency_key", "")),
		str(pending.get("item_id", "")),
		pending.get("switch_to_slot", null),
		BattleSim.index_catalog(_catalog)
	)
	if not bool(outcome.get("ok", false)):
		return {}
	var events: Array = outcome["events"]
	var next_state: Dictionary = outcome["state"]
	for value in events:
		if str(GameState.as_dict(value).get("type", "")) == "final_ace":
			return {}
	for anima_id in TeamSim.switch_targets(events, next_state):
		if not _team_art_cache.has(anima_id):
			return {}
	var predicted := session.duplicate(true)
	predicted["state"] = next_state
	predicted["turn_number"] = int(next_state.get("turn", session.get("turn_number", 1)))
	predicted["status"] = str(next_state.get("status", "active"))
	return {"session": predicted, "events": events}


func _dispatch_team_turn(payload: Dictionary) -> void:
	_team_turn_in_flight = true
	_team_turn_result = await Backend.team_battle("turn", payload)
	_team_turn_in_flight = false
	_team_turn_settled.emit()


func _await_team_turn() -> Dictionary:
	if _team_turn_in_flight:
		await _team_turn_settled
	return _team_turn_result


func _submit_pending_team_battle(pending: Dictionary) -> void:
	var account_epoch := GameState.session_epoch
	if pending.is_empty():
		return
	var action := str(pending.get("action", ""))
	_team_battle_view.begin_action(action)
	_set_busy(true)
	var payload := team_battle_turn_payload(pending)
	var session_before: Dictionary = _team_battle_view.session_data()
	var predicted := _predict_team_turn(session_before, pending)
	_dispatch_team_turn(payload)
	if not predicted.is_empty():
		await _team_battle_view.play_events(
			predicted["events"], predicted["session"], _team_art_cache.duplicate()
		)
		_team_battle_view.set_busy(_team_turn_in_flight)
	var res := await _await_team_turn()
	if not Backend.response_applies(res, account_epoch):
		return
	if not res.ok:
		# Turn yang tidak sampai ke server tidak boleh meninggalkan arena di masa
		# depan: tap berikutnya akan mengirim nomor turn yang belum pernah ada.
		if not predicted.is_empty() and not session_before.is_empty():
			_team_battle_view.set_session(session_before, _team_art_cache.duplicate())
		if res.error in ["STALE_TEAM_BATTLE", "TEAM_BATTLE_FINISHED"]:
			_set_busy(false)
			await _resume_team_battle()
			return
		var session := _team_battle_view.session_data()
		if not session.is_empty():
			GameState.remember_team_battle(
				str(session.get("id", "")),
				int(session.get("turn_number", 1)),
				int(session.get("version", 1))
			)
		_team_battle_view.set_error(res.error)
		_set_busy(false)
		return
	var data := GameState.as_dict(res.data)
	var next_session := GameState.as_dict(data.get("session"))
	next_session["last_reward"] = GameState.as_dict(data.get("reward"))
	var events := _variant_array(data.get("events"))
	if next_session.is_empty():
		_team_battle_view.set_error("TEAM_BATTLE_NOT_FOUND")
		_set_busy(false)
		return
	if _turn_outcome_matches(predicted, next_session, events):
		# Animasinya sudah jalan dari simulasi lokal; `_set_busy(false)` di bawah
		# yang melepas tombolnya.
		_team_battle_view.set_session(next_session, _team_art_cache.duplicate())
	else:
		var art := _team_art_cache.duplicate()
		for value in events:
			if str(GameState.as_dict(value).get("type", "")) == "switch":
				art = await _prepare_team_active_art(next_session)
				break
		# Arena masih menampilkan prediksi, jadi log server diputar dari session
		# sebelum turn supaya Summon membaca HP anggota yang masuk apa adanya.
		await _team_battle_view.play_events(events, next_session, art, session_before)
	GameState.confirm_team_battle_response(next_session)
	_set_busy(false)
	if action == "item":
		_refresh_inventory()
	await _apply_team_battle_reward(GameState.as_dict(data.get("reward")))


static func team_battle_turn_payload(pending: Dictionary) -> Dictionary:
	var action := str(pending.get("action", ""))
	var payload := {
		"session_id": str(pending.get("session_id", "")),
		"expected_turn": int(pending.get("expected_turn", 1)),
		"expected_version": int(pending.get("expected_version", 1)),
		"action": action,
		"idempotency_key": str(pending.get("idempotency_key", "")),
	}
	if action == "item":
		payload["item_id"] = str(pending.get("item_id", ""))
	if action == "switch":
		payload["switch_to_slot"] = int(pending.get("switch_to_slot", -1))
	return payload


func _forfeit_team_battle() -> void:
	if _busy:
		return
	var session := _team_battle_view.session_data()
	var session_id := str(
		session.get("id", GameState.pending_team_battle.get("session_id", ""))
	)
	if session_id.is_empty():
		return
	_team_battle_view.show_retreat_banner()
	_set_busy(true)
	var res := await Backend.team_battle("forfeit", {"session_id": session_id})
	if res.ok:
		var closed := GameState.as_dict(res.data)
		GameState.finish_team_battle()
		var art := await _prepare_team_active_art(closed)
		_team_battle_view.set_session(closed, art)
	else:
		_team_battle_view.set_error(res.error)
	_set_busy(false)


func _show_team_battle_session(session: Dictionary) -> bool:
	if session.is_empty():
		_team_battle_view.set_error("TEAM_BATTLE_NOT_FOUND")
		return false
	var art := await _prepare_team_active_art(session)
	if art.is_empty():
		_team_battle_view.set_error("TEAM_ART_NOT_READY")
		return false
	_team_battle_view.set_session(session, art)
	return true


func _prepare_team_active_art(session: Dictionary) -> Dictionary:
	var loaded_by_id: Dictionary = {}
	var state := GameState.as_dict(session.get("state"))
	for side in ["player", "opponent"]:
		var party := GameState.as_dict(state.get(side))
		var state_roster := _variant_array(party.get("roster"))
		var active_slot := int(party.get("active_slot", 0))
		if active_slot < 0 or active_slot >= state_roster.size():
			return {}
		var snapshots := _variant_array(
			session.get("player_snapshot" if side == "player" else "opponent_snapshot")
		)
		for slot in state_roster.size():
			var member := GameState.as_dict(state_roster[slot])
			var anima_id := str(member.get("anima_id", ""))
			if anima_id.is_empty():
				if slot == active_slot:
					return {}
				continue
			if _team_art_cache.has(anima_id):
				loaded_by_id[anima_id] = _team_art_cache[anima_id]
				continue
			var snapshot := _snapshot_for_anima(snapshots, anima_id)
			if snapshot.is_empty():
				if slot == active_slot:
					return {}
				continue
			var loaded := await _prepare_battle_art(snapshot)
			if not bool(loaded.get("ok", false)):
				if slot == active_slot:
					return {}
				continue
			_team_art_cache[anima_id] = loaded
			loaded_by_id[anima_id] = loaded
	return loaded_by_id


func _apply_team_battle_reward(reward: Dictionary) -> void:
	var exp_rows := _variant_array(reward.get("anima_exp"))
	if int(reward.get("bits", 0)) <= 0 and exp_rows.is_empty():
		return
	var session := _team_battle_view.session_data()
	var level_ups := expedition_level_rewards(
		reward, _variant_array(session.get("player_snapshot"))
	)
	await _refresh_team_battle_authority()
	for item in level_ups:
		var anima := _roster_row(str(item.get("anima_id", "")))
		if anima.is_empty():
			anima = GameState.as_dict(item.get("anima"))
		if anima.is_empty():
			continue
		_celebrate_level_up(
			int(item.get("level", 1)),
			int(item.get("previous_level", 1)),
			int(item.get("previous_score", -1)),
			int(item.get("new_score", -1)),
			anima
		)


func _apply_expedition_reward(reward: Dictionary, encounter: Dictionary) -> void:
	var level_ups := expedition_level_rewards(
		reward, _variant_array(encounter.get("player_snapshot"))
	)
	await _refresh_team_battle_authority()
	if level_ups.is_empty():
		return
	var ready: Array[Dictionary] = []
	for item in level_ups:
		var anima_id := str(item.get("anima_id", ""))
		var anima := _roster_row(anima_id)
		if anima.is_empty():
			anima = GameState.as_dict(item.get("anima"))
		if anima.is_empty():
			continue
		item["anima"] = anima.duplicate(true)
		ready.append(item)
	if ready.is_empty():
		return
	_expedition_level_queue.append_array(ready)
	if _expedition_level_sequence_active:
		return
	_expedition_level_sequence_active = true
	_expedition_view.set_level_up_sequence_busy(true)
	_show_next_expedition_level_up()


static func expedition_level_rewards(
	reward: Dictionary,
	snapshots: Array
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _variant_array(reward.get("anima_exp")):
		var row := GameState.as_dict(value)
		var exp := int(row.get("exp", 0))
		var anima_id := str(row.get("anima_id", ""))
		if exp <= 0 or anima_id.is_empty():
			continue
		var snapshot := _snapshot_for_anima(snapshots, anima_id)
		var previous_score := int(row.get("care_score_before", -1))
		if previous_score < 0:
			previous_score = int(snapshot.get("care_score", -1))
		if previous_score < 0:
			continue
		var new_score := previous_score + exp
		var level := int(CARE_RULES.leveled_up(previous_score, new_score))
		if level <= 0:
			continue
		result.append({
			"anima_id": anima_id,
			"anima": snapshot,
			"level": level,
			"previous_level": CARE_RULES.level_from_exp(previous_score),
			"previous_score": previous_score,
			"new_score": new_score,
		})
	return result


func _show_next_expedition_level_up() -> void:
	if _expedition_level_queue.is_empty():
		_expedition_level_sequence_active = false
		_expedition_view.set_level_up_sequence_busy(false)
		return
	var item: Dictionary = GameState.as_dict(_expedition_level_queue.pop_front())
	_celebrate_level_up(
		int(item.get("level", 1)),
		int(item.get("previous_level", 1)),
		int(item.get("previous_score", -1)),
		int(item.get("new_score", -1)),
		GameState.as_dict(item.get("anima")),
		&"expedition_level_up"
	)


func _refresh_team_battle_authority() -> void:
	var account_epoch := GameState.session_epoch
	var profile_res := await Backend.fetch_profile()
	if not Backend.response_applies(profile_res, account_epoch):
		return
	_apply_profile_refresh(profile_res)
	await _reload_roster()
	if GameState.session_epoch != account_epoch:
		return
	_refresh_header()
	_refresh_stats()
	_refresh_care()
	_populate_collection()


static func _team_of_kind(teams: Array, kind: String) -> Dictionary:
	for value in teams:
		var team := GameState.as_dict(value)
		if str(team.get("kind", "")) == kind:
			return team
	return {}


static func _snapshot_for_anima(snapshots: Array, anima_id: String) -> Dictionary:
	for value in snapshots:
		var snapshot := GameState.as_dict(value)
		if str(snapshot.get("anima_id", "")) == anima_id:
			return snapshot
	return {}


static func _variant_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


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
	_sync_shop_chrome()
	return true


func _prepare_battle_art(snapshot: Dictionary) -> Dictionary:
	if str(snapshot.get("system_asset", "")) == "placeholder":
		var placeholder := PlaceholderSheet.build()
		return AnimaLoader.build(
			ImageTexture.create_from_image(placeholder["image"]),
			placeholder["manifest"]
		)
	var sheet_url := str(snapshot.get("sheet_url", ""))
	if not sheet_url.is_empty():
		return await _prepare_signed_battle_art(snapshot, sheet_url)
	return await _prepare_anima_art(
		str(snapshot.get("species_key", "")),
		str(snapshot.get("color_bucket", "")),
		int(snapshot.get("stage", 1)),
		str(snapshot.get("sheet_path", "")),
		GameState.as_dict(snapshot.get("manifest")),
		false,
		str(snapshot.get("anima_id", ""))
	)


func _prepare_signed_battle_art(snapshot: Dictionary, sheet_url: String) -> Dictionary:
	var manifest := GameState.as_dict(snapshot.get("manifest"))
	if manifest.is_empty():
		return {"ok": false}
	var account_epoch := GameState.session_epoch
	var download := await Backend.download_url(sheet_url)
	if not Backend.response_applies(download, account_epoch):
		return {"ok": false}
	if not download.ok:
		return {"ok": false}
	var image := Image.new()
	if image.load_png_from_buffer(download.bytes) != OK:
		return {"ok": false}
	return AnimaLoader.build(ImageTexture.create_from_image(image), manifest)


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
	var account_epoch := GameState.session_epoch
	var profile_res := await Backend.fetch_profile()
	if not Backend.response_applies(profile_res, account_epoch):
		return
	_apply_profile_refresh(profile_res)
	await _reload_roster()
	if GameState.session_epoch != account_epoch:
		return
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
	var account_epoch := GameState.session_epoch
	_set_busy(true)
	var pending := GameState.pending_scan
	var res := await Backend.create_anima(
		str(pending.get("photo_path", "")),
		str(pending.get("idempotency_key", "")),
		"",
		ScanView.normalize_vibe(pending.get("capture_vibe", ""))
	)
	if not Backend.response_applies(res, account_epoch):
		return
	await _handle_create_result(res, account_epoch)
	if GameState.session_epoch == account_epoch:
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
	if _busy or _update_required:
		return
	if not GameState.pending_evolution.is_empty():
		_say(tr("EVOLUTION_ALREADY_ACTIVE"), true)
		return
	if _guest_scan_locked():
		_show_sign_in_confirmation()
		return
	if _cores_remaining() == 0:
		_say(tr("STATUS_NEED_CORE"), true)
		return
	_switch_destination(BottomNav.SCAN)
	if _picker == null:
		_dialog.popup_centered_ratio(0.9)
		return
	if _picker.hasCamera():
		if is_instance_valid(_photo_source_sheet):
			_photo_source_sheet.open_chooser()
		else:
			_request_camera_photo()
	else:
		_request_gallery_photo()


func _request_camera_photo() -> void:
	if _picker == null:
		return
	_picker.getCameraImage()


func _request_gallery_photo() -> void:
	if _picker == null:
		return
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
	var account_epoch := GameState.session_epoch
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
	var scan := GameState.begin_scan("png" if is_png else "jpg", _scan_view.vibe())

	_scan_view.set_phase(&"analyzing")
	_say(tr("STATUS_UPLOADING"))
	var up := await Backend.upload_photo(
		str(scan["photo_path"]), bytes, "image/png" if is_png else "image/jpeg"
	)
	if not Backend.response_applies(up, account_epoch):
		return
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
	var res := await Backend.create_anima(
		str(scan["photo_path"]),
		str(scan["idempotency_key"]),
		"",
		str(scan.get("capture_vibe", ""))
	)
	if not Backend.response_applies(res, account_epoch):
		return
	await _handle_create_result(res, account_epoch)
	if GameState.session_epoch == account_epoch:
		_set_busy(false)


func _handle_create_result(res: Dictionary, account_epoch: int) -> void:
	if not Backend.response_applies(res, account_epoch):
		return
	var profile_res := await Backend.fetch_profile()
	if not Backend.response_applies(profile_res, account_epoch):
		return
	_apply_profile_refresh(profile_res)
	_refresh_header()

	if not res.ok:
		match res.error:
			"GUEST_SCAN_USED":
				_say(tr("STATUS_SIGN_IN_TO_SCAN"), true)
			"NO_SCAN_CHARGE":
				_say(tr("STATUS_NO_SCAN_CHARGE"))
			"NO_CORE":
				# Hasil Vision sudah dibayar dan disimpan server sebagai Temuan
				# Tertunda, jadi ini bukan kerugian — pemain tidak perlu memfoto
				# ulang benda yang mungkin sudah tidak ada di dekatnya.
				_say(tr("STATUS_NO_CORE"))
			"SPEND_CAP":
				_say(tr("STATUS_SPEND_CAP"))
			"VIBE_UNAVAILABLE":
				_say(tr("STATUS_VIBE_UNAVAILABLE"), true)
			"INVALID_VIBE":
				_say(tr("STATUS_VIBE_UNAVAILABLE"), true)
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
	var account_epoch := GameState.session_epoch
	_start_incubation()
	_say(tr("STATUS_SYNTHESIZING"))
	var remaining_poll_sec := POLL_TIMEOUT_SEC

	# Hitung waktu polling aktif, bukan wall clock. SceneTreeTimer berhenti saat app
	# di-background; waktu yang pemain habiskan di kamera/app lain tidak boleh
	# langsung menghabiskan timeout begitu Scanima aktif lagi.
	while remaining_poll_sec > 0.0:
		await get_tree().create_timer(POLL_INTERVAL_SEC).timeout
		if GameState.session_epoch != account_epoch:
			return
		remaining_poll_sec -= POLL_INTERVAL_SEC
		var res := await Backend.fetch_anima(anima_id)
		if not Backend.response_applies(res, account_epoch):
			return
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
					str(row.get("sheet_path", "")),
					GameState.as_dict(row.get("manifest")),
					str(row.get("nickname", "")),
					row
				)
				return
			"failed":
				# Server sudah mengembalikan Core-nya sendiri lewat refund_generation.
				_say(tr("STATUS_GENERATION_FAILED"))
				var profile_res := await Backend.fetch_profile()
				if not Backend.response_applies(profile_res, account_epoch):
					return
				_apply_profile_refresh(profile_res)
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
	var account_epoch := GameState.session_epoch
	var hatching := _incubator.is_active() and not _evolution_chamber_active
	var loaded := await _prepare_anima_art(
		species_key, color_bucket, stage, sheet_path, manifest, complete_scan, anima_id, stage
	)
	if GameState.session_epoch != account_epoch:
		return
	if not bool(loaded.get("ok", false)):
		if complete_scan:
			_restore_previous_anima()
		return
	_anima.apply(loaded)
	_anima.visible = not hatching and not _evolution_chamber_active

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
	# Progres tap milik identitas yang tampil sebelumnya, jadi Anima/akun baru
	# selalu mulai dari nol taps ke arah wake meskipun kebetulan juga tidur.
	_reset_wake_taps()
	# Sprite dipasang sebelum baris ini, jadi `pose_changed` tadi masih membaca
	# tinggi Anima sebelumnya. Skalanya disamakan setelah tingginya diketahui.
	_sync_home_body()
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
		_scan_view.reset_vibe()
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
		await _summon_current_anima()
	else:
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
	report_status: bool = true,
	anima_id: String = "",
	cache_stage: int = -1
) -> Dictionary:
	var account_epoch := GameState.session_epoch
	if species_key.is_empty() or color_bucket.is_empty():
		if report_status:
			_say(tr("STATUS_SPECIES_DATA_ERROR"))
		return {"ok": false}

	var use_anima_cache := not anima_id.is_empty()
	var art_stage := cache_stage if cache_stage > 0 else stage
	if use_anima_cache and GameState.has_sprite_for_anima(anima_id, art_stage):
		return AnimaLoader.load_from_manifest(GameState.manifest_path_for_anima(anima_id, art_stage))
	if not use_anima_cache and GameState.has_sprite(species_key, color_bucket, stage):
		return AnimaLoader.load_from_manifest(
			GameState.manifest_path(species_key, color_bucket, stage)
		)

	if report_status:
		_say(tr("STATUS_DOWNLOADING_ART"))

	if manifest.is_empty() or sheet_path.is_empty():
		var art := await Backend.fetch_species_art(species_key, color_bucket, stage)
		if not Backend.response_applies(art, account_epoch):
			return {"ok": false, "abandoned": true}
		if not art.ok or typeof(art.data) != TYPE_ARRAY or (art.data as Array).is_empty():
			print("art library error: %s" % art.error)
			if report_status:
				_say(tr("STATUS_ART_LIBRARY_ERROR"))
			return {"ok": false}
		var row := GameState.as_dict((art.data as Array)[0])
		sheet_path = str(row.get("sheet_path", ""))
		manifest = GameState.as_dict(row.get("manifest"))
		use_anima_cache = false

	var download := (
		await Backend.download_anima_sheet(sheet_path)
		if use_anima_cache
		else await Backend.download_sheet(sheet_path)
	)
	if not Backend.response_applies(download, account_epoch):
		return {"ok": false, "abandoned": true}
	if not download.ok and use_anima_cache:
		download = await Backend.download_sheet(sheet_path)
		if not Backend.response_applies(download, account_epoch):
			return {"ok": false, "abandoned": true}
	if not download.ok:
		print("art download error: %s" % download.error)
		if report_status:
			_say(tr("STATUS_ART_DOWNLOAD_ERROR"))
		return {"ok": false}

	var stored: Dictionary
	var manifest_path := ""
	if use_anima_cache:
		stored = GameState.store_sprite_for_anima(anima_id, manifest, download.bytes, art_stage)
		manifest_path = GameState.manifest_path_for_anima(anima_id, art_stage)
	else:
		stored = GameState.store_sprite(
			species_key, color_bucket, stage, manifest, download.bytes
		)
		manifest_path = GameState.manifest_path(species_key, color_bucket, stage)
	if not stored.ok:
		print("art save error: %s" % stored.error)
		if report_status:
			_say(tr("STATUS_ART_SAVE_ERROR"))
		return {"ok": false}

	var loaded := AnimaLoader.load_from_manifest(manifest_path)
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


## Mengecat Home dari salinan display-only respons server terakhir supaya boot
## tidak menampilkan layar kosong selama empat round trip. Semua angka di sini
## ditimpa `_boot()` begitu Postgres menjawab.
func _paint_boot_cache() -> bool:
	var cache: Dictionary = GameState.boot_cache
	if cache.is_empty():
		return false
	var roster := _variant_array(cache.get("roster"))
	var rows: Array[Dictionary] = []
	for value in roster:
		var row := GameState.as_dict(value)
		if not str(row.get("id", "")).is_empty():
			rows.append(row)
	if rows.is_empty():
		return false
	GameState.profile = GameState.as_dict(cache.get("profile"))
	_catalog = _variant_array(cache.get("catalog"))
	_inventory = _variant_array(cache.get("inventory"))
	_roster = rows
	if is_instance_valid(_expedition_controller):
		_expedition_controller.set_roster(_roster)
	_refresh_header()
	_populate_collection()
	# ShopSheet memegang salinannya sendiri, jadi tanpa ini membuka Shop sebelum
	# jaringan menjawab memperlihatkan daftar kosong padahal katalognya sudah ada.
	if is_instance_valid(_shop_sheet) and not _catalog.is_empty():
		_shop_sheet.set_catalog(
			_catalog, _inventory, int(GameState.profile.get("bits", 0))
		)
	_set_home_shell_state(&"ready")
	return true


func _show_cached_anima() -> void:
	var painted := _paint_boot_cache()
	if not painted:
		return
	var anima := _active_row()
	if anima.is_empty():
		return
	_anima.visible = false
	_current_anima = normalize_anima_data(anima)
	# Cache adalah nilai sync terakhir, jadi meter-nya diproyeksikan ke sekarang
	# dengan aturan decay yang sama seperti Collection. Tanpa itu Home membuka
	# dengan Hunger jam delapan pagi setelah app ditutup semalaman.
	if painted and typeof(_current_anima.get("care")) == TYPE_DICTIONARY:
		_current_anima["care"] = CareRules.projected_care(
			_current_anima, str(GameState.profile.get("active_anima_id", ""))
		)
	# last_anima hanya menyimpan pilihan terakhir, bukan care server-authoritative.
	# Menampilkan art cache dari sana selalu memulai pose Idle dan membuat Anima
	# yang sedang tidur berkedip bangun. Art hanya boleh terlihat kalau row-nya
	# membawa care sungguhan — dari cache boot atau dari _present().
	var anima_id := str(_current_anima.get("id", ""))
	var art_stage := _sprite_stage_for_row(_current_anima)
	var pending_evolution_here := _pending_evolution_matches(anima_id)
	if pending_evolution_here:
		_current_anima["status"] = "evolving"
		_upsert_roster(_current_anima)
		_apply_evolution_chamber_for_row(
			_current_anima, _destination == BottomNav.HOME
		)
	if (
		painted
		and not anima_id.is_empty()
		and GameState.has_sprite_for_anima(anima_id, art_stage)
		and not CareRules.is_evolving(_current_anima)
		and not pending_evolution_here
		and not _evolution_chamber_active
	):
		var loaded := AnimaLoader.load_from_manifest(
			GameState.manifest_path_for_anima(anima_id, art_stage)
		)
		if bool(loaded.get("ok", false)):
			_anima.apply(loaded)
			_anima.visible = true
	_refresh_stats()
	_refresh_care()


func _upsert_roster(row: Dictionary) -> void:
	var id := str(row.get("id", ""))
	if id.is_empty():
		return
	for i in _roster.size():
		if str(_roster[i].get("id", "")) == id:
			_roster[i] = row
			return
	_roster.push_front(row)


func _roster_row(anima_id: String) -> Dictionary:
	for row in _roster:
		if str(row.get("id", "")) == anima_id:
			return row
	return {}


func _populate_collection() -> void:
	if not is_instance_valid(_collection_view):
		return
	_collection_view.set_evolution_enabled(_evolution_enabled())
	_collection_view.set_synthesis_enabled(_synthesis_enabled())
	# ponytail: pass pertama membuat thumbnail cached secara sinkron. Plafon
	# sekitar 100 Anima lokal; kalau roster nyata melewatinya, simpan thumbnail
	# 128px terpisah saat sheet diunduh dan virtualisasikan daftar.
	_collection_view.set_rows(_roster, _summoned_id(), _thumbnail_for)


func _thumbnail_for(row: Dictionary) -> Texture2D:
	var anima_id := str(row.get("id", ""))
	if anima_id.is_empty():
		anima_id = str(row.get("anima_id", ""))
	var sheet_path := str(row.get("sheet_path", ""))
	var species := str(row.get("species_key", ""))
	var color := str(row.get("color_bucket", ""))
	var stage := _sprite_stage_for_row(row)
	var pose := CareRules.collection_pose(row, _summoned_id())
	var use_anima := not anima_id.is_empty() and not sheet_path.is_empty()
	var cache_key := (
		"%s|%d|%s" % [anima_id, stage, pose]
		if use_anima
		else "%s|%s|%d|%s" % [species, color, stage, pose]
	)
	if _thumbnail_cache.has(cache_key):
		return _thumbnail_cache[cache_key] as Texture2D

	var manifest_path := ""
	if use_anima and GameState.has_sprite_for_anima(anima_id, stage):
		manifest_path = GameState.manifest_path_for_anima(anima_id, stage)
	elif GameState.has_sprite(species, color, stage):
		manifest_path = GameState.manifest_path(species, color, stage)

	if not manifest_path.is_empty():
		var loaded := AnimaLoader.load_from_manifest(manifest_path)
		if bool(loaded.get("ok", false)):
			var frames: SpriteFrames = loaded.get("frames")
			if frames != null:
				if not frames.has_animation(pose) or frames.get_frame_count(pose) <= 0:
					pose = "idle"
				if frames.has_animation(pose) and frames.get_frame_count(pose) > 0:
					var frame := frames.get_frame_texture(pose, 0)
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


## The HUD's own copy of the compact identity line, sitting under Brand instead
## of beside the Stage. Mirrors exactly what `HomeView.set_anima()` renders,
## but only for the "ready" state -- loading/error/empty/evolution keep their
## sentence-length copy in the Stage-centered headline, which would not fit
## the HUD's own bar.
func _update_hud_identity() -> void:
	var show_identity := (
		_destination == BottomNav.HOME
		and not _current_anima.is_empty()
		and _home_view.shell_state() == &"ready"
	)
	_hud_anima_name.visible = show_identity
	_hud_anima_meta.visible = show_identity
	if not show_identity:
		return
	_hud_anima_name.text = LocaleManager.display_name(_current_anima)
	_hud_anima_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(CARE_RULES.level_from_exp(int(_current_anima.get("care_score", 0)))),
		LocaleManager.element_compact(_current_anima),
	]


func _refresh_stats() -> void:
	var details_row := _profile_anima if not _profile_anima.is_empty() else _current_anima
	_details_view.set_evolution_enabled(_evolution_enabled())
	_details_view.set_synthesis_enabled(_synthesis_enabled())
	_details_view.set_history_source_names(_history_source_names())
	_details_view.set_anima(
		details_row,
		_thumbnail_for(details_row) if not details_row.is_empty() else null
	)
	_home_view.set_anima(_current_anima, _busy)
	_update_hud_identity()
	if _battle_view.session_data().is_empty():
		_battle_view.set_lobby(_current_anima)
	else:
		_battle_view.set_companion(_current_anima)
	_first_anima_effect.set_active(_home_view.shell_state() == &"empty")
	_bottom_nav.set_busy(_busy, _details_available())


func _set_home_shell_state(state: StringName) -> void:
	_home_view.set_shell_state(state)
	_update_hud_identity()
	_first_anima_effect.set_active(state == &"empty")
	if state != &"ready":
		_anima.visible = false


func _refresh_care() -> void:
	_schedule_sleep_completion()
	var has_care := typeof(_current_anima.get("care")) == TYPE_DICTIONARY
	if not has_care:
		_home_view.set_anima(_current_anima, _busy)
		_update_hud_identity()
		return

	var sleeping := _is_sleeping(_current_anima)
	var dormant := _has_timestamp(_current_anima.get("dormant_since"))
	if not sleeping:
		_reset_wake_taps()
	_home_view.update_care(_current_anima, _busy)
	_update_hud_identity()
	if _battle_view.session_data().is_empty():
		_battle_view.set_lobby(_current_anima)
	else:
		_battle_view.set_companion(_current_anima)
	if _profile_anima.is_empty():
		_details_view.set_anima(_current_anima, _thumbnail_for(_current_anima))
	if _anima.sprite_frames != null:
		_anima.apply_care_state(sleeping, dormant, _current_anima.get("care"))


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


## Anchor yang diskalakan, bukan presenter-nya: `_start_motion()` menulis
## `scale = Vector2.ONE` setiap ganti pose, jadi skala yang dipasang langsung ke
## sprite hilang pada napas berikutnya. Arena memakai pola yang sama lewat
## `_player_anchor`. Dibuat di kode dan hanya membungkus Anima + bayangannya
## supaya Incubator dan FirstAnimaEffect tetap pada ukuran yang digambar.
func _make_anima_body_anchor() -> Node2D:
	var anchor := Node2D.new()
	anchor.name = "AnimaBody"
	_stage.add_child(anchor)
	_anima.reparent(anchor, false)
	return anchor


func _make_home_ground_shadow(anchor: Node2D) -> Sprite2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.01, 0.02, 0.05, 0.42),
		Color(0.01, 0.02, 0.05, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 220
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var shadow := Sprite2D.new()
	shadow.name = "HomeGroundShadow"
	shadow.texture = texture
	shadow.visible = false
	shadow.z_index = 0
	anchor.add_child(shadow)
	anchor.move_child(shadow, 0)
	return shadow


func _sync_home_body(_pose: StringName = &"") -> void:
	if is_instance_valid(_anima_body):
		var body_scale := stage_scale_for(
			float(_current_anima.get("body_height_cm", 0.0)),
			_anima.reference_height_px(),
			get_viewport_rect().size
		)
		_anima_body.scale = Vector2(body_scale, body_scale)
	if not is_instance_valid(_home_ground_shadow):
		return
	_anima.sync_ground_shadow(_home_ground_shadow)
	_home_ground_shadow.scale = Vector2(_home_ground_shadow.scale.x * 0.82, 0.52)
	_home_ground_shadow.modulate.a = lerpf(0.90, 0.76, LocalDaylight.daylight_blend())


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

	var immersive := _is_immersive_arena()
	_apply_margins(
		_safe_margin,
		insets,
		16.0 if immersive else BASE_MARGIN,
		8.0 if immersive else HUD_TOP_PAD
	)
	_sync_shop_chrome()
	_place_toast(insets)
	_stage.position = stage_position_for(viewport_size)
	_sync_home_body()


## Ground line-nya diukur pada art, bukan pada viewport, dan safe area sengaja
## tidak ikut: `HomeBackground` menggambar `cover` yang dipin ke bawah tanpa
## melihat inset, jadi ratio yang dihitung dari viewport meleset sebesar crop-nya
## begitu aspect device menjauh dari aspect art — kaki lalu terlihat melayang.
static func stage_position_for(viewport_size: Vector2) -> Vector2:
	var art := home_art_rect(viewport_size)
	var ground_ratio := (
		HOME_GROUND_LANDSCAPE_RATIO
		if HomeBackground.uses_landscape(viewport_size)
		else HOME_GROUND_PORTRAIT_RATIO
	)
	return Vector2(viewport_size.x * 0.5, art.position.y + art.size.y * ground_ratio)


static func home_art_rect(viewport_size: Vector2) -> Rect2:
	return HomeBackground.floor_aligned_cover_rect(
		(
			HomeBackground.HOME_BACKGROUND_NIGHT_LANDSCAPE
			if HomeBackground.uses_landscape(viewport_size)
			else HomeBackground.HOME_BACKGROUND_NIGHT
		).get_size(),
		viewport_size
	)


## Home menggambar sel sheet pada ukuran pikselnya, jadi tanpa normalisasi yang
## menentukan besar Anima adalah resolusi sheet — bukan tingginya. Terukur 22
## Agustus 2026: Adult hasil evolusi kembali 312 px sementara Rookie-nya 517 px,
## jadi tumbuh +25% dalam cm justru menyusut jadi 60% di layar. Membagi dengan
## `reference_height_px` persis yang sudah dilakukan arena, tetapi kurvanya milik
## Home sendiri — lihat `HOME_BODY_HEIGHT_CURVE`. Nol referensi berarti manifest
## lama: biarkan apa adanya.
static func stage_scale_for(
	body_height_cm: float,
	reference_height_px: float,
	viewport_size: Vector2
) -> float:
	var art := home_art_rect(viewport_size)
	if reference_height_px <= 0.0 or art.size.y <= 0.0:
		return 1.0
	var height_cm := (
		body_height_cm if body_height_cm > 0.0 else BattleScale.BODY_HEIGHT_REFERENCE_CM
	)
	var height_ratio := (
		BattleScale.anima_display_height_cm(height_cm) / BattleScale.BODY_HEIGHT_REFERENCE_CM
	)
	var target := art.size.y * HOME_BODY_SPAN_RATIO * pow(
		height_ratio, HOME_BODY_HEIGHT_CURVE
	)
	target = clampf(
		target,
		art.size.y * HOME_BODY_SPAN_MIN_RATIO,
		art.size.y * HOME_BODY_SPAN_MAX_RATIO
	)
	return target / reference_height_px


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
	_menu_popover.close()
	_details_view.close_action_menu(false)
	if destination == ANIMA_PROFILE_DEST and not profile_row.is_empty():
		_profile_anima = profile_row.duplicate(true)
	if destination == ANIMA_PROFILE_DEST and not _details_available():
		destination = BottomNav.HOME
	var previous := _destination
	if previous == BottomNav.HOME and destination != BottomNav.HOME:
		_stop_evolution_chamber()
		_reset_wake_taps()
	if previous == BottomNav.COLLECTION and destination != BottomNav.COLLECTION:
		_collection_view.close_sheet()
	if previous == BottomNav.BATTLE and destination != BottomNav.BATTLE:
		if is_instance_valid(_battle_pick_sheet) and _battle_pick_sheet.visible:
			_battle_pick_sheet.close()
	if destination == BottomNav.COLLECTION and previous != BottomNav.COLLECTION:
		_collection_view.begin_visit()
		_populate_collection()
	if destination == ANIMA_PROFILE_DEST:
		if profile_row.is_empty():
			_profile_anima = _current_anima.duplicate(true)
	_destination = destination
	# The raised-tab HUD art and the compact identity line under Brand are a
	# Home-only look; every other tab keeps the plain HudSurface bar until it
	# gets a background sized for its own layout. This has to land before
	# HomeView becomes visible below: HomeView fills whatever room ViewStack
	# has left under the HUD, so if the HUD grew after HomeView already
	# measured itself, HomeView is left holding a stale, too-tall layout.
	_top_hud.theme_type_variation = (
		&"HomeHudSurface" if destination == BottomNav.HOME else &"HudSurface"
	)
	_update_hud_identity()
	_home_view.visible = destination == BottomNav.HOME
	_home_background.visible = destination == BottomNav.HOME
	_scan_view.visible = destination == BottomNav.SCAN
	_battle_view.visible = destination == BottomNav.BATTLE
	_collection_view.visible = destination == BottomNav.COLLECTION
	_synthesis_view.visible = destination == SYNTHESIS_DEST
	_details_view.visible = destination == ANIMA_PROFILE_DEST
	_seeker_profile_view.visible = destination == SEEKER_PROFILE_DEST
	_atlas_view.visible = destination == ATLAS_DEST
	if destination not in [SEEKER_PROFILE_DEST, ANIMA_PROFILE_DEST, ATLAS_DEST, SYNTHESIS_DEST]:
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
		and _battle_view.session_data().is_empty()
		and not _battle_view.is_team_mode()
		and not _battle_view.is_expedition_mode()
	):
		_battle_view.set_lobby(_current_anima)
		if (
			GameState.pending_battle.is_empty()
			and GameState.pending_team_battle.is_empty()
			and GameState.pending_expedition.is_empty()
			and refresh_battle_reward
		):
			_refresh_battle_reward_status()

	var stage_destination := destination == BottomNav.HOME or (
		destination == BottomNav.SCAN and _incubator.is_active()
	)
	_stage.visible = stage_destination
	if destination == BottomNav.HOME:
		var evolving_row := _evolving_roster_row()
		if evolving_row.is_empty() and not GameState.pending_evolution.is_empty():
			evolving_row = _roster_row(str(GameState.pending_evolution.get("anima_id", "")))
		if not evolving_row.is_empty() and GameState.pending_scan.is_empty():
			_apply_evolution_chamber_for_row(evolving_row, true)
		else:
			_anima.visible = _anima.sprite_frames != null and not _incubator.is_active()
	elif destination != BottomNav.SCAN:
		_anima.visible = false

	if destination == BottomNav.COLLECTION and not _roster_error.is_empty() and not _busy:
		_reload_roster()
	if destination == ANIMA_PROFILE_DEST:
		_refresh_stats()
		call_deferred("_refresh_gallery_status")
		call_deferred("_refresh_synthesis_history")
		call_deferred("_refresh_evolution_history")
	if destination == SYNTHESIS_DEST:
		_synthesis_view.set_rows(_roster)
	if destination == ATLAS_DEST:
		_atlas_view.begin_visit()
	if destination == BottomNav.HOME:
		call_deferred("_maybe_show_chapter_popup")
	_sync_shop_chrome()
	_bottom_nav.set_scan_emphasized(
		_cores_remaining() > 0
		and not _guest_scan_locked()
		and destination != BottomNav.BATTLE
	)
	UiJuice.reveal(_active_view())


func _active_view() -> Control:
	match _destination:
		BottomNav.SCAN:
			return _scan_view
		BottomNav.BATTLE:
			return _battle_view
		BottomNav.COLLECTION:
			return _collection_view
		ANIMA_PROFILE_DEST:
			return _details_view
		SEEKER_PROFILE_DEST:
			return _seeker_profile_view
		ATLAS_DEST:
			return _atlas_view
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
	_collection_view.refresh_localized_ui()
	_atlas_view.refresh_localized_ui()
	_menu_popover.refresh_localized_ui()
	_scan_view.refresh_localized_ui()
	_synthesis_view.refresh_localized_ui()
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


func _open_shop(tab: String = "food") -> void:
	if _destination != BottomNav.HOME:
		return
	if GameState.shop_locked():
		_say(tr("ERROR_SHOP_IN_BATTLE"), true)
		return
	if _shop_sheet.is_shop_open() and tab == "food":
		return
	_shop_sheet.set_catalog(_catalog, _inventory, int(GameState.profile.get("bits", 0)))
	_shop_sheet.open_shop(tab)


func _on_bag_pressed() -> void:
	if _shop_sheet.is_bag_open():
		return
	_open_bag()


func _open_bag(tab: String = "food") -> void:
	if _destination != BottomNav.HOME:
		return
	_shop_sheet.set_catalog(_catalog, _inventory, int(GameState.profile.get("bits", 0)))
	_shop_sheet.open_bag(tab)


func _open_shop_from_empty() -> void:
	_open_shop("item" if _shop_sheet.prefers_item_tab() else "food")


func _open_feed_picker() -> void:
	_open_bag("food")


func _open_battle_item_picker() -> void:
	_shop_sheet.set_catalog(_catalog, _inventory, int(GameState.profile.get("bits", 0)))
	_shop_sheet.open_battle()


## ponytail: satu pembelian in-flight per waktu, jadi tap kedua selama request
## masih terbang diabaikan. Plafonnya jendela satu round trip — sesudah saldo dan
## jumlah item bergerak optimistis, tap ulang biasanya sudah lolos. Upgrade ke
## antrean hanya kalau telemetri menunjukkan tap yang benar-benar hilang.
func _buy_catalog_item(item: Dictionary) -> void:
	var account_epoch := GameState.session_epoch
	if _busy or not GameState.pending_purchase.is_empty():
		return
	if GameState.shop_locked():
		_say(tr("ERROR_SHOP_IN_BATTLE"), true)
		return
	var item_id := str(item.get("id", ""))
	var price := int(item.get("price", 0))
	# Rect ikonnya diambil sebelum apa pun merombak baris ShopSheet --
	# `_apply_optimistic_purchase` di bawah memanggil `set_catalog`, yang
	# `queue_free()` seluruh baris lama termasuk ikon yang mau diterbangkan.
	var icon_snapshot: Dictionary = _shop_sheet.icon_snapshot_for(item_id)
	_shop_sheet.set_pending(item_id)
	var pending := GameState.begin_purchase(item_id, price)
	var bits_before := int(GameState.profile.get("bits", 0))
	var inventory_before := _inventory.duplicate(true)
	_apply_optimistic_purchase(item_id, price)
	_fly_purchased_item(icon_snapshot)
	if not await _send_pending_purchase(pending):
		if GameState.session_epoch != account_epoch:
			return
		_shop_sheet.set_pending("")
		GameState.profile["bits"] = bits_before
		_inventory = inventory_before
		_refresh_header()
		_shop_sheet.set_catalog(_catalog, _inventory, bits_before)
		return
	if GameState.session_epoch == account_epoch:
		_shop_sheet.set_pending("")


## Saldo dan jumlah tas bergerak di frame yang sama dengan tap. Server tetap
## otoritas: `purchase_catalog_item` menimpa keduanya beberapa ratus milidetik
## kemudian, dan `_buy_catalog_item` mengembalikannya kalau pembelian ditolak.
## Toast transient sengaja dibuang di sini -- animasi terbang + pop Bag sudah
## memberi feedback yang sama, dan toast digambar tepat di atas Bag yang
## sedang jadi target animasi itu.
func _apply_optimistic_purchase(item_id: String, price: int) -> void:
	var bits := maxi(0, int(GameState.profile.get("bits", 0)) - maxi(0, price))
	GameState.profile["bits"] = bits
	_inventory = Catalog.with_quantity(
		_inventory, item_id, Catalog.quantity_of(_inventory, item_id) + 1
	)
	_refresh_header()
	_shop_sheet.set_catalog(_catalog, _inventory, bits)


## Ikon baris yang baru dibeli terbang ke Bag lalu memberinya pop terisi.
## `_bag_button`'s parent (`RightButtons`, di dalam TopHud) dipakai sebagai
## host konversi koordinat -- z_index tetap relatif terhadap root canvas
## selama tidak ada leluhur yang menimpanya, jadi menaikkannya sementara
## di sini tetap menang di atas seluruh chrome lain, supaya payoff-nya
## tidak tenggelam di balik scrim ShopSheet yang masih terbuka.
## Restore-nya ke konstanta 0, bukan ke z_index yang ditangkap sebelum
## dinaikkan -- tap beli kedua bisa lolos sebelum flyer pertama mendarat
## (network round trip lebih cepat dari animasi 0,4 s), dan menangkap z_index
## saat itu berarti menangkap 61 milik animasi pertama, lalu me-restore-nya
## sesudah animasi kedua justru mengunci Bag di 61 selamanya.
func _fly_purchased_item(icon_snapshot: Dictionary) -> void:
	var texture := icon_snapshot.get("texture") as Texture2D
	if texture == null or not is_instance_valid(_bag_button) or not _bag_button.visible:
		return
	var host := _bag_button.get_parent() as Control
	if host == null:
		return
	var from_rect: Rect2 = icon_snapshot.get("rect", Rect2())
	# The chip's own rect reaches well below its icon to make room for the
	# "Open" label under it -- landing on that rect's center misses the icon
	# by a good 20 px and looks like it lands between the icon and the label.
	var to_rect := _bag_button.icon_global_rect()
	_bag_button.z_index = 61
	UiJuice.fly_to(host, texture, from_rect, to_rect, func() -> void:
		if not is_instance_valid(_bag_button):
			return
		_bag_button.z_index = 0
		if _bag_button.visible:
			UiJuice.pop(_bag_button, 1.18)
			Sfx.play(Sfx.CUE_ITEM)
	)


## Ikon Feed/Item terbang lewat arc dari sheet yang baru menutup, lalu diserap
## (fade ke 0, bukan berhenti di 0,85 seperti pendaratan Bag) ke tubuh Anima.
## Reaksi presenter (bob/kilau/burst) menunggu `on_arrive` alih-alih tampil di
## frame tap -- itulah alasan `_commit_care` menerima `on_react` daripada
## memanggil `care_feedback()` langsung. `to_rect` sudah dalam ruang canvas
## yang sama dengan Control manapun di bawah `UI` (CanvasLayer-nya identity),
## persis seperti `_fly_purchased_item` di atas menyeberang dari ShopSheet ke
## RightButtons tanpa konversi tambahan -- lihat body_viewport_rect().
func _fly_consumable_to_anima(icon_snapshot: Dictionary, kind: String) -> void:
	var texture := icon_snapshot.get("texture") as Texture2D
	var host := _bag_button.get_parent() as Control if is_instance_valid(_bag_button) else null
	var to_rect := _anima.body_viewport_rect() if is_instance_valid(_anima) else Rect2()
	if texture == null or host == null or to_rect.size == Vector2.ZERO or not _anima.visible:
		if is_instance_valid(_anima):
			_anima.care_feedback(kind)
		return
	UiJuice.fly_to(
		host, texture, icon_snapshot.get("rect", Rect2()), to_rect,
		func() -> void:
			if is_instance_valid(_anima):
				_anima.care_feedback(kind),
		UiJuice.FLY_TO_ARC_PX, 0.0
	)


func _use_catalog_item(item: Dictionary) -> void:
	if (
		(Catalog.is_food(item) or Catalog.is_energy(item))
		and _is_sleeping(_current_anima)
	):
		_say(tr("ERROR_SLEEPING_CONSUME"), true)
		return
	var item_id := str(item.get("id", ""))
	# Sebelum close(): sheet men-queue_free() barisnya begitu ditutup, jadi
	# ikonnya ikut hilang -- sama seperti snapshot pembelian di _buy_catalog_item.
	var icon_snapshot: Dictionary = _shop_sheet.icon_snapshot_for(item_id)
	_shop_sheet.close()
	if Catalog.is_food(item):
		await _commit_care(
			"feed", item_id, func() -> void: _fly_consumable_to_anima(icon_snapshot, "feed")
		)
		return
	if Catalog.is_energy(item):
		await _commit_care(
			"use_item", item_id, func() -> void: _fly_consumable_to_anima(icon_snapshot, "item")
		)
		return
	if Catalog.is_battle(item):
		if _busy:
			return
		if _battle_view.is_expedition_mode():
			await _expedition_controller.use_item(str(item.get("id", "")))
			return
		if _battle_view.is_team_mode():
			var team_session := _team_battle_view.session_data()
			if team_session.is_empty() or str(team_session.get("status", "")) != "active":
				return
			var team_pending := GameState.begin_team_battle_action(
				str(team_session.get("id", "")),
				int(team_session.get("turn_number", 1)),
				int(team_session.get("version", 1)),
				"item",
				str(item.get("id", ""))
			)
			await _submit_pending_team_battle(team_pending)
			return
		var session: Dictionary = _battle_view.session_data()
		if session.is_empty() or str(session.get("status", "")) != "active":
			return
		var pending := GameState.begin_battle_action(
			str(session.get("id", "")),
			int(session.get("turn_number", 1)),
			int(session.get("version", 1)),
			"item",
			str(item.get("id", ""))
		)
		await _submit_pending_battle(pending)


func _resume_pending_purchase() -> void:
	var pending := GameState.pending_purchase.duplicate(true)
	if pending.is_empty():
		return
	if await _send_pending_purchase(pending):
		_say(tr("FEEDBACK_PURCHASE"), true)


func _send_pending_purchase(pending: Dictionary) -> bool:
	var account_epoch := GameState.session_epoch
	var res := await Backend.purchase_item(
		str(pending.get("item_id", "")),
		int(pending.get("expected_price", 0)),
		str(pending.get("idempotency_key", ""))
	)
	if not Backend.response_applies(res, account_epoch):
		return false
	if res.ok:
		GameState.finish_purchase()
		var data := GameState.as_dict(res.data)
		if data.has("bits"):
			GameState.profile["bits"] = int(data.get("bits", 0))
			_refresh_header()
		if data.has("quantity"):
			_inventory = Catalog.with_quantity(
				_inventory, str(data.get("item_id", pending.get("item_id", ""))), int(data.get("quantity", 0))
			)
			_shop_sheet.set_catalog(_catalog, _inventory, int(GameState.profile.get("bits", 0)))
		else:
			_refresh_inventory()
		return true
	if res.code >= 400 and res.code < 500:
		GameState.finish_purchase()
	_say(_care_error_message(str(res.error)), true)
	return false


## Katalog di-fetch sekali per sesi app. Salinan cache boot cukup untuk mengecat
## Shop segera, tetapi harga dan item baru tetap harus datang dari server, jadi
## cache tidak boleh menghitung sebagai sudah tersinkron.
func _refresh_catalog() -> void:
	var account_epoch := GameState.session_epoch
	if not _catalog_synced:
		var catalog_res := await Backend.fetch_catalog()
		if not Backend.response_applies(catalog_res, account_epoch):
			return
		if catalog_res.ok and typeof(catalog_res.data) == TYPE_ARRAY:
			_catalog = catalog_res.data
			_catalog_synced = true
	await _refresh_inventory()


func _refresh_inventory() -> void:
	var account_epoch := GameState.session_epoch
	var inventory_res := await Backend.fetch_inventory()
	if not Backend.response_applies(inventory_res, account_epoch):
		return
	if inventory_res.ok and typeof(inventory_res.data) == TYPE_ARRAY:
		_inventory = inventory_res.data
		GameState.remember_boot_cache({"catalog": _catalog, "inventory": _inventory})
	if is_instance_valid(_shop_sheet):
		_shop_sheet.set_catalog(_catalog, _inventory, int(GameState.profile.get("bits", 0)))


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
	_cores_chip.set_inline(true)
	_cores_chip.set_name_text(tr("RESOURCE_CORES"))
	_cores_chip.set_interactive(true, tr("CORE_INFO_TITLE"))
	_bits_chip.set_inline(true)
	_bits_chip.set_name_text(tr("RESOURCE_BITS"))
	_bits_chip.set_interactive(true, tr("BITS_INFO_TITLE"))
	_bag_button.set_icon(BAG_ICON)
	_bag_button.set_value_text(tr("BAG_OPEN"))
	_bag_button.set_name_text("")
	_bag_button.set_interactive(true, tr("BAG_OPEN"))
	_shop_button.set_icon(SHOP_ICON)
	_shop_button.set_value_text(tr("SHOP_OPEN"))
	_shop_button.set_name_text("")
	_shop_button.set_interactive(true, tr("SHOP_OPEN"))


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
	_stop_evolution_chamber()
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
	if CareRules.is_evolving(_current_anima):
		_apply_evolution_chamber_for_row(
			_current_anima, _destination == BottomNav.HOME
		)
	else:
		_anima.visible = _destination == BottomNav.HOME and _anima.sprite_frames != null
	if _current_anima.is_empty():
		_set_home_shell_state(&"empty")


func _maybe_celebrate_level(previous_score: int, new_score: int) -> void:
	if previous_score < 0:
		return
	var new_level: int = CARE_RULES.leveled_up(previous_score, new_score)
	if new_level > 0:
		_celebrate_level_up(
			new_level,
			CARE_RULES.level_from_exp(previous_score),
			previous_score,
			new_score
		)


# ponytail: one shell dialog, not a per-screen fanfare. Plafon: no particles;
# committed form changes own the evolution chamber instead of Level-up copy.
func _celebrate_level_up(
	level: int,
	previous_level: int,
	previous_score: int = -1,
	new_score: int = -1,
	target_anima: Dictionary = {},
	modal_context: StringName = &"level_up"
) -> void:
	var anima := target_anima if not target_anima.is_empty() else _current_anima
	if previous_score < 0 or new_score < 0 or anima.is_empty():
		return
	_enqueue_outcome_dialog({
		"kind": "level_up",
		"level": level,
		"previous_level": previous_level,
		"previous_score": previous_score,
		"new_score": new_score,
		"target_anima": target_anima.duplicate(true),
		"modal_context": modal_context,
	})


func _present_level_up_outcome(dialog: Dictionary) -> void:
	var target := GameState.as_dict(dialog.get("target_anima"))
	var anima := target if not target.is_empty() else _current_anima
	if anima.is_empty():
		_active_outcome_dialog = {}
		call_deferred("_present_next_outcome_dialog")
		return
	_status_panel.visible = false
	Sfx.play(Sfx.CUE_LEVEL_UP)
	var anima_id := str(anima.get("id", ""))
	if target.is_empty():
		_home_view.pulse_progress()
	if (
		anima_id == str(_current_anima.get("id", ""))
		and is_instance_valid(_anima)
		and _anima.visible
	):
		_anima.celebrate_level_up()
	Input.vibrate_handheld(70)
	_show_level_up_stats(
		int(dialog.get("level", 1)),
		int(dialog.get("previous_level", 1)),
		int(dialog.get("previous_score", -1)),
		int(dialog.get("new_score", -1)),
		target,
		StringName(dialog.get("modal_context", &"level_up"))
	)


# Legacy snapshots (`evolution_version = 0`) still grow their form from the Level
# alone, so they get a body line. The hero slot stays a bare `Lv. N`: it is the
# largest text in the dialog and a form name beside it would wrap.
func _level_up_form_line(level: int, previous_level: int, form_row: Dictionary) -> String:
	if _evolution_enabled() and CareRules.evolution_version(form_row) >= 1:
		return ""
	if CARE_RULES.form_key(level) == CARE_RULES.form_key(previous_level):
		return ""
	return tr("LEVEL_UP_FORM_LINE") % LocaleManager.form_name(level)


func _show_level_up_stats(
	level: int,
	previous_level: int,
	previous_score: int,
	new_score: int,
	target_anima: Dictionary = {},
	modal_context: StringName = &"level_up"
) -> void:
	var anima := target_anima if not target_anima.is_empty() else _current_anima
	if previous_score < 0 or new_score < 0 or anima.is_empty():
		return
	var chained := modal_context == &"expedition_level_up"
	var stats := GameState.as_dict(anima.get("base_stats"))
	var lines: PackedStringArray = []
	var form_line := _level_up_form_line(level, previous_level, anima)
	if not form_line.is_empty():
		lines.append_array([form_line, ""])
	for key in STAT_ORDER:
		lines.append(
			tr("LEVEL_UP_STAT_ROW")
			% [
				tr(STAT_LABEL_KEYS[key]),
				LocaleManager.format_integer(CARE_RULES.grown_stat(stats.get(key, 0), previous_score)),
				LocaleManager.format_integer(CARE_RULES.grown_stat(stats.get(key, 0), new_score)),
			]
		)
	_modal_context = modal_context
	var action := (
		tr("EXPEDITION_CHOICE_CONTINUE") if chained else tr("CORE_INFO_CLOSE")
	)
	_shell_modal.open_info(
		tr("LEVEL_UP_TITLE") % LocaleManager.display_name(anima),
		"\n".join(lines),
		action,
		tr("LEVEL_UP_TO") % LocaleManager.format_integer(level)
	)


func _say(text: String, transient: bool = false) -> void:
	_toast_revision += 1
	var revision := _toast_revision
	_status.text = text
	_scan_view.set_status(text)
	_relayout_toast_after_minimum_update(revision)
	if _destination == BottomNav.SCAN:
		_status_panel.visible = false
	else:
		_status_panel.visible = true
		UiJuice.pop(_status_panel, 1.025)
	print(text)
	if transient and _status_panel.visible:
		_hide_toast_later(revision)


func _relayout_toast_after_minimum_update(revision: int) -> void:
	await get_tree().process_frame
	if revision == _toast_revision and is_instance_valid(_status_panel):
		_layout_for_viewport()


func _hide_toast_later(revision: int) -> void:
	await get_tree().create_timer(2.8).timeout
	if revision == _toast_revision and is_instance_valid(_status_panel):
		_status_panel.visible = false


func _seeker_header_text(profile: Dictionary) -> String:
	if GameState.is_anonymous():
		return tr("SEEKER_GUEST_LABEL")
	if profile_value_present(profile, &"seeker_name"):
		return str(profile.get("seeker_name"))
	return tr("SEEKER_UNNAMED")


func _refresh_header() -> void:
	var p := GameState.profile
	_brand.text = _seeker_header_text(p)
	if p.is_empty():
		_cores_chip.set_value_text(tr("VALUE_UNAVAILABLE"))
		_bits_chip.set_value_text(tr("VALUE_UNAVAILABLE"))
		_scan_view.set_cores(-1)
		_scan_view.set_sign_in_required(false)
		_bottom_nav.set_scan_emphasized(_destination != BottomNav.BATTLE)
		return
	var cores := int(p.get("genesis_cores", 0))
	var sign_in_required := _guest_scan_locked()
	_cores_chip.set_value_text(LocaleManager.format_integer(cores))
	_bits_chip.set_value_text(LocaleManager.format_integer(int(p.get("bits", 0))))
	_scan_view.set_cores(cores)
	_scan_view.set_sign_in_required(sign_in_required)
	_bottom_nav.set_scan_emphasized(
		cores > 0 and not sign_in_required and _destination != BottomNav.BATTLE and not _update_required
	)
	UiJuice.pop(_top_hud, 1.012)


func _apply_profile_refresh(profile_res: Dictionary) -> void:
	if not profile_res.ok or GameState.profile.is_empty():
		return
	var current := int(GameState.profile.get("genesis_cores", 0))
	var previous := int(profile_res.get("previous_genesis_cores", _last_known_cores))
	if previous >= 0 and current > previous:
		_say(tr("FEEDBACK_WEEKLY_CORE") % LocaleManager.format_integer(current - previous), true)
	_last_known_cores = current


func _ensure_client_version() -> bool:
	var config := await Backend.fetch_client_config()
	var min_version: Variant = GameState.client_config.get("min_client_version", {})
	if config.ok:
		min_version = GameState.client_config.get("min_client_version", min_version)
	if not ClientVersion.is_outdated(min_version):
		return true
	_update_required = true
	_set_home_shell_state(&"error")
	_anima.visible = false
	var required := int(GameState.as_dict(min_version).get(ClientVersion.platform_key(), 0))
	_shell_modal.open_info(
		tr("UPDATE_REQUIRED_TITLE"),
		tr("UPDATE_REQUIRED_BODY") % LocaleManager.format_integer(required),
		tr("UPDATE_REQUIRED_CLOSE")
	)
	return false


func _set_busy(busy: bool) -> void:
	_busy = busy
	# Layar loading dimiliki flag busy shell. Setiap transisi yang menampilkannya
	# sudah dikurung `_set_busy`, jadi tidak ada jalur error yang bisa
	# meninggalkannya menempel; menutup layar yang tidak tampil adalah no-op.
	if not busy:
		LoadingScreen.hide_screen()
	_scan_view.set_busy(busy)
	_battle_view.set_busy(busy)
	_team_battle_view.set_busy(busy)
	_home_view.set_busy(busy)
	_collection_view.set_busy(busy)
	_synthesis_view.set_busy(busy)
	_atlas_view.set_busy(busy)
	_details_view.set_busy(busy)
	_seeker_profile_view.set_busy(busy)
	_bottom_nav.set_busy(busy, _details_available())
	_bag_button.set_interactive(not busy, tr("BAG_OPEN"))
	_shop_button.set_interactive(not busy, tr("SHOP_OPEN"))
	if is_instance_valid(_shop_sheet):
		_shop_sheet.set_busy(busy)
	if is_instance_valid(_battle_pick_sheet):
		_battle_pick_sheet.set_busy(busy)
	if is_instance_valid(_seeker_onboarding_sheet) and _seeker_onboarding_sheet.visible:
		_seeker_onboarding_sheet.set_busy(busy)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _handle_back(false):
		get_viewport().set_input_as_handled()
		return
	_try_home_anima_tap(event)


func _handle_back(allow_quit: bool) -> bool:
	if is_instance_valid(_shell_modal) and _shell_modal.visible:
		_shell_modal.request_cancel()
		return true
	if is_instance_valid(_seeker_onboarding_sheet) and _seeker_onboarding_sheet.visible:
		_seeker_onboarding_sheet.close()
		return true
	if is_instance_valid(_menu_popover) and _menu_popover.visible:
		_menu_popover.close()
		return true
	if is_instance_valid(_seeker_menu_sheet) and _seeker_menu_sheet.visible:
		_seeker_menu_sheet.close()
		return true
	if is_instance_valid(_shop_sheet) and _shop_sheet.visible:
		_shop_sheet.close()
		return true
	if is_instance_valid(_battle_pick_sheet) and _battle_pick_sheet.handle_back():
		return true
	if (
		_destination == BottomNav.BATTLE
		and is_instance_valid(_expedition_controller)
		and _battle_view.is_expedition_mode()
		and _expedition_controller.handle_back()
	):
		return true
	if (
		_destination == BottomNav.BATTLE
		and is_instance_valid(_team_battle_view)
		and _team_battle_view.handle_back()
	):
		return true
	if (
		_destination == BottomNav.BATTLE
		and not _battle_view.is_team_mode()
		and not _battle_view.is_expedition_mode()
		and _battle_view.can_leave_result()
	):
		_leave_battle()
		return true
	if _collection_view.is_sheet_open():
		_collection_view.close_sheet()
		return true
	if _destination == SYNTHESIS_DEST:
		_close_synthesis_lab()
		return true
	if is_instance_valid(_atlas_view) and _atlas_view.is_detail_open():
		_atlas_view.close_detail()
		return true
	if _close_open_bottom_sheet():
		return true
	if _destination == ANIMA_PROFILE_DEST and _details_view.is_action_menu_open():
		_details_view.close_action_menu()
		return true
	if _destination == ANIMA_PROFILE_DEST:
		_switch_destination(_profile_return_destination)
		return true
	if _destination in [SEEKER_PROFILE_DEST, ATLAS_DEST]:
		_return_from_overlay()
		return true
	if _destination != BottomNav.HOME:
		_switch_destination(BottomNav.HOME)
		return true
	if allow_quit:
		get_tree().quit()
		return true
	return false


func _close_open_bottom_sheet() -> bool:
	var nodes: Array[Node] = find_children("*", "", true, false)
	for index in range(nodes.size() - 1, -1, -1):
		var sheet := nodes[index] as UiBottomSheet
		if sheet != null and sheet.is_visible_in_tree():
			sheet.close()
			return true
	return false


func _cores_remaining() -> int:
	if GameState.profile.is_empty():
		return -1
	return int(GameState.profile.get("genesis_cores", 0))


func _guest_scan_locked() -> bool:
	return (
		GameState.is_anonymous()
		and profile_value_present(GameState.profile, &"guest_scan_used_at")
	)


static func profile_value_present(profile: Dictionary, key: StringName) -> bool:
	var value: Variant = profile.get(key)
	return value != null and (typeof(value) != TYPE_STRING or not str(value).is_empty())


func _is_immersive_arena() -> bool:
	if not is_instance_valid(_battle_view) or not _battle_view.visible:
		return false
	if (
		is_instance_valid(_expedition_view)
		and _expedition_view.visible
		and _expedition_view.is_combat_open()
	):
		return true
	if (
		is_instance_valid(_team_battle_view)
		and _team_battle_view.visible
		and _team_battle_view.is_arena_open()
	):
		return true
	return _battle_view.is_duel_arena_open()


func _music_cue() -> StringName:
	if _destination != BottomNav.BATTLE or not _is_immersive_arena():
		return &"lobby"
	if (
		is_instance_valid(_expedition_view)
		and _expedition_view.visible
		and _expedition_view.is_combat_open()
		and is_instance_valid(_expedition_controller)
	):
		return &"boss" if _expedition_controller.encounter_kind() == "boss" else &"battle"
	if (
		is_instance_valid(_team_battle_view)
		and _team_battle_view.visible
		and _team_battle_view.is_arena_open()
	):
		return &"boss" if _team_battle_view.session_kind() == "boss" else &"battle"
	return &"battle"


func _on_immersive_arena_changed(_open: bool) -> void:
	_sync_shop_chrome()
	_layout_for_viewport()


func _sync_shop_chrome() -> void:
	if not is_instance_valid(_shop_button):
		return
	var immersive := _is_immersive_arena()
	if is_instance_valid(_top_hud):
		_top_hud.visible = not immersive
	if is_instance_valid(_bottom_nav):
		_bottom_nav.visible = not immersive
	var show_chrome := _destination == BottomNav.HOME and not immersive
	var shop_locked := GameState.shop_locked()
	if is_instance_valid(_bottom_section):
		_bottom_section.visible = show_chrome
	if is_instance_valid(_bag_button):
		_bag_button.visible = show_chrome
	_shop_button.visible = show_chrome
	_shop_button.modulate = Color(1.0, 1.0, 1.0, 0.45) if shop_locked else Color.WHITE
	if (
		is_instance_valid(_shop_sheet)
		and _shop_sheet.visible
		and (not show_chrome or (shop_locked and _shop_sheet.is_shop_open()))
	):
		_shop_sheet.close()


func _place_toast(insets: Vector4) -> void:
	if not is_instance_valid(_status_panel) or not is_instance_valid(_top_hud):
		return
	var hud_h := maxf(_top_hud.size.y, _top_hud.get_combined_minimum_size().y)
	var top := HUD_TOP_PAD + insets.y + hud_h + TOAST_GAP
	var height := _status_panel.get_combined_minimum_size().y
	_status_panel.offset_top = top
	_status_panel.offset_bottom = top + height


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
		if _register_sleep_tap():
			await _commit_care("wake")


## Cara kedua membangunkan Anima selain tombol Wake: sejumlah tap acak (3–6,
## di-roll ulang tiap sesi tidur supaya tidak bisa dihafal) di atas sprite.
## Mengembalikan true tepat pada tap yang membangunkan. Diam total selama
## evolving/dormant/`pending_care` masih terbang, supaya tap berulang tidak
## memuntahkan toast "care pending" di atas toast wake yang sedang jalan.
func _register_sleep_tap() -> bool:
	if not _is_sleeping(_current_anima):
		_reset_wake_taps()
		return false
	if (
		CareRules.is_evolving(_current_anima)
		or _has_timestamp(_current_anima.get("dormant_since"))
		or not GameState.pending_care.is_empty()
	):
		return false
	_wake_taps += 1
	if _wake_taps_target <= 0:
		_wake_taps_target = randi_range(WAKE_TAPS_MIN, WAKE_TAPS_MAX)
	if _wake_taps < _wake_taps_target:
		return false
	_reset_wake_taps()
	return true


func _reset_wake_taps() -> void:
	_wake_taps = 0
	_wake_taps_target = 0


## Kilau Guard hidup sekitar satu detik sementara --screenshot menunggu tiga,
## jadi demo mengulanginya supaya capture selalu jatuh di tengah sapuan.
func _loop_guard_shimmer_demo() -> void:
	var sprite := _battle_view.find_child("BattlePlayerSprite", true, false) as AnimaPresenter
	if not is_instance_valid(sprite):
		return
	var loop := Timer.new()
	loop.wait_time = AnimaPresenter.GUARD_SHIMMER_SEC * 0.6
	loop.autostart = true
	add_child(loop)
	loop.timeout.connect(sprite.guard_shimmer)
	sprite.guard_shimmer()


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


func _run_evolve_chamber_demo() -> void:
	var demo := _current_anima.duplicate(true) if not _current_anima.is_empty() else {
		"id": "evolve-chamber-demo",
		"nickname": "Velumi",
		"status": "evolving",
	}
	demo["status"] = "evolving"
	_switch_destination(BottomNav.HOME)
	_home_view.set_evolution(demo)
	_update_hud_identity()
	_evolution_chamber_active = true
	_anima.visible = false
	_stage.visible = true
	_incubator.align_visual_center(_stage.global_position + Vector2(0.0, -80.0))
	_incubator.start_evolution()
	_say(tr("EVOLUTION_CHAMBER_STATUS"), true)


func _run_evolve_demo() -> void:
	var demo := _current_anima.duplicate(true) if not _current_anima.is_empty() else {
		"id": "evolve-demo",
		"nickname": "Velumi",
		"status": "ready",
		"stage": 1,
		"evolution_version": 1,
		"care_score": 150,
		"species_key": "demo",
		"color_bucket": "cyan",
		"element": "spark",
		"rarity": 3,
		"base_stats": {"hp": 74, "atk": 62, "def": 58, "spd": 81, "special": 77},
		"strike_name": "Spark Tap",
		"surge_name": "Voltage Rush",
		"strike_effect_id": "burn",
		"surge_effect_id": "barrier",
	}
	demo["evolution_version"] = 1
	demo["care_score"] = 150
	demo["stage"] = 1
	demo["status"] = "ready"
	_profile_anima = demo.duplicate(true)
	_switch_destination(ANIMA_PROFILE_DEST)
	_details_view.set_evolution_enabled(true)
	_details_view.set_anima(demo, _thumbnail_for(demo))
	_say(tr("COLLECTION_READY_EVOLVE"), true)


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


## Membuka Bag lalu mensimulasikan tap "Feed"/"Use" pada baris pertama yang
## cocok, lewat `_use_catalog_item()` yang sama dengan tap sungguhan --
## sengaja bukan mensintesis tap tombol, supaya jalur snapshot-ikon dan
## penutupan sheet ikut teruji apa adanya. Alat verifikasi visual: perangkat
## uji layarnya mati dan `adb shell input` diblokir HyperOS, jadi flag ini
## plus `--screenshot` adalah satu-satunya cara melihat animasi ini mendarat
## sebelum masuk APK.
func _run_feed_fly_demo(kind: String) -> void:
	_switch_destination(BottomNav.HOME)
	await get_tree().process_frame
	_open_bag("food" if kind == "feed" else "item")
	await get_tree().create_timer(0.3).timeout
	var predicate := (
		Callable(Catalog, "is_food") if kind == "feed" else Callable(Catalog, "is_energy")
	)
	for row in _catalog:
		var item: Dictionary = row if typeof(row) == TYPE_DICTIONARY else {}
		if predicate.call(item):
			await _use_catalog_item(item)
			print("%s fly demo: used item_id=%s" % [kind, item.get("id", "")])
			return
	print("%s fly demo: no matching catalog item loaded" % kind)


func _run_synthesis_history_demo(show_help: bool, scroll_history: bool = false) -> void:
	var history := {
		"mode": "balanced",
		"resonance": 74,
		"source_a": {
			"id": "history-demo-a", "name": "Chromvein", "selected_stage": 1,
		},
		"source_b": {
			"id": "history-demo-b", "name": "Playtron", "selected_stage": 1,
		},
		"inheritance_summary": {
			"source_a": "Contributes the primary sleek, dark metallic vehicle body silhouette, robust structure, and chrome accents, along with the concept of wheeled mobility.",
			"source_b": "Provides the distinct digital screen face with pixelated features, the teal color palette for the screen, and the subtle spark/hovering effect.",
			"coherence": "The creature seamlessly integrates the robust, polished vehicle form with the playful, digital screen face, creating a smart car Hatchling that is both sturdy and expressive.",
		},
	}
	var demo := {
		"id": "",
		"nickname": "Gearbit Racer",
		"species_key": "synthesis_result",
		"status": "ready",
		"stage": 1,
		"element": "metal",
		"secondary_element": "spark",
		"rarity": 3,
		"care_score": 150,
		"base_stats": {"hp": 50, "atk": 55, "def": 45, "spd": 60, "special": 65},
		"strike_name": "Chrome Rush",
		"surge_name": "Pixel Overdrive",
		"synthesis_history": history,
	}
	_switch_destination(ANIMA_PROFILE_DEST, demo)
	_details_view.set_evolution_enabled(false)
	_details_view.set_synthesis_enabled(true)
	_details_view.set_anima(demo, null)
	call_deferred("_finish_synthesis_history_demo", show_help, scroll_history)


func _open_profile_menu_demo() -> void:
	await get_tree().create_timer(0.5).timeout
	var demo := _profile_anima.duplicate(true)
	demo["id"] = "profile-menu-demo"
	_details_view.set_anima(demo, null)
	_details_view.set_busy(false)
	_details_view.call("_toggle_action_menu")


func _finish_synthesis_history_demo(show_help: bool, scroll_history: bool) -> void:
	await get_tree().process_frame
	_details_view.set_gallery_status({"available": true, "published": false})
	_details_view.set_synthesis_history_loading(true)
	if show_help:
		var help := _details_view.find_child("SynthesisHistoryHelp", true, false) as Button
		help.pressed.emit()
	elif scroll_history:
		await get_tree().process_frame
		var scroll := _details_view.find_child("DetailsScroll", true, false) as ScrollContainer
		var history_panel := _details_view.find_child(
			"SynthesisHistoryPanel", true, false
		) as Control
		scroll.scroll_vertical = maxi(0, int(history_panel.position.y) - 24)


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
	_switch_destination(ANIMA_PROFILE_DEST, demo)
	_refresh_stats()
	if show_help:
		_show_details_help(tr("STAT_SPD"), tr("STAT_SPD_HELP"))


func _run_atlas_demo() -> void:
	var rows: Array[Dictionary] = [
		{
			"form_id": "atlas-demo-scanned",
			"source_kind": "player",
			"discovery_source": "scanned",
			"discovered": true,
			"display_name": "Veridian",
			"element": "plant",
			"secondary_element": "stone",
			"stage": 1,
		},
		{
			"form_id": "atlas-demo-duel",
			"source_kind": "player",
			"discovery_source": "duel",
			"discovered": true,
			"display_name": "Sunhound",
			"element": "flame",
			"secondary_element": "fauna",
			"stage": 2,
		},
		{
			"form_id": "atlas-demo-expedition",
			"source_kind": "expedition",
			"discovery_source": "expedition",
			"discovered": true,
			"display_name": "Gumdrop",
			"element": "food",
			"secondary_element": null,
			"stage": 3,
		},
		{
			"form_id": "atlas-demo-hidden",
			"source_kind": "expedition",
			"discovery_source": "",
			"discovered": false,
			"display_name": "???",
			"element": "",
			"secondary_element": null,
			"stage": 1,
		},
	]
	var placeholder := PlaceholderSheet.build()
	var idle := AtlasView._crop_idle(placeholder["image"], placeholder["manifest"])
	var texture := ImageTexture.create_from_image(idle)
	_atlas_view.set_busy(true)
	_switch_destination(ATLAS_DEST)
	_atlas_view.show_demo(rows, texture)


## Kartu kedua sengaja dibiarkan tanpa art supaya slot yang sudah dipesan
## sebelum PNG-nya turun ikut terlihat saat layar ini diperiksa.
func _run_trophy_demo() -> void:
	var rows: Array = []
	for index in 4:
		rows.append({"expedition_trophies": {
			"id": "trophy-demo-%d" % index,
			"display_name": "Sugarfold Core %d" % (index + 1),
		}})
	_seeker_profile_view.set_profile(GameState.profile, null)
	_seeker_profile_view.set_trophies(rows)
	var swatch := Image.create(240, 240, false, Image.FORMAT_RGBA8)
	swatch.fill(Color(0.52, 0.24, 0.34))
	for index in 4:
		if index != 1:
			_seeker_profile_view.set_trophy_art(
				"trophy-demo-%d" % index,
				ImageTexture.create_from_image(swatch)
			)
	_switch_destination(SEEKER_PROFILE_DEST)
	var scroll := _seeker_profile_view.find_child("Scroll", true, false) as ScrollContainer
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


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
	status: String = "active",
	training: bool = false,
	effectiveness: float = 0.0,
	player_height_cm: float = BattleScale.BODY_HEIGHT_REFERENCE_CM,
	bot_height_cm: float = BattleScale.BODY_HEIGHT_REFERENCE_CM
) -> void:
	var placeholder := PlaceholderSheet.build()
	var texture := ImageTexture.create_from_image(placeholder["image"])
	var loaded := AnimaLoader.build(texture, placeholder["manifest"])
	loaded["render_metrics"] = {
		"reference_height_px": 300,
		"reference_width_px": 220,
	}
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
			"body_height_cm": player_height_cm,
		},
		"bot_snapshot": {
			"anima_id": "battle-demo-bot",
			"element": "flow",
			"stage": 1,
			"body_height_cm": bot_height_cm,
		},
		"daily_reward": {
			"earned": 7 if training else (3 if status == "won" else 2),
			"limit": 3,
			"remaining": 0 if training or status == "won" else 1,
			"rewarded": status == "won" and not training,
			"bits_earned": 100 if training and status == "won" else (24 if status == "won" else 8),
			"bits_limit": 100,
			"bits_remaining": 0 if training and status == "won" else 76,
		},
		"last_reward": {
			"bits": 0 if training else 8,
			"care_score": 0 if training else 4,
			"battle_wins": 0 if training else 1,
		},
		"reward_tier": "even",
		"reward_bits": 8,
		"state": {
			"status": status,
			"player": {"hp": 162, "max_hp": 240, "momentum": 2},
			"bot": {"hp": 118, "max_hp": 228, "momentum": 1},
		},
	}
	_switch_destination(BottomNav.BATTLE, {}, false)
	_battle_view.show_duel_mode()
	_battle_view.set_session(session, loaded, loaded)
	_sync_shop_chrome()
	if not is_zero_approx(effectiveness):
		_battle_view.call("_show_effectiveness", effectiveness)


## Visual gate untuk CTA result yang terpagari Energy: menang, lalu companion-nya
## kehabisan Energy, jadi Choose Anima plus alasannya bisa diperiksa gratis.
func _run_battle_blocked_demo() -> void:
	_run_battle_demo("won")
	var drained := _current_anima.duplicate(true)
	drained["care"] = {"hunger": 70.0, "energy": 8.0, "hygiene": 70.0}
	_battle_view.set_companion(drained)


## Visual gate untuk result Team: dua tombol dalam satu baris, lalu anggota yang
## kehabisan Energy menukar Try Again menjadi Edit Team.
func _run_team_result_demo() -> void:
	var demo := _run_team_battle_demo()
	var roster: Array[Dictionary] = []
	var members: Array[Dictionary] = []
	var player_roster := GameState.as_dict(
		GameState.as_dict(demo["session"].get("state")).get("player")
	).get("roster") as Array
	for slot in player_roster.size():
		var fighter := GameState.as_dict(player_roster[slot])
		var anima_id := str(fighter.get("anima_id", ""))
		members.append({"slot": slot, "anima_id": anima_id})
		roster.append({
			"id": anima_id,
			"nickname": str(fighter.get("name", "")),
			"status": "ready",
			"care": {"hunger": 70.0, "energy": 4.0 if slot == 1 else 60.0, "hygiene": 70.0},
		})
	_team_battle_view.set_lobby({"id": "team-demo-team", "members": members}, {}, [], false)
	var session: Dictionary = demo["session"]
	session["status"] = "won"
	session["state"]["status"] = "won"
	session["last_reward"] = {
		"bits": 8,
		"anima_exp": [{"anima_id": members[0].get("anima_id"), "exp": 3}],
	}
	_team_battle_view.set_session(session, demo["art"])
	_team_battle_view.set_roster(roster)


func _run_team_battle_demo(boss: bool = false) -> Dictionary:
	_team_battle_demo_active = true
	var placeholder := PlaceholderSheet.build()
	var loaded := AnimaLoader.build(
		ImageTexture.create_from_image(placeholder["image"]),
		placeholder["manifest"]
	)
	var player_roster: Array[Dictionary] = []
	var opponent_roster: Array[Dictionary] = []
	var player_snapshots: Array[Dictionary] = []
	var opponent_snapshots: Array[Dictionary] = []
	var art: Dictionary = {}
	var player_heights: Array[int] = [175, 90, 50, 75]
	var boss_names: Array[String] = ["Fudge Fang", "Syrup Sentry", "Gumdrop Grunt", "Nimbelisk"]
	var boss_heights: Array[int] = [135, 170, 95, 130]
	for slot in 4:
		var player_id := "team-demo-player-%d" % slot
		var opponent_id := "team-demo-opponent-%d" % slot
		player_roster.append({
			"anima_id": player_id,
			"name": ["Velumi", "Mugora", "Treadle", "Monstera"][slot],
			"slot": slot,
			"hp": 162 - slot * 8,
			"max_hp": 180,
			"momentum": 2,
			"momentum_max": 3,
			"body_height_cm": player_heights[slot],
			"strike_name": "Prism Jab",
			"surge_name": "Neon Burst",
		})
		opponent_roster.append({
			"anima_id": opponent_id,
			"name": (
				boss_names[slot]
				if boss
				else ["Byte Scout", "Moss Guard", "Pebble Dash", "Paper Kite"][slot]
			),
			"slot": slot,
			"hp": 154 - slot * 6,
			"max_hp": 172,
			"momentum": 3,
			"momentum_max": 3,
			"body_height_cm": boss_heights[slot] if boss else 110 + slot * 20,
			"is_ace": boss and slot == 3,
			"strike_name": "Pixel Jab",
			"surge_name": "Static Arc",
		})
		player_snapshots.append({"anima_id": player_id})
		opponent_snapshots.append({"anima_id": opponent_id})
		art[player_id] = loaded
		art[opponent_id] = loaded
	if boss:
		var frames: SpriteFrames = loaded.get("frames")
		var seeker_texture := frames.get_frame_texture("idle", 0)
		var seeker_size := Vector2i(seeker_texture.get_size())
		var seeker_poses: Dictionary = {}
		for pose in BossSeekerSheet.KNOWN_POSES:
			seeker_poses[pose] = {"region": [0, 0, seeker_size.x, seeker_size.y]}
		art["boss_seeker"] = BossSeekerSheet.build(seeker_texture, {
			"version": 1,
			"frame_size": [seeker_size.x, seeker_size.y],
			"poses": seeker_poses,
			"render_metrics": {
				"reference_height_px": 300,
				"reference_width_px": 180,
			},
		})
	var session := {
		"id": "boss-demo" if boss else "team-demo",
		"kind": "boss" if boss else "team",
		"status": "active",
		"turn_number": 4,
		"version": 3,
		"item_used_id": null,
		"player_snapshot": player_snapshots,
		"opponent_snapshot": opponent_snapshots,
		"state": {
			"status": "active",
			"turn": 4,
			"player": {
				"active_slot": 0,
				"forced_switch": false,
				"item_used": false,
				"roster": player_roster,
			},
			"opponent": {
				"active_slot": 0,
				"forced_switch": false,
				"item_used": false,
				"roster": opponent_roster,
			},
		},
	}
	if boss:
		session["zone_attempt"] = 1
		session["boss_seeker"] = {
			"display_name": "The Confectioner",
			"body_height_cm": 165,
			"portrait_pose": "profile",
			"dialogue": {
				"boss_intro": "Show me what belongs in the archive.",
				"last_anima": "Nimbelisk, preserve what the others could not.",
				"victory": "Your improvisation belongs in the record.",
				"defeat": "The archive stands.",
			},
		}
	_switch_destination(BottomNav.BATTLE, {}, false)
	_battle_view.show_team_mode()
	_team_battle_view.set_session(session, art)
	_sync_shop_chrome()
	return {"session": session, "art": art}


func _run_boss_scale_demo() -> void:
	_run_sugarworks_zone_demo(3)


func _run_sugarworks_zone_demo(
	zone: int,
	hide_seeker: bool = false,
	player_height_override: int = -1,
	opponent_height_override: int = -1
) -> void:
	var index := clampi(zone, 1, 3)
	var chapter := _sugarworks_asset_dir()
	var player := _demo_player_sheet()
	var opponent_slug := "animas/sugarworks-gumdrop"
	var opponent_name := "Gumdrop Grunt"
	var opponent_height := 95
	var with_seeker := index == 3 and not hide_seeker
	if index == 2:
		opponent_slug = "animas/sugarworks-caramel"
		opponent_name = "Caramel Clad"
		opponent_height = 155
	elif index == 3:
		opponent_slug = "animas/sugarworks-fudge"
		opponent_name = "Fudge Fang"
		opponent_height = 135
	var opponent := _load_local_anima_sheet(chapter, opponent_slug)
	var seeker := _load_local_seeker_sheet(chapter) if with_seeker else {}
	var zone_tex := AnimaLoader.load_sheet_texture(
		chapter.path_join("zones/zone-%d.png" % index), true
	)
	if not bool(player.get("ok", false)) or not bool(opponent.get("ok", false)):
		push_error("sugarworks-zone-demo: aset Sugarworks tidak ketemu di %s" % chapter)
		return
	if with_seeker and seeker.is_empty():
		push_error("sugarworks-zone-demo: Boss Seeker tidak ketemu di %s" % chapter)
		return
	var demo := _run_team_battle_demo(with_seeker)
	var session: Dictionary = demo.get("session", {})
	var art: Dictionary = {}
	var player_id := str(session["state"]["player"]["roster"][0].get("anima_id", ""))
	var opponent_id := str(session["state"]["opponent"]["roster"][0].get("anima_id", ""))
	art[player_id] = player
	art[opponent_id] = opponent
	if with_seeker:
		art["boss_seeker"] = seeker
	if zone_tex != null:
		art["arena_background"] = zone_tex
	session["state"]["player"]["roster"][0]["name"] = str(player.get("demo_name", "Licorice"))
	session["state"]["player"]["roster"][0]["body_height_cm"] = (
		player_height_override
		if player_height_override > 0
		else int(player.get("demo_height_cm", 150))
	)
	session["state"]["opponent"]["roster"][0]["name"] = opponent_name
	session["state"]["opponent"]["roster"][0]["body_height_cm"] = (
		opponent_height_override if opponent_height_override > 0 else opponent_height
	)
	session["id"] = "sugarworks-zone-%d-%d-%d" % [
		index,
		int(session["state"]["player"]["roster"][0]["body_height_cm"]),
		int(session["state"]["opponent"]["roster"][0]["body_height_cm"]),
	]
	session["turn_number"] = 2
	session["state"]["turn"] = 2
	_team_battle_view.set_session(session, art)
	_team_battle_view.set_arena_location(tr("EXPEDITION_ARENA_LOCATION") % ["The Sugarworks", index])


func _sugarworks_asset_dir() -> String:
	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var root := game_dir.get_base_dir()
	var v4 := root.path_join("backend/chapters/the-sugarworks/v4/assets")
	if FileAccess.file_exists(v4.path_join("zones/zone-3.png")):
		return v4
	return root.path_join("backend/chapters/the-sugarworks/v3/assets")


func _demo_player_sheet() -> Dictionary:
	var anima_id := str(_current_anima.get("id", ""))
	var stage := CareRules.committed_stage(_current_anima)
	if not anima_id.is_empty() and GameState.has_sprite_for_anima(anima_id, stage):
		var loaded := AnimaLoader.load_from_manifest(GameState.manifest_path_for_anima(anima_id, stage))
		if bool(loaded.get("ok", false)):
			loaded["demo_name"] = str(_current_anima.get("nickname", "Veridian"))
			loaded["demo_height_cm"] = 150
			return loaded
	var fallback := _load_local_anima_sheet(_sugarworks_asset_dir(), "animas/sugarworks-licorice")
	if bool(fallback.get("ok", false)):
		fallback["demo_name"] = "Licorice Lash"
		fallback["demo_height_cm"] = 170
	return fallback


func _load_local_anima_sheet(chapter_dir: String, slug: String) -> Dictionary:
	var manifest_path := chapter_dir.path_join("%s/manifest.json" % slug)
	var sheet_path := chapter_dir.path_join("%s/sheet.png" % slug)
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(sheet_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var texture := AnimaLoader.load_sheet_texture(sheet_path)
	if texture == null:
		return {}
	return AnimaLoader.build(texture, parsed)


func _load_local_seeker_sheet(chapter_dir: String) -> Dictionary:
	var manifest_path := chapter_dir.path_join("boss/manifest.json")
	var sheet_path := chapter_dir.path_join("boss/confectioner-seeker.png")
	if not FileAccess.file_exists(manifest_path) or not FileAccess.file_exists(sheet_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var texture := AnimaLoader.load_sheet_texture(sheet_path)
	if texture == null:
		return {}
	return BossSeekerSheet.build(texture, parsed)


func _run_boss_ace_demo() -> void:
	var demo := _run_team_battle_demo(true)
	await get_tree().process_frame
	if _team_battle_view.handle_back():
		await get_tree().process_frame
	var session: Dictionary = demo.get("session", {}).duplicate(true)
	var art: Dictionary = demo.get("art", {})
	session["state"]["opponent"]["active_slot"] = 3
	var ace: Dictionary = session["state"]["opponent"]["roster"][3]
	_team_battle_view.play_events([{
		"type": "final_ace",
		"actor": "opponent",
		"to_slot": 3,
		"anima_id": ace.get("anima_id", ""),
		"name": ace.get("name", ""),
	}, {
		"type": "switch",
		"actor": "opponent",
		"to_slot": 3,
		"forced": true,
		"name": ace.get("name", ""),
	}, {
		"type": "ace_passive",
		"actor": "opponent",
		"passive_name": "Final Confection",
		"copy": "Final Confection: Nimbelisk enters with +1 PP.",
	}], session, art)
	await get_tree().process_frame


func _run_expedition_demo() -> void:
	_switch_destination(BottomNav.BATTLE, {}, false)
	_battle_view.show_expedition_mode()
	_expedition_view.set_team({"id": "expedition-demo-team"})
	_expedition_view.set_run({
		"id": "expedition-demo",
		"status": "active",
		"zone": 1,
		"supplies": 7,
		"team_id": "expedition-demo-team",
		"available_node_ids": ["battle-1", "recovery-1"],
		"party_state": [
			{"name": "Velumi", "hp": 154, "max_hp": 180},
			{"name": "Mugora", "hp": 132, "max_hp": 160},
			{"name": "Treadle", "hp": 118, "max_hp": 170},
			{"name": "Monstera", "hp": 149, "max_hp": 175},
		],
		"zone_map": {"nodes": [
			{"id": "battle-1", "kind": "battle", "depth": 1},
			{"id": "recovery-1", "kind": "recovery", "depth": 1},
			{"id": "elite-2", "kind": "elite", "depth": 2},
			{"id": "cache-2", "kind": "cache", "depth": 2},
			{"id": "boss-4", "kind": "boss", "depth": 4},
		]},
	})
	_sync_shop_chrome()


func _run_expedition_builder_demo() -> void:
	var placeholder := PlaceholderSheet.build()
	var loaded := AnimaLoader.build(
		ImageTexture.create_from_image(placeholder["image"]),
		placeholder["manifest"]
	)
	var frames: SpriteFrames = loaded.get("frames")
	_expedition_view.set_thumbnail_provider(func(row: Dictionary) -> Texture2D:
		var pose := CareRules.collection_pose(row, "demo-idle")
		return frames.get_frame_texture(pose, 0)
	)
	_switch_destination(BottomNav.BATTLE, {}, false)
	_battle_view.show_expedition_mode()
	_expedition_view.set_builder([
		{"id": "demo-idle", "nickname": "Sunhound", "status": "ready", "element": "food",
			"care": {"energy": 100.0, "hunger": 80.0, "hygiene": 80.0}},
		{"id": "demo-hungry", "nickname": "Veridian", "status": "ready", "element": "plant",
			"care": {"energy": 100.0, "hunger": 20.0, "hygiene": 80.0}},
		{"id": "demo-dirty", "nickname": "Playtron", "status": "ready", "element": "spark",
			"care": {"energy": 100.0, "hunger": 80.0, "hygiene": 20.0}},
		{"id": "demo-sleep", "nickname": "Hydron", "status": "ready", "element": "flow",
			"care": {"energy": 5.0, "hunger": 80.0, "hygiene": 80.0}},
		{"id": "demo-dormant", "nickname": "Mugshot", "status": "ready", "element": "ceramic",
			"dormant_since": "2026-08-15T00:00:00Z",
			"care": {"energy": 80.0, "hunger": 0.0, "hygiene": 0.0}},
	], {"members": [{"slot": 0, "anima_id": "demo-idle"}]})
	_sync_shop_chrome()


func _run_chapter_announcement_demo() -> void:
	_switch_destination(BottomNav.HOME)
	GameState.profile["seeker_name"] = "Sunhound"
	_apply_chapter_announcements({
		"unread": [{
			"chapter_id": "chapter-demo",
			"version_id": "chapter-demo-v1",
			"summary": {
				"title": "The Sugarworks",
				"description": "Follow the candy trails and challenge the Confectioner.",
			},
		}],
		"home_popup": [{
			"chapter_id": "chapter-demo",
			"version_id": "chapter-demo-v1",
			"summary": {
				"title": "The Sugarworks",
				"description": "Follow the candy trails and challenge the Confectioner.",
			},
		}],
	})
	_maybe_show_chapter_popup()


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
