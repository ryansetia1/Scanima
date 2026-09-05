class_name TeamBattleView
extends Control

signal back_requested
signal save_team_requested(anima_ids: Array[String])
signal defense_requested(publish: bool, anima_ids: Array[String])
signal refresh_requested(team_id: String)
signal start_requested(team_id: String, candidate_id: String)
signal action_requested(action: String, switch_to_slot: int)
signal item_picker_requested
signal forfeit_requested
signal retry_requested
signal arena_open_changed(open: bool)

## Baris terakhir Boss Seeker dan reveal Trophy menunggu tap pemain, sementara
## `_apply_session_state()` bukan coroutine. Sinyal ini yang membiarkan
## `play_events()` menahan reward/level-up sampai dialognya benar-benar habis.
signal _boss_result_settled

const SURGE_COST := 1
const ACTION_CUE_SEC := 1.4
const INTRO_OPENING_BEAT_SEC := 0.4
const INTRO_COMMAND_BEAT_SEC := 0.42
const INTRO_GAMEPLAY_TRANSITION_SEC := 0.32
const GAMEPLAY_CHROME_GAP := 16.0
const SEEKER_SHOT_X := 0.83
## Figur pemain berdiri sejauh dari tepinya seperti Boss Seeker berdiri dari
## tepi seberang, jadi angkanya diturunkan alih-alih ditulis ulang.
const PLAYER_SEEKER_SHOT_X := 1.0 - SEEKER_SHOT_X
## Seeker Avatar bukan petarung, jadi ia tidak punya `body_height_cm`
## authoritative. 165 cm adalah tinggi manusia yang dipakai catatan skala arena,
## dan `fighter_scale()` menormalkan ke tinggi layar — figur pemain dan Boss
## Seeker setinggi 165 cm karena itu digambar sama besar walau sheet-nya beda.
##
## ponytail: satu tinggi untuk seluruh roster. Plafonnya figur yang memang
## dimaksudkan beda tinggi (automaton jangkung, figur anak); kalau itu datang,
## taruh tingginya di manifest `SeekerRoster` dan baca dari sana, bukan di sini.
const PLAYER_SEEKER_HEIGHT_CM := 165.0
const CAMERA_MIN_ZOOM := 0.30
const CAMERA_MAX_ZOOM := 1.30
const CAMERA_LARGE_ANIMA_ZOOM := 0.72
const CAMERA_TOP_PAD_RATIO := 0.05
const CAMERA_SIDE_PAD_RATIO := 0.05
const CAMERA_FIGHTER_GAP_RATIO := 0.025
const CAMERA_BACKGROUND_MAX_SCALE := 1.55
# Expedition keeps its approved chapter framing. Team Battle's static arena
# uses a higher foot line and a gentler background crop.
const TEAM_GROUND_Y_RATIO := BattleScale.GROUND_Y_RATIO
const TEAM_BACKGROUND_MAX_SCALE := 1.0
const TEAM_STATIC_BACKGROUND_CAMERA_MAX := 1.08
const TEAM_STATIC_BACKGROUND_CAMERA_FLOOR := 0.60
const TEAM_STATIC_BACKGROUND_REFIT_STRENGTH := 0.25
const MIN_TEAM_SIZE := 2
const MAX_TEAM_SIZE := 4
const CAMERA_REFIT_SEC := 0.48
const DIM := Color(1.0, 1.0, 1.0, 0.42)
const BATTLE_EVENT := preload("res://scripts/battle_event.gd")
const BACKGROUND_DOF_SHADER: Shader = preload("res://shaders/battle_background_dof.gdshader")
const TEAM_BACKGROUND: Texture2D = preload(
	"res://assets/backgrounds/team_battle_background.png"
)
const TEAM_BACKGROUND_LANDSCAPE: Texture2D = preload(
	"res://assets/backgrounds/team_battle_landscape_background.png"
)
const CARE_RULES: GDScript = preload("res://scripts/care_rules.gd")
const SEEKER_PRESENTER := preload("res://scripts/seeker_presenter.gd")
const BOSS_SEEKER_DIALOG := preload("res://scripts/boss_seeker_dialog.gd")
const SEEKER_SHEET := preload("res://scripts/seeker_sheet.gd")
const COMMIT_COLORS := {
	"strike": Color(0.28, 0.9, 1.0, 1.0),
	"surge": Color(1.0, 0.82, 0.4, 1.0),
	"guard": Color(0.66, 0.48, 1.0, 1.0),
	"item": Color(1.0, 0.9, 0.45, 1.0),
	"switch": Color(0.42, 0.9, 0.82, 1.0),
}

@onready var _back: Button = %TeamBackButton
@onready var _header: HBoxContainer = $Column/Header
@onready var _loading: VBoxContainer = %TeamLoading
@onready var _loading_label: Label = %TeamLoadingLabel
@onready var _builder_scroll: ScrollContainer = %TeamBuilderScroll
@onready var _builder: VBoxContainer = %TeamBuilder
@onready var _builder_meta: Label = %TeamBuilderMeta
@onready var _roster_list: ItemList = %TeamRosterList
@onready var _builder_back: Button = %TeamBuilderBack
@onready var _save_button: Button = %TeamSaveButton
@onready var _lobby_scroll: ScrollContainer = %TeamLobbyScroll
@onready var _lobby: VBoxContainer = %TeamLobby
@onready var _lineup: Label = %TeamLineup
@onready var _reward_status: Label = %TeamRewardStatus
@onready var _rival_list: ItemList = %TeamRivalList
@onready var _edit_button: Button = %TeamEditButton
@onready var _defense_button: Button = %TeamDefenseButton
@onready var _refresh_button: Button = %TeamRefreshButton
@onready var _start_button: Button = %TeamStartButton
@onready var _arena: VBoxContainer = %TeamArena
@onready var _battle_chrome: Control = %TeamChrome
@onready var _battle_overlay: Control = %TeamOverlay
@onready var _result_panel: PanelContainer = %TeamResultPanel
@onready var _arena_hud: PanelContainer = %ArenaHud
@onready var _arena_dock: PanelContainer = %TeamDock
@onready var _turn: Label = %TeamTurn
@onready var _forfeit: Button = %TeamForfeitButton
@onready var _player_slots: Label = %TeamPlayerSlots
@onready var _opponent_slots: Label = %TeamOpponentSlots
@onready var _player_name: Label = %TeamPlayerName
@onready var _opponent_name: Label = %TeamOpponentName
@onready var _player_hp: ProgressBar = %TeamPlayerHp
@onready var _opponent_hp: ProgressBar = %TeamOpponentHp
@onready var _player_hp_value: Label = %TeamPlayerHpValue
@onready var _opponent_hp_value: Label = %TeamOpponentHpValue
@onready var _battle_stage: Control = %TeamBattleStage
@onready var _arena_background: TextureRect = %TeamArenaBackground
@onready var _effectiveness: Control = %TeamEffectiveness
@onready var _event_plate: PanelContainer = %TeamEventPlate
@onready var _effectiveness_label: Label = %TeamEffectivenessLabel
@onready var _damage: Label = %TeamDamage
@onready var _player_anchor: Node2D = %TeamPlayerAnchor
@onready var _opponent_anchor: Node2D = %TeamOpponentAnchor
@onready var _player_sprite: AnimaPresenter = %TeamPlayerSprite
@onready var _opponent_sprite: AnimaPresenter = %TeamOpponentSprite
@onready var _feedback: Label = %TeamFeedback
@onready var _actions: VBoxContainer = %TeamActions
@onready var _attack_button: Button = %TeamAttackButton
@onready var _special_button: Button = %TeamSpecialButton
@onready var _guard_button: Button = %TeamGuardButton
@onready var _item_button: Button = %TeamItemButton
@onready var _switch_button: Button = %TeamSwitchButton
@onready var _switch_panel: VBoxContainer = %TeamSwitchPanel
@onready var _switch_title: Label = %TeamSwitchTitle
@onready var _switch_cancel: Button = %TeamSwitchCancel
@onready var _switch_buttons: Array[Button] = [
	%TeamSwitchSlot0, %TeamSwitchSlot1, %TeamSwitchSlot2, %TeamSwitchSlot3,
]
@onready var _result: VBoxContainer = %TeamResult
@onready var _result_title: Label = %TeamResultTitle
@onready var _result_body: Label = %TeamResultBody
@onready var _retry: Button = %TeamRetryButton
@onready var _result_actions: HBoxContainer = %TeamResultActions
@onready var _leave: Button = %TeamLeaveButton

var _roster: Array = []
var _result_body_base := ""
var _retry_edits_team := false
var _team: Dictionary = {}
var _candidates: Array = []
var _daily_reward: Dictionary = {}
var _session: Dictionary = {}
var _art_cache: Dictionary = {}
var _selected_candidate := ""
var _defense_published := false
var _busy := false
var _expedition_mode := false
var _arena_location := ""
var _thumbnail_provider: Callable
var _queued_action := ""
var _command_tween: Tween
var _effectiveness_tween: Tween
var _layout_tween: Tween
var _action_commits: Dictionary = {}
var _switch_meters: Array[ProgressBar] = []
var _player_portal: IncubatorEffect
var _opponent_portal: IncubatorEffect
var _player_shadow: Sprite2D
var _opponent_shadow: Sprite2D
var _seeker: SEEKER_PRESENTER
var _seeker_shadow: Sprite2D
var _player_seeker: SEEKER_PRESENTER
var _player_seeker_shadow: Sprite2D
var _player_seeker_loaded: Dictionary = {}
var _impact: BattleImpact
var _fighter_layer: Node2D
var _background_session_id := ""
var _background_pan := 0.5
var _uses_static_background := false
var _seeker_dialog: BOSS_SEEKER_DIALOG
var _seeker_loaded: Dictionary = {}
var _spoken: Dictionary = {}
var _spoken_session := ""
var _intro_started := false
var _intro_pending_summon := false
var _opening_intro_pending := false
var _opening_intro_running := false
var _opening_intro_revision := 0
var _gameplay_framing := true
var _opening_transition: Tween
var _background_ground_offset := 0.0
var _opening_chrome_shown := true
var _command_dialogue_used := false
var _final_ace_pending := false
var _boss_result_pending := false
var _switch_overlay: Control
var _switch_sheet: PanelContainer


func _ready() -> void:
	_back.tooltip_text = tr("ACTION_BACK")
	_builder_back.flat = true
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_list.fixed_icon_size = Vector2i(96, 96)
	_roster_list.max_columns = 1
	_roster_list.fixed_column_width = 0
	_back.pressed.connect(_on_back)
	_roster_list.connect("selection_changed", _update_builder)
	_builder_back.pressed.connect(_leave_builder)
	_save_button.pressed.connect(_save_team)
	_rival_list.item_selected.connect(_select_candidate)
	_edit_button.pressed.connect(_edit_team)
	_defense_button.visible = false
	_refresh_button.pressed.connect(_refresh_candidates)
	_start_button.pressed.connect(_start_candidate)
	_attack_button.pressed.connect(_request_action.bind("strike", -1))
	_special_button.pressed.connect(_request_action.bind("surge", -1))
	_guard_button.pressed.connect(_request_action.bind("guard", -1))
	_item_button.pressed.connect(item_picker_requested.emit)
	_switch_button.pressed.connect(_open_switch_picker.bind(false))
	_switch_cancel.pressed.connect(_close_switch_picker)
	_forfeit.pressed.connect(forfeit_requested.emit)
	_retry.pressed.connect(_on_retry_pressed)
	_leave.pressed.connect(back_requested.emit)
	resized.connect(_layout_full_bleed_arena)
	for slot in _switch_buttons.size():
		_switch_buttons[slot].pressed.connect(_request_switch.bind(slot))
	_battle_stage.resized.connect(_position_fighters)
	var background_material := ShaderMaterial.new()
	background_material.shader = BACKGROUND_DOF_SHADER
	background_material.set_shader_parameter("camera_zoom", 1.0)
	_arena_background.material = background_material
	_player_sprite.set_facing(1.0)
	_opponent_sprite.set_facing(-1.0)
	_player_sprite.z_index = 1
	_opponent_sprite.z_index = 1
	_player_anchor.z_index = 3
	_opponent_anchor.z_index = 2
	_player_sprite.pose_changed.connect(func(_pose: String) -> void: _sync_shadow("player"))
	_opponent_sprite.pose_changed.connect(func(_pose: String) -> void: _sync_shadow("opponent"))
	_action_commits = {
		"strike": _make_commit(_attack_button, COMMIT_COLORS["strike"]),
		"surge": _make_commit(_special_button, COMMIT_COLORS["surge"]),
		"guard": _make_commit(_guard_button, COMMIT_COLORS["guard"]),
		"item": _make_commit(_item_button, COMMIT_COLORS["item"]),
		"switch": _make_commit(_switch_button, COMMIT_COLORS["switch"]),
	}
	for button in _switch_buttons:
		_switch_meters.append(_make_switch_meter(button))
	_mount_switch_overlay()
	_sync_action_layout()
	_feedback.visible = false
	_player_portal = _make_portal(_player_anchor)
	_opponent_portal = _make_portal(_opponent_anchor)
	_player_shadow = _make_ground_shadow(_player_anchor)
	_opponent_shadow = _make_ground_shadow(_opponent_anchor)
	_seeker = SEEKER_PRESENTER.new()
	_seeker.name = "BossSeeker"
	_impact = BattleImpact.new()
	_impact.mount(_battle_stage, _arena_background)
	_fighter_layer = Node2D.new()
	_fighter_layer.name = "FighterLayer"
	_impact.add_foreground(_fighter_layer)
	_opponent_anchor.reparent(_fighter_layer)
	_player_anchor.reparent(_fighter_layer)
	_fighter_layer.add_child(_seeker)
	_seeker_shadow = _make_ground_shadow(_fighter_layer)
	_player_seeker = SEEKER_PRESENTER.new()
	_player_seeker.name = "PlayerSeeker"
	# Sheet Seeker digambar menghadap kiri, arah Boss Seeker memandang dari sisi
	# seberang. Figur pemain berdiri di sisi kiri, jadi ia dibalik supaya
	# komposisinya terbaca sebagai dua pihak yang berhadapan.
	_player_seeker.flip_h = true
	# Lantai awalnya di belakang; `_apply_player_seeker_layer()` yang memindahkan
	# figur ke depan begitu Anima pemain cukup tinggi untuk menelan siluetnya.
	_player_seeker.z_index = BattleScale.PLAYER_SEEKER_Z_BEHIND
	_fighter_layer.add_child(_player_seeker)
	# Dua bayangan bersaudara di layer yang sama; tanpa nama sendiri yang kedua
	# di-serialkan diam-diam jadi "GroundShadow2".
	_player_seeker_shadow = _make_ground_shadow(_fighter_layer)
	_player_seeker_shadow.name = "PlayerSeekerShadow"
	_seeker_dialog = BOSS_SEEKER_DIALOG.new()
	_seeker_dialog.name = "BossSeekerDialog"
	_battle_overlay.add_child(_seeker_dialog)
	_layout_full_bleed_arena.call_deferred()


func _layout_full_bleed_arena() -> void:
	if not is_instance_valid(_battle_stage) or not is_inside_tree():
		return
	var viewport_rect := get_viewport().get_visible_rect()
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var top_left := inverse * viewport_rect.position
	var bottom_right := inverse * viewport_rect.end
	_battle_stage.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_battle_stage.position = top_left
	_battle_stage.size = bottom_right - top_left
	_layout_battle_chrome()
	_position_fighters.call_deferred()


func _layout_battle_chrome() -> void:
	if not is_instance_valid(_battle_chrome) or not is_instance_valid(_arena_dock):
		return
	_battle_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dock_height := _arena_dock.get_combined_minimum_size().y
	_arena_dock.offset_top = -dock_height
	_arena_dock.offset_bottom = 0.0


func _layout_result_panel() -> void:
	if not is_instance_valid(_result_panel) or not _result_panel.visible:
		return
	var panel_height := _result_panel.get_combined_minimum_size().y
	_result_panel.offset_top = -panel_height
	_result_panel.offset_bottom = 0.0


func open_mode() -> void:
	visible = true


func close_mode() -> void:
	if not _session.is_empty() and str(_session.get("status", "")) == "active":
		return
	visible = false
	_switch_panel.visible = false
	_emit_arena_open()


func is_open() -> bool:
	return visible


func is_arena_open() -> bool:
	return (
		is_instance_valid(_arena)
		and _arena.visible
		and not _session.is_empty()
	)


func set_thumbnail_provider(provider: Callable) -> void:
	_thumbnail_provider = provider


## Roster authoritative terbaru, supaya result CTA tahu siapa yang kehabisan
## Energy tanpa membuka builder lebih dulu.
func set_roster(roster: Array) -> void:
	_roster = roster.duplicate(true)
	if _result_actions.visible and not _session.is_empty():
		_apply_result_actions()


## Seeker Avatar pemain: cermin Boss Seeker di sisi pemain, tanpa panel dialog —
## ia hadir, tapi tidak pernah bicara.
##
## Art-nya ter-bundel (ADR-0002), jadi tidak ada unduhan yang bisa gagal dan
## `SeekerRoster` mengembalikan `SpriteFrames` yang sama untuk slug yang sama.
## Perbandingan itulah yang membuat pemanggilan ulang — shell menyegarkan figur
## ini setiap kali profil berubah, termasuk saat Bits bergerak — tidak me-reset
## pose di tengah turn.
func set_player_avatar(loaded: Dictionary) -> void:
	if not is_instance_valid(_player_seeker):
		return
	if _player_seeker.has_sheet() and _player_seeker.sprite_frames == loaded.get("frames"):
		return
	_player_seeker_loaded = loaded.duplicate(true) if bool(loaded.get("ok", false)) else {}
	_player_seeker.apply(loaded)
	# Bukan hanya `_position_player_seeker()`: kolom figurnya ikut menentukan
	# bingkai kamera, jadi arena harus dibingkai ulang saat figur itu datang.
	_position_fighters()


func set_expedition_mode(enabled: bool) -> void:
	_expedition_mode = enabled
	_sync_action_layout()
	_retry.text = tr("EXPEDITION_RETURN_MAP") if enabled else tr("TEAM_RETRY")
	_leave.visible = _result_actions.visible and not enabled
	_sync_header()
	_sync_location_chrome()
	_position_fighters.call_deferred()


func _sync_action_layout() -> void:
	if not is_instance_valid(_attack_button) or not is_instance_valid(_item_button):
		return
	var primary_row := _attack_button.get_parent() as HBoxContainer
	var support_row := _item_button.get_parent() as HBoxContainer
	if primary_row == null or support_row == null:
		return
	var target := primary_row if _uses_expedition_framing() else support_row
	if _guard_button.get_parent() != target:
		_guard_button.reparent(target)
	if _uses_expedition_framing():
		target.move_child(_guard_button, -1)
	else:
		target.move_child(_guard_button, 0)


func set_arena_location(text: String) -> void:
	_arena_location = text.strip_edges()
	_sync_location_chrome()


func handle_back() -> bool:
	if not visible:
		return false
	if is_instance_valid(_seeker_dialog) and _seeker_dialog.is_open():
		_seeker_dialog.dismiss()
		return true
	if _close_switch_picker():
		return true
	if _builder.visible:
		_leave_builder()
		return true
	if _session.is_empty() or str(_session.get("status", "")) != "active":
		back_requested.emit()
		return true
	return false


func _on_back() -> void:
	handle_back()


func set_loading(message_key: String = "TEAM_LOADING") -> void:
	_show_only(_loading)
	_loading_label.text = tr(message_key)
	_back.disabled = _busy


func set_builder(roster: Array, existing_team: Dictionary = {}) -> void:
	_session = {}
	_roster = roster.duplicate(true)
	_team = existing_team.duplicate(true)
	_roster_list.clear()
	for value in _roster:
		var row := GameState.as_dict(value)
		if row.is_empty():
			continue
		var unavailable := _team_member_unavailable(row)
		var label := tr("TEAM_ROSTER_ROW") % [
			LocaleManager.display_name(row),
			LocaleManager.level_label(
				CareRules.level_from_exp(int(row.get("care_score", 0)))
			),
			tr(_team_member_status_key(unavailable)),
			LocaleManager.element_compact(row),
		]
		var thumbnail: Texture2D = (
			_thumbnail_provider.call(row) if _thumbnail_provider.is_valid() else null
		)
		_roster_list.add_item(label, thumbnail, true)
		var index := _roster_list.item_count - 1
		_roster_list.set_item_metadata(index, row)
		_roster_list.set_item_disabled(index, not unavailable.is_empty())
		if not unavailable.is_empty():
			_roster_list.set_item_icon_modulate(index, DIM)
	var roster_list := _roster_list as TeamRosterList
	if roster_list != null:
		roster_list.set_chosen_order(
			roster_list.indices_for_anima_ids(_team_member_ids(_team))
		)
	_show_only(_builder)
	_update_builder()


func set_lobby(
	team: Dictionary,
	daily_reward: Dictionary,
	candidates: Array,
	defense_published: bool
) -> void:
	_session = {}
	_team = team.duplicate(true)
	_daily_reward = daily_reward.duplicate(true)
	_candidates = candidates.duplicate(true)
	_defense_published = defense_published
	_selected_candidate = ""
	_lineup.text = _team_lineup_text(_team)
	_reward_status.text = _daily_reward_text(_daily_reward)
	var blocked := _team_blocked_key()
	if not blocked.is_empty():
		_reward_status.text += "\n" + tr(blocked)
	_rival_list.clear()
	for value in _candidates:
		var candidate := GameState.as_dict(value)
		var roster := _as_array(candidate.get("roster"))
		var lead := (
			str(GameState.as_dict(roster[0]).get("name", tr("TEAM_RIVAL")))
			if not roster.is_empty() else tr("TEAM_RIVAL")
		)
		_rival_list.add_item(tr("TEAM_RIVAL_ROW") % [
			lead,
			LocaleManager.format_integer(roster.size()),
			_tier_label(str(candidate.get("reward_tier", ""))),
			LocaleManager.format_integer(int(candidate.get("reward_bits", 0))),
		])
		_rival_list.set_item_metadata(_rival_list.item_count - 1, candidate)
	_defense_button.text = tr(
		"TEAM_DEFENSE_UNPUBLISH" if _defense_published else "TEAM_DEFENSE_PUBLISH"
	)
	_show_only(_lobby)
	_update_lobby_actions()


func show_retreat_banner() -> void:
	_show_banner(tr("BATTLE_RETREATING"), BattleView.CUE_COLOR, false, BattleView.ToastType.WARNING)


func set_error(error_code: String) -> void:
	_effectiveness.visible = false
	_clear_action_commit()
	_show_only(_loading)
	_loading_label.text = _error_copy(error_code)
	_set_result_actions_visible(true)
	_retry_edits_team = false
	_back.disabled = false


func set_busy(busy: bool) -> void:
	_busy = busy or _opening_intro_pending or _opening_intro_running
	if not _busy and is_instance_valid(_seeker_dialog) and _seeker_dialog.is_open():
		_busy = true
	if not _busy:
		_clear_action_commit()
	_back.disabled = _busy
	_builder_back.disabled = _busy
	var selected_count := _selected_roster_ids().size()
	_save_button.disabled = (
		_busy or selected_count < MIN_TEAM_SIZE or selected_count > MAX_TEAM_SIZE
	)
	_update_lobby_actions()
	_update_arena_actions()
	if not _busy and _forced_switch():
		_open_switch_picker(true)


func set_result_continue_enabled(enabled: bool) -> void:
	_retry.disabled = not enabled


func set_session(
	session: Dictionary,
	art_cache: Dictionary = {},
	fresh_intro: bool = false
) -> void:
	_cancel_opening_intro()
	_session = session.duplicate(true)
	_sync_action_layout()
	_art_cache.merge(art_cache, true)
	_reset_spoken_if_needed()
	_sync_background_pan()
	_show_only(_arena)
	_apply_arena_background(art_cache)
	_present_seeker()
	var opening_requested := (
		fresh_intro
		and str(_session.get("status", "active")) == "active"
		and not _is_boss_encounter()
	)
	_gameplay_framing = not opening_requested
	_opening_intro_pending = opening_requested
	if opening_requested:
		_busy = true
	if _should_boss_intro():
		_intro_started = true
		_intro_pending_summon = true
		_busy = true
	_apply_session_state()
	_set_opening_chrome_visible(not opening_requested)
	_update_arena_actions()
	if _intro_pending_summon:
		_begin_boss_intro()


func play_opening_intro() -> void:
	if not _opening_intro_pending:
		return
	_opening_intro_pending = false
	_opening_intro_running = true
	_busy = true
	_update_arena_actions()
	var revision := _opening_intro_revision
	await _event_pause(INTRO_OPENING_BEAT_SEC)
	if not _opening_intro_is_active(revision):
		return
	if not await _summon_opening_side("opponent", revision):
		return
	_set_player_seeker_pose("switch_command")
	await _event_pause(INTRO_COMMAND_BEAT_SEC)
	if not _opening_intro_is_active(revision):
		return
	if not await _summon_opening_side("player", revision):
		return
	if not await _transition_opening_to_gameplay(revision):
		return
	_opening_intro_running = false
	_busy = false
	_restore_player_seeker_idle()
	_apply_session_state()
	_sync_shadow("player")
	_sync_shadow("opponent")
	_update_arena_actions()


func _summon_opening_side(side: String, revision: int) -> bool:
	var sprite := _sprite_for(side)
	var portal := _portal_for(side)
	if not is_instance_valid(sprite):
		return _opening_intro_is_active(revision)
	_align_portal(side)
	if is_instance_valid(portal):
		await portal.start_portal()
	if not _opening_intro_is_active(revision):
		return false
	if is_instance_valid(portal):
		portal.burst()
	if sprite.sprite_frames != null:
		await sprite.summon_reveal()
	else:
		sprite.visible = true
	if not _opening_intro_is_active(revision):
		return false
	_sync_shadow(side)
	return true


func _opening_intro_is_active(revision: int) -> bool:
	return (
		_opening_intro_running
		and revision == _opening_intro_revision
		and str(_session.get("status", "")) == "active"
		and not _is_boss_encounter()
	)


func _cancel_opening_intro() -> void:
	if is_instance_valid(_impact):
		_impact.cancel()
	if _opening_transition != null and _opening_transition.is_valid():
		_opening_transition.kill()
	_opening_transition = null
	var was_active := _opening_intro_pending or _opening_intro_running
	_opening_intro_revision += 1
	_opening_intro_pending = false
	_opening_intro_running = false
	if was_active:
		_busy = false
	if is_instance_valid(_player_portal):
		_player_portal.stop()
	if is_instance_valid(_opponent_portal):
		_opponent_portal.stop()


func _transition_opening_to_gameplay(revision: int) -> bool:
	var from_layer_position := _fighter_layer.position
	var from_layer_scale := _fighter_layer.scale
	var from_background_zoom := _background_camera_zoom()
	var from_background_offset := _background_ground_offset
	_prepare_opening_chrome_fade()
	_gameplay_framing = true
	_position_fighters()
	var target_layer_position := _fighter_layer.position
	var target_layer_scale := _fighter_layer.scale
	var target_background_zoom := _background_camera_zoom()
	var target_background_offset := _background_ground_offset
	_fighter_layer.position = from_layer_position
	_fighter_layer.scale = from_layer_scale
	_set_background_camera_zoom(from_background_zoom)
	_set_background_ground_offset(from_background_offset)
	_opening_transition = create_tween()
	_opening_transition.set_parallel(true)
	_opening_transition.set_trans(Tween.TRANS_SINE)
	_opening_transition.set_ease(Tween.EASE_IN_OUT)
	_opening_transition.tween_property(
		_fighter_layer, "position", target_layer_position, INTRO_GAMEPLAY_TRANSITION_SEC
	)
	_opening_transition.tween_property(
		_fighter_layer, "scale", target_layer_scale, INTRO_GAMEPLAY_TRANSITION_SEC
	)
	_opening_transition.tween_method(
		_set_background_camera_zoom,
		from_background_zoom,
		target_background_zoom,
		INTRO_GAMEPLAY_TRANSITION_SEC
	)
	_opening_transition.tween_method(
		_set_background_ground_offset,
		from_background_offset,
		target_background_offset,
		INTRO_GAMEPLAY_TRANSITION_SEC
	)
	_opening_transition.tween_method(
		_set_opening_chrome_alpha, 0.0, 1.0, INTRO_GAMEPLAY_TRANSITION_SEC
	)
	await _event_pause(INTRO_GAMEPLAY_TRANSITION_SEC)
	if not _opening_intro_is_active(revision):
		return false
	_opening_transition = null
	_fighter_layer.position = target_layer_position
	_fighter_layer.scale = target_layer_scale
	_set_background_camera_zoom(target_background_zoom)
	_set_background_ground_offset(target_background_offset)
	_set_opening_chrome_visible(true)
	return true


func _prepare_opening_chrome_fade() -> void:
	_arena_hud.visible = true
	_opening_chrome_shown = true
	_sync_location_chrome()
	_set_opening_chrome_alpha(0.0)


func _set_opening_chrome_alpha(alpha: float) -> void:
	_battle_chrome.modulate.a = alpha


func _set_opening_chrome_visible(shown: bool) -> void:
	_opening_chrome_shown = shown
	_arena_hud.visible = true
	_set_opening_chrome_alpha(1.0 if shown else 0.0)
	_arena_dock.mouse_filter = (
		Control.MOUSE_FILTER_STOP if shown else Control.MOUSE_FILTER_IGNORE
	)
	_sync_location_chrome()
	if not shown:
		for button in [
			_attack_button, _special_button, _guard_button,
			_item_button, _switch_button, _forfeit,
		]:
			(button as Button).release_focus()


func session_data() -> Dictionary:
	return _session.duplicate(true)


func session_kind() -> String:
	return str(_session.get("kind", ""))


func _apply_arena_background(art_cache: Dictionary) -> void:
	var texture: Variant = art_cache.get("arena_background", _art_cache.get("arena_background"))
	_uses_static_background = not _expedition_mode and not texture is Texture2D
	if _uses_static_background:
		texture = _static_team_background()
	_arena_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arena_background.stretch_mode = TextureRect.STRETCH_SCALE
	_arena_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_arena_background.texture = texture if texture is Texture2D else null
	_arena_background.visible = texture is Texture2D


func _sync_static_background_variant() -> void:
	if not _uses_static_background:
		return
	var background := _static_team_background()
	if _arena_background.texture != background:
		_arena_background.texture = background


func _static_team_background() -> Texture2D:
	return (
		TEAM_BACKGROUND_LANDSCAPE
		if static_background_uses_landscape(_battle_stage.size)
		else TEAM_BACKGROUND
	)


static func static_background_uses_landscape(stage_size: Vector2) -> bool:
	return stage_size.x > stage_size.y


func begin_action(action: String) -> void:
	if _busy and _queued_action == action:
		return
	_busy = true
	_show_action_commit(action)
	BattleImpact.command_haptic()
	_update_arena_actions()


## Log dianimasikan dari session yang sedang tampil — `_play_switch()` membaca nama
## dan HP anggota yang masuk dari sana — lalu mendarat di `next_session`. Pemanggil
## karena itu tidak boleh memasang session akhir turn sebelum memutar log-nya.
## Replay authoritative sesudah prediksi menyimpang adalah satu pengecualiannya:
## arena masih menampilkan prediksi, jadi ia mengirim `from_session` berisi state
## sebelum turn supaya Summon tidak membaca HP satu turn terlalu maju.
func play_events(
	events: Array,
	next_session: Dictionary,
	art_cache: Dictionary = {},
	from_session: Dictionary = {}
) -> void:
	_art_cache.merge(art_cache, true)
	var physical_feedback := from_session.is_empty()
	if not physical_feedback:
		_impact.cancel()
	if not from_session.is_empty():
		# Sengaja tanpa repaint: bar yang tampil ditimpa absolut oleh event log ini,
		# dan memasangnya lewat set_session() akan terlihat sebagai arena mundur.
		_session = from_session.duplicate(true)
	set_busy(true)
	var played_switch := false
	await _announce_initiative(events)
	for value in events:
		var event := GameState.as_dict(value)
		match str(event.get("type", "")):
			"guard":
				var guard_actor := str(event.get("actor", ""))
				var bracing := _sprite_for(guard_actor)
				if is_instance_valid(bracing):
					bracing.guard_shimmer()
				await _present_banner(
					tr("BATTLE_EVENT_GUARD") % _actor_name(guard_actor),
					BattleView.CUE_COLOR,
					false,
					BattleView.ToastType.SUCCESS
				)
				await _hide_effectiveness()
			"item":
				var item_actor := str(event.get("actor", "player"))
				await _present_banner(
					tr("BATTLE_EVENT_ITEM") % _actor_name(item_actor),
					BattleView.CUE_COLOR,
					false,
					BattleView.ToastType.GENERAL
				)
				var item_sprite := _sprite_for(item_actor)
				if is_instance_valid(item_sprite):
					item_sprite.care_feedback("item")
				await _present_banner(
					BattleView.item_banner_text(event),
					BattleView.EFFECTIVE_COLOR,
					true,
					BattleView.ToastType.SUCCESS
				)
				await _hide_effectiveness()
			"final_ace":
				await _cue_final_ace()
			"switch":
				played_switch = true
				var switch_actor := str(event.get("actor", ""))
				if switch_actor == "opponent" and not _final_ace_pending:
					await _cue_seeker_command("first_switch", "switch_command")
				elif switch_actor == "player":
					_set_player_seeker_pose("switch_command")
				await _play_switch(event)
				if switch_actor == "player":
					_restore_player_seeker_idle()
				elif switch_actor == "opponent" and not _final_ace_pending:
					_restore_seeker_idle()
			"ace_passive":
				await _play_ace_passive(event)
				_final_ace_pending = false
				_restore_seeker_idle()
			"attack":
				var attack_actor := str(event.get("actor", ""))
				var attack_action := str(event.get("action", ""))
				var command_pose := (
					"special_command" if attack_action == "surge" else "attack_command"
				)
				if attack_actor == "opponent":
					await _cue_seeker_command(
						"first_special" if attack_action == "surge" else "first_attack",
						command_pose
					)
				elif attack_actor == "player":
					_set_player_seeker_pose(command_pose)
				await _play_attack(event, physical_feedback)
			"knockout":
				var side := str(event.get("actor", ""))
				_faint(side)
				var player_ko := side == "player"
				# Kalau KO ini menghabiskan seluruh tim (bukan sekadar satu member
				# yang masih bisa di-switch), sinkronkan pose figur pemain sekarang
				# juga -- jangan tunggu set_session() di akhir play_events().
				var final_status := str(next_session.get("status", "active"))
				if player_ko and final_status == "lost":
					_set_player_seeker_pose("defeat")
				elif not player_ko and final_status == "won":
					_set_player_seeker_pose("victory")
					_player_sprite.victory_celebration(_active_player_level())
				await _present_banner(
					tr("BATTLE_EVENT_KO") % _actor_name(side),
					BattleView.DAMAGE_COLOR if player_ko else BattleView.WIN_COLOR,
					true,
					BattleView.ToastType.ERROR if player_ko else BattleView.ToastType.SUCCESS
				)
				# Hold the faint so a KO is readable before the replacement picker.
				await _event_pause(1.2)
				await _hide_effectiveness()
			"timeout":
				await _present_banner(tr("BATTLE_EVENT_TIMEOUT"), BattleView.DAMAGE_COLOR, false, BattleView.ToastType.WARNING)
				await _hide_effectiveness()
			"finished":
				await _present_banner(
					tr("BATTLE_EVENT_FINISHED"),
					BattleView.COMPLETE_COLOR,
					false,
					BattleView.ToastType.GENERAL
				)
				await _hide_effectiveness()
			"move_effect", "status_tick", "status_expired":
				var normalized := BATTLE_EVENT.normalized(event)
				_apply_effect_hp_event(normalized, str(next_session.get("status", "active")))
				if str(normalized.get("type", "")) == "status_tick":
					_impact.play_event(normalized, physical_feedback)
				var plate := BATTLE_EVENT.plate_text(normalized)
				if not plate.is_empty():
					await _present_banner(plate, BattleView.CUE_COLOR, false, BattleView.ToastType.GENERAL)
					await _hide_effectiveness()
	if _final_ace_pending:
		_final_ace_pending = false
		_restore_seeker_idle()
	var switch_background_zoom := _background_camera_zoom()
	var switch_background_offset := _background_ground_offset
	set_session(next_session)
	if played_switch and _uses_static_background:
		_set_background_camera_zoom(switch_background_zoom)
		_set_background_ground_offset(switch_background_offset)
	if _boss_result_pending:
		await _boss_result_settled
	set_busy(false)


func _apply_effect_hp_event(event: Dictionary, final_status: String = "active") -> void:
	if not event.has("target_hp"):
		return
	var side := str(event.get("target", event.get("actor", "")))
	if side == "bot":
		side = "opponent"
	if side not in ["player", "opponent"]:
		return
	var party := _party(side)
	var active_slot := int(party.get("active_slot", 0))
	var event_slot := int(event.get("target_slot", event.get("actor_slot", active_slot)))
	if event_slot != active_slot:
		return
	var hp := int(event.get("target_hp", 0))
	var bar := _player_hp if side == "player" else _opponent_hp
	var value := _player_hp_value if side == "player" else _opponent_hp_value
	BattleView.apply_hp_bar_state(bar, float(hp), bar.max_value)
	value.text = LocaleManager.format_ratio(hp, int(bar.max_value))
	if hp <= 0:
		_faint(side)
		if side == "player" and final_status == "lost":
			_set_player_seeker_pose("defeat")
		elif side == "opponent" and final_status == "won":
			_set_player_seeker_pose("victory")
			_player_sprite.victory_celebration(_active_player_level())


func _show_only(panel: Control) -> void:
	if is_instance_valid(_impact):
		_impact.cancel()
	for child in [_loading, _builder, _lobby, _arena]:
		(child as Control).visible = child == panel
	_builder_scroll.visible = panel == _builder
	_lobby_scroll.visible = panel == _lobby
	_result.visible = false
	_set_result_actions_visible(false)
	_sync_header()
	_emit_arena_open()


func _sync_header() -> void:
	# Arena is a full-bleed fight. Back/title only belong on builder/lobby.
	_header.visible = not _expedition_mode and _session.is_empty()
	_sync_location_chrome()


func _sync_location_chrome() -> void:
	var show := (
		_opening_chrome_shown
		and _expedition_mode
		and _arena.visible
		and not _session.is_empty()
		and not _arena_location.is_empty()
	)
	_turn.text = _arena_location
	_turn.visible = show


func _update_builder() -> void:
	var count := _selected_roster_ids().size()
	_builder_meta.text = tr("TEAM_BUILDER_META") % [
		tr("TEAM_BUILDER_COUNT") % [
			LocaleManager.format_integer(count),
			LocaleManager.format_integer(MAX_TEAM_SIZE),
		],
		tr("TEAM_ROSTER_LEAD_HINT"),
	]
	_save_button.disabled = _busy or count < MIN_TEAM_SIZE or count > MAX_TEAM_SIZE


func _selected_roster_ids() -> Array[String]:
	var ids: Array[String] = []
	var roster_list := _roster_list as TeamRosterList
	if roster_list == null:
		return ids
	for index in roster_list.get_chosen_indices_ordered():
		var row := GameState.as_dict(_roster_list.get_item_metadata(index))
		var anima_id := str(row.get("id", ""))
		if not anima_id.is_empty():
			ids.append(anima_id)
	return ids


func _save_team() -> void:
	var ids := _selected_roster_ids()
	if _busy or ids.size() < MIN_TEAM_SIZE or ids.size() > MAX_TEAM_SIZE:
		return
	save_team_requested.emit(ids)


func _edit_team() -> void:
	set_builder(_roster, _team)


func _leave_builder() -> void:
	if _busy:
		return
	if str(_team.get("id", "")).is_empty():
		back_requested.emit()
		return
	set_lobby(_team, _daily_reward, _candidates, _defense_published)


func _toggle_defense() -> void:
	if _busy:
		return
	defense_requested.emit(not _defense_published, _team_member_ids(_team))


func _refresh_candidates() -> void:
	if _busy:
		return
	refresh_requested.emit(str(_team.get("id", "")))


func _select_candidate(index: int) -> void:
	if index < 0 or index >= _rival_list.item_count:
		return
	var candidate := GameState.as_dict(_rival_list.get_item_metadata(index))
	_selected_candidate = str(candidate.get("id", ""))
	_update_lobby_actions()


func _update_lobby_actions() -> void:
	var has_team := not str(_team.get("id", "")).is_empty()
	_edit_button.disabled = _busy
	_defense_button.disabled = _busy or not has_team
	_refresh_button.disabled = _busy or not has_team
	_start_button.disabled = (
		_busy
		or _selected_candidate.is_empty()
		or not _team_blocked_key().is_empty()
	)


func _start_candidate() -> void:
	if _start_button.disabled:
		return
	start_requested.emit(str(_team.get("id", "")), _selected_candidate)


func _request_action(action: String, switch_to_slot: int) -> void:
	if _busy:
		return
	begin_action(action)
	action_requested.emit(action, switch_to_slot)


func _request_switch(slot: int) -> void:
	var party := _party("player")
	var active_slot := int(party.get("active_slot", 0))
	var roster := _as_array(party.get("roster"))
	if (
		_busy
		or slot == active_slot
		or slot < 0
		or slot >= roster.size()
		or int(GameState.as_dict(roster[slot]).get("hp", 0)) <= 0
	):
		return
	_hide_switch_overlay()
	_request_action("switch", slot)


func _mount_switch_overlay() -> void:
	var overlay := Control.new()
	overlay.name = "SwitchOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.clip_contents = true
	overlay.z_index = 10
	overlay.visible = false
	var sheet := PanelContainer.new()
	sheet.name = "SwitchSheet"
	sheet.theme_type_variation = &"BottomSheetPanel"
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.anchor_left = 0.0
	sheet.anchor_right = 1.0
	sheet.anchor_top = 1.0
	sheet.anchor_bottom = 1.0
	sheet.offset_left = 0.0
	sheet.offset_right = 0.0
	sheet.offset_bottom = 0.0
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var handle_row := CenterContainer.new()
	handle_row.custom_minimum_size.y = 24.0
	handle_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var handle := ColorRect.new()
	handle.custom_minimum_size = Vector2(84, 7)
	handle.color = Color(0.4, 0.5, 0.68, 0.72)
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle_row.add_child(handle)
	column.add_child(handle_row)
	_switch_panel.reparent(column)
	sheet.add_child(column)
	overlay.add_child(sheet)
	_battle_overlay.add_child(overlay)
	_switch_overlay = overlay
	_switch_sheet = sheet


func _layout_switch_panel() -> void:
	if not is_instance_valid(_switch_sheet):
		return
	var height := _switch_sheet.get_combined_minimum_size().y
	_switch_sheet.offset_top = -height
	_switch_sheet.offset_bottom = 0.0


func _hide_switch_overlay() -> void:
	_switch_panel.visible = false
	if is_instance_valid(_switch_overlay):
		_switch_overlay.visible = false


func _open_switch_picker(forced: bool) -> void:
	if _busy:
		return
	var remaining := _living_switch_slots()
	if remaining.size() == 1:
		# Controller masih menyimpan response authoritative saat play_events selesai.
		# Satu frame memberi controller waktu melepas lock sebelum request switch.
		_request_switch.call_deferred(remaining[0])
		return
	var party := _party("player")
	var active_slot := int(party.get("active_slot", 0))
	var roster := _as_array(party.get("roster"))
	_switch_title.text = tr("TEAM_SWITCH_FORCED" if forced else "TEAM_SWITCH_TITLE")
	for slot in _switch_buttons.size():
		var button := _switch_buttons[slot]
		if slot >= roster.size():
			button.visible = false
			continue
		button.visible = true
		var member := GameState.as_dict(roster[slot])
		var hp := int(member.get("hp", 0))
		var max_hp := maxi(1, int(member.get("max_hp", 1)))
		var status_key := (
			"TEAM_SWITCH_KO" if hp <= 0
			else ("TEAM_SWITCH_ACTIVE" if slot == active_slot else "TEAM_ROSTER_READY")
		)
		button.icon = _member_texture(member)
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", 72)
		button.text = tr("TEAM_SWITCH_CARD") % [
			_fighter_title(member),
			tr(status_key),
			LocaleManager.format_ratio(hp, max_hp),
		]
		button.disabled = _busy or slot == active_slot or hp <= 0
		button.self_modulate = Color.WHITE if hp > 0 else DIM
		if slot < _switch_meters.size():
			var meter := _switch_meters[slot]
			BattleView.apply_hp_bar_state(meter, float(hp), float(max_hp))
			meter.visible = true
	_switch_cancel.visible = not forced
	_switch_panel.visible = true
	_layout_switch_panel()
	if is_instance_valid(_switch_overlay):
		_switch_overlay.visible = true
	_layout_switch_panel.call_deferred()
	_actions.visible = true
	_update_arena_actions()


func _close_switch_picker() -> bool:
	if not _switch_panel.visible or _forced_switch() or _busy:
		return false
	_hide_switch_overlay()
	_actions.visible = true
	_update_arena_actions()
	return true


func _apply_session_state() -> void:
	var state := GameState.as_dict(_session.get("state"))
	var status := str(_session.get("status", state.get("status", "active")))
	_sync_location_chrome()
	_effectiveness.visible = false
	var opening_hidden := _opening_intro_pending or _opening_intro_running
	_apply_side(_session, "player", true, not opening_hidden)
	_apply_side(
		_session,
		"opponent",
		true,
		not opening_hidden and not _intro_pending_summon
	)
	_position_fighters()
	_set_player_seeker_pose(
		"intro_idle" if status == "active"
		else ("victory" if status == "won" else "defeat")
	)
	_player_slots.text = _slots_text("player")
	_opponent_slots.text = _slots_text("opponent")
	_forfeit.visible = status == "active"
	_result.visible = status != "active"
	_set_result_actions_visible(status != "active")
	_back.disabled = status == "active" or _busy
	if status == "active":
		if _forced_switch():
			_actions.visible = true
			if not _busy:
				_open_switch_picker(true)
		else:
			_hide_switch_overlay()
			_actions.visible = true
	else:
		_actions.visible = false
		_hide_switch_overlay()
		if _is_boss_encounter() and status in ["won", "lost", "draw"]:
			_result.visible = false
			_set_result_actions_visible(false)
			# Presenter yang sedang menunggu tap sudah memegang urutannya; memanggil
			# yang kedua membuat reveal Trophy menutup baris terakhir Seeker.
			if not _boss_result_pending:
				_boss_result_pending = true
				_present_boss_result(status)
		else:
			_show_result(status)
	_update_arena_actions()


func _apply_side(
	session: Dictionary,
	side: String,
	update_hp: bool,
	show_sprite: bool = true
) -> void:
	var state := GameState.as_dict(session.get("state"))
	var party := GameState.as_dict(state.get(side))
	var slot := int(party.get("active_slot", 0))
	var roster := _as_array(party.get("roster"))
	if slot < 0 or slot >= roster.size():
		return
	var member := GameState.as_dict(roster[slot])
	var name_label := _player_name if side == "player" else _opponent_name
	name_label.text = _fighter_hud_title(member)
	var anima_id := str(member.get("anima_id", ""))
	var loaded := GameState.as_dict(_art_cache.get(anima_id))
	var sprite := _sprite_for(side)
	if bool(loaded.get("ok", false)):
		sprite.apply(loaded)
		sprite.visible = show_sprite
		if show_sprite:
			sprite.set_pose("defeated" if int(member.get("hp", 0)) <= 0 else "idle")
	else:
		sprite.visible = show_sprite
	_apply_fighter_scales(session)
	_sync_shadow(side)
	var shadow := _player_shadow if side == "player" else _opponent_shadow
	if is_instance_valid(shadow):
		shadow.visible = show_sprite
	if update_hp:
		var hp := _player_hp if side == "player" else _opponent_hp
		var hp_value := _player_hp_value if side == "player" else _opponent_hp_value
		BattleView.apply_hp_bar_state(
			hp, float(member.get("hp", 0)), float(member.get("max_hp", 1))
		)
		hp_value.text = LocaleManager.format_ratio(
			int(member.get("hp", 0)),
			int(member.get("max_hp", 1))
		)


## Session yang dianimasikan adalah yang sedang tampil plus `to_slot` event ini,
## bukan session akhir turn. Satu log bisa memuat dua switch di sisi yang sama —
## switch sukarela lalu KO menyusul — dan session akhir turn hanya mengenal
## anggota terakhir beserta HP-nya sesudah damage, jadi memakainya membuat Summon
## menampilkan Anima yang salah lalu menahan HP bar di angka pasca-damage.
func _play_switch(event: Dictionary) -> void:
	var side := str(event.get("actor", ""))
	var slot := int(event.get("to_slot", 0))
	var incoming := _session.duplicate(true)
	GameState.as_dict(
		GameState.as_dict(incoming.get("state")).get(side)
	)["active_slot"] = slot
	await _present_banner(
		tr("TEAM_EVENT_SWITCH") % _member_name(incoming, side, slot),
		BattleView.CUE_COLOR,
		false
	)
	var sprite := _sprite_for(side)
	var portal := _portal_for(side)
	var previous_layout := _fighter_layout()
	if not is_instance_valid(sprite):
		_apply_side(incoming, side, true)
		_reframe_for_switch(incoming, previous_layout, false)
		return
	if sprite.visible and sprite.sprite_frames != null:
		await sprite.summon_dissolve()
	_apply_side(incoming, side, true, false)
	var refit := _reframe_for_switch(incoming, previous_layout, true)
	_align_portal(side)
	if is_instance_valid(portal):
		await portal.start_portal()
	if is_instance_valid(portal):
		portal.burst()
	# Kamera mulai bersama charge portal, tetapi incoming harus terlihat sebelum
	# sebagian besar reframe selesai. Kalau reveal menunggu kamera, Seeker dan
	# background menyusut sendirian ketika dua Anima besar memaksa shot melebar.
	if sprite.sprite_frames != null:
		await sprite.summon_reveal()
		_sync_shadow(side)
	else:
		sprite.visible = true
	if is_instance_valid(refit) and refit.is_running():
		await refit.finished
	await _hide_effectiveness()


func _reframe_for_switch(
	session: Dictionary,
	previous_layout: Dictionary,
	animate: bool
) -> Tween:
	_session = session.duplicate(true)
	_position_fighters(false)
	var target_layout := _fighter_layout()
	if not animate:
		return null
	if _uses_static_background:
		var previous_scale: Vector2 = previous_layout.get("layer_scale", Vector2.ONE)
		var target_scale: Vector2 = target_layout.get("layer_scale", Vector2.ONE)
		var fitted_background_zoom := float(target_layout.get("background_camera_zoom", 1.0))
		var switch_background_zoom := background_zoom_for_switch(
			previous_scale.x,
			target_scale.x,
			float(previous_layout.get("background_camera_zoom", 1.0))
		)
		target_layout["background_camera_zoom"] = switch_background_zoom
		target_layout["background_ground_offset"] = (
			float(target_layout.get("background_ground_offset", 0.0))
			* fitted_background_zoom / maxf(0.001, switch_background_zoom)
		)
	_apply_fighter_layout(previous_layout)
	return _tween_fighter_layout(target_layout)


func _fighter_layout() -> Dictionary:
	return {
		"layer_position": _fighter_layer.position,
		"layer_scale": _fighter_layer.scale,
		"player_position": _player_anchor.position,
		"player_scale": _player_anchor.scale,
		"opponent_position": _opponent_anchor.position,
		"opponent_scale": _opponent_anchor.scale,
		"seeker_position": _seeker.position,
		"seeker_scale": _seeker.scale,
		"seeker_shadow_position": _seeker_shadow.position,
		"seeker_shadow_scale": _seeker_shadow.scale,
		"player_seeker_position": _player_seeker.position,
		"player_seeker_scale": _player_seeker.scale,
		"player_seeker_shadow_position": _player_seeker_shadow.position,
		"player_seeker_shadow_scale": _player_seeker_shadow.scale,
		"background_position": _arena_background.position,
		"background_size": _arena_background.size,
		"background_camera_zoom": _background_camera_zoom(),
		"background_ground_offset": _background_ground_offset,
	}


func _apply_fighter_layout(layout: Dictionary) -> void:
	_fighter_layer.position = layout.get("layer_position", _fighter_layer.position)
	_fighter_layer.scale = layout.get("layer_scale", _fighter_layer.scale)
	_player_anchor.position = layout.get("player_position", _player_anchor.position)
	_player_anchor.scale = layout.get("player_scale", _player_anchor.scale)
	_opponent_anchor.position = layout.get("opponent_position", _opponent_anchor.position)
	_opponent_anchor.scale = layout.get("opponent_scale", _opponent_anchor.scale)
	_seeker.position = layout.get("seeker_position", _seeker.position)
	_seeker.scale = layout.get("seeker_scale", _seeker.scale)
	_seeker_shadow.position = layout.get("seeker_shadow_position", _seeker_shadow.position)
	_seeker_shadow.scale = layout.get("seeker_shadow_scale", _seeker_shadow.scale)
	_player_seeker.position = layout.get("player_seeker_position", _player_seeker.position)
	_player_seeker.scale = layout.get("player_seeker_scale", _player_seeker.scale)
	_player_seeker_shadow.position = layout.get(
		"player_seeker_shadow_position", _player_seeker_shadow.position
	)
	_player_seeker_shadow.scale = layout.get(
		"player_seeker_shadow_scale", _player_seeker_shadow.scale
	)
	_arena_background.position = layout.get("background_position", _arena_background.position)
	_arena_background.size = layout.get("background_size", _arena_background.size)
	_set_background_camera_zoom(float(layout.get(
		"background_camera_zoom", _background_camera_zoom()
	)))
	_set_background_ground_offset(float(layout.get(
		"background_ground_offset", _background_ground_offset
	)))


func _tween_fighter_layout(target: Dictionary) -> Tween:
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
	_layout_tween = create_tween().set_parallel(true)
	_layout_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_layout_tween.tween_property(
		_fighter_layer, "position", target["layer_position"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_fighter_layer, "scale", target["layer_scale"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_player_anchor, "position", target["player_position"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_player_anchor, "scale", target["player_scale"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_opponent_anchor, "position", target["opponent_position"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_opponent_anchor, "scale", target["opponent_scale"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(_seeker, "position", target["seeker_position"], CAMERA_REFIT_SEC)
	_layout_tween.tween_property(_seeker, "scale", target["seeker_scale"], CAMERA_REFIT_SEC)
	_layout_tween.tween_property(
		_seeker_shadow, "position", target["seeker_shadow_position"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_seeker_shadow, "scale", target["seeker_shadow_scale"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_player_seeker, "position", target["player_seeker_position"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_player_seeker, "scale", target["player_seeker_scale"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_player_seeker_shadow,
		"position",
		target["player_seeker_shadow_position"],
		CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_player_seeker_shadow, "scale", target["player_seeker_shadow_scale"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_arena_background, "position", target["background_position"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_property(
		_arena_background, "size", target["background_size"], CAMERA_REFIT_SEC
	)
	_layout_tween.tween_method(
		_set_background_camera_zoom,
		_background_camera_zoom(),
		float(target["background_camera_zoom"]),
		CAMERA_REFIT_SEC
	)
	_layout_tween.tween_method(
		_set_background_ground_offset,
		_background_ground_offset,
		float(target["background_ground_offset"]),
		CAMERA_REFIT_SEC
	)
	return _layout_tween


func _play_attack(event: Dictionary, physical_feedback: bool = true) -> void:
	var actor_side := str(event.get("actor", ""))
	var target_side := str(event.get("target", ""))
	var actor := _sprite_for(actor_side)
	var target := _sprite_for(target_side)
	await _present_banner(
		tr("BATTLE_EVENT_ATTACK") % [
			_actor_name(actor_side),
			_move_name(actor_side, str(event.get("action", ""))),
		],
		BattleView.CUE_COLOR,
		false,
		BattleView.ToastType.GENERAL
	)
	await _hide_effectiveness()
	if is_instance_valid(actor):
		actor.set_pose("attack")
	if is_instance_valid(actor) and is_instance_valid(target):
		var fx := "fx_surge" if str(event.get("action", "")) == "surge" else "fx_strike"
		actor.play_fx(fx, target.body_center_global())
	var element_multiplier := float(event.get("element_multiplier", 1.0))
	var critical := bool(event.get("crit", false))
	var message_keys := BattleImpact.message_keys(event)
	await _event_pause(AnimaPresenter.FX_TRAVEL_SEC)
	_impact.play_event(event, physical_feedback)
	if is_instance_valid(actor):
		actor.set_pose("idle")
	var hp := int(event.get("target_hp", 0))
	if target_side == "player":
		BattleView.apply_hp_bar_state(_player_hp, float(hp), _player_hp.max_value)
		_player_hp_value.text = LocaleManager.format_ratio(hp, int(_player_hp.max_value))
	else:
		BattleView.apply_hp_bar_state(_opponent_hp, float(hp), _opponent_hp.max_value)
		_opponent_hp_value.text = LocaleManager.format_ratio(hp, int(_opponent_hp.max_value))
	if is_instance_valid(target):
		_react_seeker_attack(event)
		_react_player_seeker_attack(event)
		target.hit_react(element_multiplier)
		target.modulate = Color(1.65, 0.45, 0.55, 1.0)
		var flash := create_tween()
		flash.tween_property(target, "modulate", Color.WHITE, 0.28)
		if hp <= 0:
			target.set_pose("defeated")
	if critical:
		_show_impact_banner(message_keys, true, element_multiplier)
	await _play_damage(int(event.get("damage", 0)), element_multiplier)
	_restore_seeker_idle()
	_restore_player_seeker_idle()
	if critical:
		await _readability_pause()
	elif not message_keys.is_empty():
		await _present_impact_banner(message_keys, false, element_multiplier)
	await _hide_effectiveness()


func _show_impact_banner(
	message_keys: PackedStringArray,
	critical: bool,
	element_multiplier: float
) -> void:
	if message_keys.is_empty():
		return
	var lines := PackedStringArray()
	for key in message_keys:
		lines.append(tr(key))
	var color := BattleView.CRITICAL_COLOR if critical else (
		BattleView.EFFECTIVE_COLOR if element_multiplier > 1.0 else BattleView.RESISTED_COLOR
	)
	var type := (
		BattleView.ToastType.SUCCESS
		if critical or element_multiplier > 1.0
		else BattleView.ToastType.WARNING
	)
	_show_banner("\n".join(lines), color, critical or element_multiplier > 1.0, type)


func _present_impact_banner(
	message_keys: PackedStringArray,
	critical: bool,
	element_multiplier: float
) -> void:
	_show_impact_banner(message_keys, critical, element_multiplier)
	if is_instance_valid(_effectiveness_tween) and _effectiveness_tween.is_running():
		await _effectiveness_tween.finished
	await _readability_pause()


func _present_banner(text: String, color: Color, big: bool = true, type: BattleView.ToastType = BattleView.ToastType.GENERAL) -> void:
	_show_banner(text, color, big, type)
	if is_instance_valid(_effectiveness_tween) and _effectiveness_tween.is_running():
		await _effectiveness_tween.finished
	await _readability_pause()


func _show_banner(text: String, color: Color, big: bool = true, type: BattleView.ToastType = BattleView.ToastType.GENERAL) -> void:
	if is_instance_valid(_effectiveness_tween):
		_effectiveness_tween.kill()
	_effectiveness.visible = not text.is_empty()
	if not _effectiveness.visible:
		return
	if is_instance_valid(_event_plate) and BattleView.TOAST_STYLES.has(type):
		_event_plate.add_theme_stylebox_override("panel", BattleView.TOAST_STYLES[type])
	_effectiveness.modulate = Color.WHITE
	_effectiveness.scale = Vector2.ONE
	_effectiveness.pivot_offset = _effectiveness.size * 0.5
	_effectiveness_label.text = text
	_effectiveness_label.add_theme_color_override("font_color", color)
	_effectiveness_label.add_theme_color_override(
		"font_shadow_color", Color(color.r, color.g, color.b, 0.48)
	)
	_effectiveness_label.add_theme_font_size_override("font_size", 40 if big else 32)
	_effectiveness.modulate.a = 0.0
	_effectiveness.scale = Vector2(0.70, 0.70)
	_effectiveness_tween = create_tween().set_parallel(true)
	_effectiveness_tween.tween_property(_effectiveness, "modulate:a", 1.0, 0.08)
	_effectiveness_tween.tween_property(_effectiveness, "scale", Vector2(1.08, 1.08), 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_effectiveness_tween.chain().tween_property(
		_effectiveness, "scale", Vector2.ONE, 0.08
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _hide_effectiveness() -> void:
	if not _effectiveness.visible:
		return
	if is_instance_valid(_effectiveness_tween):
		_effectiveness_tween.kill()
	_effectiveness_tween = create_tween().set_parallel(true)
	_effectiveness_tween.tween_property(_effectiveness, "modulate:a", 0.0, 0.14)
	_effectiveness_tween.tween_property(
		_effectiveness, "scale", Vector2(1.12, 1.12), 0.14
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _effectiveness_tween.finished
	_effectiveness.visible = false
	_effectiveness.modulate = Color.WHITE
	_effectiveness.scale = Vector2.ONE


func _update_arena_actions() -> void:
	if _session.is_empty():
		return
	var state := GameState.as_dict(_session.get("state"))
	var active := str(_session.get("status", state.get("status", ""))) == "active"
	var member := _active_member("player")
	var locked := _busy or _forced_switch() or _switch_panel.visible
	var committed := _busy and not _queued_action.is_empty()
	_attack_button.text = LocaleManager.move_name(member, "strike")
	_special_button.text = tr("TEAM_SPECIAL_BUTTON") % [
		LocaleManager.move_name(member, "surge"),
		LocaleManager.format_integer(int(member.get("momentum", 0))),
		LocaleManager.format_integer(int(member.get("momentum_max", 3))),
	]
	_attack_button.disabled = not active or (locked and not committed)
	_special_button.disabled = (
		not active
		or int(member.get("momentum", 0)) < SURGE_COST
		or (locked and not committed)
	)
	_guard_button.disabled = not active or (locked and not committed)
	_item_button.disabled = not active or (locked and not committed)
	_switch_button.disabled = (
		not active or not _has_living_bench() or (locked and not committed)
	)
	var accepts_input := (
		active
		and not _busy
		and not _forced_switch()
		and not _switch_panel.visible
		and _opening_chrome_shown
	)
	for button in [_attack_button, _special_button, _guard_button, _item_button, _switch_button]:
		var action_button := button as Button
		action_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if accepts_input and not action_button.disabled
			else Control.MOUSE_FILTER_IGNORE
		)
		action_button.focus_mode = (
			Control.FOCUS_ALL
			if accepts_input and not action_button.disabled
			else Control.FOCUS_NONE
		)
	_forfeit.disabled = not active or _busy
	_forfeit.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if accepts_input and not _forfeit.disabled
		else Control.MOUSE_FILTER_IGNORE
	)
	_forfeit.focus_mode = (
		Control.FOCUS_ALL
		if accepts_input and not _forfeit.disabled
		else Control.FOCUS_NONE
	)


func _show_result(status: String) -> void:
	var reward := GameState.as_dict(_session.get("last_reward"))
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match status:
		"won":
			_result_title.text = tr(
				"EXPEDITION_ENCOUNTER_WIN_TITLE" if _expedition_mode else "TEAM_WIN_TITLE"
			)
			var exp_lines := _exp_reward_lines(reward)
			_result_body_base = _win_reward_text(reward, exp_lines)
			if not exp_lines.is_empty():
				_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			# Knockout/status-tick sudah memicu happy pose ini di saat yang sama
			# Seeker berganti ke "victory" -- jangan mengulang flourish-nya di sini.
			if _player_sprite.current_pose() != "happy":
				_player_sprite.victory_celebration(_active_player_level())
		"lost":
			_result_title.text = tr(
				"EXPEDITION_WIPE_TITLE" if _expedition_mode else "TEAM_LOSS_TITLE"
			)
			_result_body_base = tr(
				"EXPEDITION_WIPE_BODY" if _expedition_mode else "TEAM_LOSS_BODY"
			)
		"draw":
			_result_title.text = tr(
				"EXPEDITION_WIPE_TITLE" if _expedition_mode else "TEAM_DRAW_TITLE"
			)
			_result_body_base = tr(
				"EXPEDITION_WIPE_BODY" if _expedition_mode else "TEAM_DRAW_BODY"
			)
		_:
			_result_title.text = tr("BATTLE_FORFEIT_TITLE")
			_result_body_base = tr("BATTLE_FORFEIT_BODY")
	_apply_result_actions()


## Rematch butuh 2–4 anggota yang masih bisa bertarung. Kalau tidak, CTA-nya
## menjadi Edit Team plus alasannya. Expedition keluar lewat Return to Map.
func _apply_result_actions() -> void:
	var blocked := "" if _expedition_mode else _team_blocked_key()
	_retry_edits_team = not blocked.is_empty()
	if _retry_edits_team:
		# Chip pendek: CTA-nya sudah bilang Edit Team, dan panel result tumbuh ke
		# atas menutupi arena kalau alasannya ditulis sebagai kalimat penuh.
		var reason := tr("BATTLE_RESULT_BLOCKED") % tr(_team_member_status_key(blocked))
		_result_body.text = _result_body_base + "\n" + reason
		_retry.text = tr("TEAM_EDIT")
		return
	_result_body.text = _result_body_base
	if not _expedition_mode:
		var state_value: Variant = _session.get("state", {})
		var state: Dictionary = state_value if typeof(state_value) == TYPE_DICTIONARY else {}
		var status := str(_session.get("status", state.get("status", "")))
		_retry.text = tr("TEAM_NEXT_BATTLE") if status == "won" else tr("TEAM_RETRY")


func _set_result_actions_visible(shown: bool) -> void:
	_result_panel.visible = shown
	_result_actions.visible = shown
	_retry.visible = shown
	_leave.visible = shown and not _expedition_mode
	if shown:
		_layout_result_panel.call_deferred()


func _on_retry_pressed() -> void:
	if _retry_edits_team:
		_edit_team()
		return
	retry_requested.emit()


func _active_player_level() -> int:
	return int(_active_member("player").get("level", 1))


## Fail open: roster yang belum ter-refresh tidak boleh mengunci tombol, sebab
## server tetap pagar terakhirnya.
func _team_blocked_key() -> String:
	if _roster.is_empty():
		return ""
	for anima_id in _team_member_ids(_team):
		for value in _roster:
			var row := GameState.as_dict(value)
			if str(row.get("id", "")) != anima_id:
				continue
			var unavailable := _team_member_unavailable(row)
			if not unavailable.is_empty():
				return unavailable
			break
	return ""


func _slots_text(side: String) -> String:
	var party := _party(side)
	var active_slot := int(party.get("active_slot", 0))
	var roster := _as_array(party.get("roster"))
	var labels: PackedStringArray = []
	for slot in roster.size():
		var hp := int(GameState.as_dict(roster[slot]).get("hp", 0))
		if hp <= 0:
			labels.append("×")
		elif slot == active_slot:
			labels.append("●")
		else:
			labels.append("○")
	return "  ".join(labels)


func _team_lineup_text(team: Dictionary) -> String:
	var names: PackedStringArray = []
	for value in _as_array(team.get("members")):
		names.append(str(GameState.as_dict(value).get("nickname", tr("ANIMA_FALLBACK_NAME"))))
	return tr("TEAM_LINEUP") % " · ".join(names)


func _daily_reward_text(daily: Dictionary) -> String:
	if daily.is_empty():
		return tr("BATTLE_REWARD_STATUS_ERROR")
	return "%s · %s" % [
		tr("BATTLE_DAILY_PROGRESS") % [
			LocaleManager.format_integer(int(daily.get("earned", 0))),
			LocaleManager.format_integer(int(daily.get("limit", 2))),
		],
		tr("BATTLE_DAILY_BITS") % [
			LocaleManager.format_integer(int(daily.get("bits_earned", 0))),
			LocaleManager.format_integer(int(daily.get("bits_limit", 40))),
		],
	]


func _team_member_unavailable(row: Dictionary) -> String:
	if CareRules.is_evolving(row):
		return "TEAM_MEMBER_EVOLVING_COPY"
	if str(row.get("status", "")) != "ready":
		return "TEAM_MEMBER_NOT_READY_COPY"
	if row.get("dormant_since") != null and not str(row.get("dormant_since", "")).is_empty():
		return "TEAM_MEMBER_DORMANT_COPY"
	var care := GameState.as_dict(row.get("care"))
	if float(care.get("energy", 0.0)) < 10.0:
		return "TEAM_MEMBER_LOW_ENERGY_COPY"
	return ""


static func _team_member_status_key(unavailable: String) -> String:
	match unavailable:
		"TEAM_MEMBER_NOT_READY_COPY":
			return "BATTLE_PICK_NOT_READY"
		"TEAM_MEMBER_DORMANT_COPY":
			return "BATTLE_PICK_DORMANT"
		"TEAM_MEMBER_LOW_ENERGY_COPY":
			return "BATTLE_PICK_LOW_ENERGY"
		"TEAM_MEMBER_EVOLVING_COPY":
			return "BATTLE_PICK_EVOLVING"
		_:
			return "TEAM_ROSTER_READY"


func _team_member_ids(team: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for value in _as_array(team.get("members")):
		var anima_id := str(GameState.as_dict(value).get("anima_id", ""))
		if not anima_id.is_empty():
			ids.append(anima_id)
	return ids


func _party(side: String) -> Dictionary:
	return GameState.as_dict(GameState.as_dict(_session.get("state")).get(side))


func _active_member(side: String) -> Dictionary:
	var party := _party(side)
	var roster := _as_array(party.get("roster"))
	var slot := int(party.get("active_slot", 0))
	return GameState.as_dict(roster[slot]) if slot >= 0 and slot < roster.size() else {}


func _member_name(session: Dictionary, side: String, slot: int) -> String:
	var state := GameState.as_dict(session.get("state"))
	var roster := _as_array(GameState.as_dict(state.get(side)).get("roster"))
	if slot < 0 or slot >= roster.size():
		return tr("ANIMA_FALLBACK_NAME")
	return str(GameState.as_dict(roster[slot]).get("name", tr("ANIMA_FALLBACK_NAME")))


func _move_name(side: String, action: String) -> String:
	return LocaleManager.move_name(_active_member(side), action)


func _actor_name(side: String) -> String:
	var anima_name := str(_active_member(side).get("name", "")).strip_edges()
	return anima_name if not anima_name.is_empty() else tr("ANIMA_FALLBACK_NAME")


func _sprite_for(side: String) -> AnimaPresenter:
	return _player_sprite if side == "player" else _opponent_sprite


func _faint(side: String) -> void:
	var sprite := _sprite_for(side)
	if is_instance_valid(sprite):
		sprite.set_pose("defeated")


func _announce_initiative(events: Array) -> void:
	for value in events:
		var event := GameState.as_dict(value)
		var event_type := str(event.get("type", ""))
		if event_type in ["guard", "switch", "item"]:
			return
		if event_type != "attack":
			continue
		await _present_banner(
			tr("BATTLE_INITIATIVE") % _actor_name(str(event.get("actor", ""))),
			BattleView.CUE_COLOR,
			false
		)
		await _hide_effectiveness()
		return


func _forced_switch() -> bool:
	return bool(_party("player").get("forced_switch", false))


func _fighter_title(member: Dictionary) -> String:
	var anima_name := str(member.get("name", tr("ANIMA_FALLBACK_NAME")))
	var level := int(member.get("level", 0))
	if level <= 0:
		level = CARE_RULES.level_from_exp(int(member.get("care_score", 0)))
	return "%s %s" % [anima_name, LocaleManager.level_label(maxi(1, level))]


func _fighter_hud_title(member: Dictionary) -> String:
	var title := _fighter_title(member)
	var summary := CareRules.fighter_status_summary(member)
	if summary.is_empty():
		return title
	return "%s · %s" % [title, summary]


func _living_switch_slots() -> Array[int]:
	var slots: Array[int] = []
	var party := _party("player")
	var active_slot := int(party.get("active_slot", 0))
	var roster := _as_array(party.get("roster"))
	for slot in roster.size():
		if slot != active_slot and int(GameState.as_dict(roster[slot]).get("hp", 0)) > 0:
			slots.append(slot)
	return slots


func _has_living_bench() -> bool:
	return not _living_switch_slots().is_empty()


func _total_reward_exp(reward: Dictionary) -> int:
	var total := 0
	for value in _as_array(reward.get("anima_exp")):
		total += int(GameState.as_dict(value).get("exp", 0))
	return total


func _win_reward_text(reward: Dictionary, exp_lines: PackedStringArray) -> String:
	if _expedition_mode:
		var lines := PackedStringArray([
			tr("EXPEDITION_ENCOUNTER_WIN_TOKENS") % LocaleManager.format_integer(
				int(reward.get("supplies", 0))
			),
		])
		if reward.has("zone_bits"):
			lines.append(tr("EXPEDITION_ZONE_BITS_RESULT") % [
				LocaleManager.format_integer(int(reward.get("zone_bits", 0))),
				LocaleManager.format_integer(int(reward.get("zone_scheduled_bits", 0))),
			])
		if int(reward.get("clear_bits", 0)) > 0:
			lines.append(tr("EXPEDITION_FIRST_CLEAR_BITS_RESULT") % LocaleManager.format_integer(
				int(reward.get("clear_bits", 0))
			))
		lines.append_array(exp_lines)
		return "\n".join(lines)
	var bits := LocaleManager.format_integer(int(reward.get("bits", 0)))
	if exp_lines.is_empty():
		if reward.has("anima_exp"):
			return tr("TEAM_WIN_BODY") % [bits, LocaleManager.format_integer(_total_reward_exp(reward))]
		return tr("TEAM_WIN_RESUMED_BODY") % bits
	return "%s\n%s" % [tr("TEAM_WIN_BITS") % bits, "\n".join(exp_lines)]


func _exp_reward_lines(reward: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for value in _as_array(reward.get("anima_exp")):
		var row := GameState.as_dict(value)
		var exp := int(row.get("exp", 0))
		if exp <= 0:
			continue
		var anima_id := str(row.get("anima_id", ""))
		var before := _reward_care_score_before(row, anima_id)
		if before >= 0 and int(CARE_RULES.leveled_up(before, before + exp)) > 0:
			lines.append(tr("TEAM_REWARD_LEVEL_ROW") % [
				_reward_member_name(anima_id),
				LocaleManager.format_integer(exp),
				LocaleManager.format_integer(int(CARE_RULES.level_from_exp(before + exp))),
			])
		else:
			lines.append(tr("TEAM_REWARD_EXP_ROW") % [
				_reward_member_name(anima_id),
				LocaleManager.format_integer(exp),
			])
	return lines


func _reward_member_name(anima_id: String) -> String:
	for value in _as_array(_party("player").get("roster")):
		var member := GameState.as_dict(value)
		if str(member.get("anima_id", "")) == anima_id:
			return str(member.get("name", tr("ANIMA_FALLBACK_NAME")))
	var snapshot := _snapshot_member(anima_id)
	if not snapshot.is_empty():
		return str(snapshot.get("name", tr("ANIMA_FALLBACK_NAME")))
	return tr("ANIMA_FALLBACK_NAME")


func _reward_care_score_before(row: Dictionary, anima_id: String) -> int:
	if row.has("care_score_before"):
		return int(row.get("care_score_before", -1))
	var snapshot := _snapshot_member(anima_id)
	if snapshot.has("care_score"):
		return int(snapshot.get("care_score", -1))
	return -1


func _snapshot_member(anima_id: String) -> Dictionary:
	for value in _as_array(_session.get("player_snapshot")):
		var snapshot := GameState.as_dict(value)
		if str(snapshot.get("anima_id", "")) == anima_id:
			return snapshot
	return {}


func _tier_label(tier: String) -> String:
	match tier:
		"favorable":
			return tr("BATTLE_TIER_FAVORABLE")
		"tough":
			return tr("BATTLE_TIER_TOUGH")
		"formidable":
			return tr("BATTLE_TIER_FORMIDABLE")
		_:
			return tr("BATTLE_TIER_EVEN")


func _error_copy(code: String) -> String:
	var key := str({
		"FEATURE_DISABLED": "TEAM_COMING_SOON",
		"TEAM_REQUIRES_FOUR": "TEAM_REQUIRES_FOUR_COPY",
		"TEAM_REQUIRES_TWO_TO_FOUR": "TEAM_REQUIRES_TWO_TO_FOUR_COPY",
		"TEAM_MEMBER_NOT_READY": "TEAM_MEMBER_NOT_READY_COPY",
		"TEAM_MEMBER_UNAVAILABLE": "TEAM_MEMBER_UNAVAILABLE_COPY",
		"TEAM_MEMBER_SLEEPING": "TEAM_MEMBER_SLEEPING_COPY",
		"TEAM_MEMBER_LOW_ENERGY": "TEAM_MEMBER_LOW_ENERGY_COPY",
		"TEAM_ART_NOT_READY": "TEAM_ART_NOT_READY_COPY",
		"TEAM_CANDIDATE_EXPIRED": "TEAM_CANDIDATE_EXPIRED_COPY",
		"COMBAT_ALREADY_ACTIVE": "TEAM_COMBAT_ACTIVE_COPY",
		"NO_TEAM_OPPONENT": "TEAM_NO_RIVAL_COPY",
		"FORCED_SWITCH_REQUIRED": "TEAM_SWITCH_FORCED",
		"INVALID_SWITCH_SLOT": "TEAM_SWITCH_INVALID_COPY",
		"NO_MOMENTUM": "BATTLE_NO_MOMENTUM",
		"NO_ITEM": "ERROR_NO_ITEM",
		"ITEM_ALREADY_USED": "BATTLE_ITEM_USED",
		"AUTH_EXPIRED": "BATTLE_AUTH_EXPIRED",
	}.get(code, "TEAM_ERROR_GENERIC"))
	return tr(key)


func _show_action_commit(action: String) -> void:
	_clear_action_commit()
	_queued_action = action
	var selected := _button_for_action(action)
	var commit := _action_commits.get(action) as ColorRect
	for button in [_attack_button, _special_button, _guard_button, _item_button, _switch_button]:
		(button as Button).self_modulate = (
			Color.WHITE if button == selected else Color(1.0, 1.0, 1.0, 0.48)
		)
	if commit == null:
		return
	commit.visible = true
	commit.pivot_offset = Vector2(commit.size.x * 0.5, commit.size.y * 0.5)
	commit.scale = Vector2(0.0, 1.0)
	commit.modulate = Color.WHITE
	_command_tween = create_tween()
	_command_tween.tween_property(commit, "scale:x", 1.0, 0.10) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_command_tween.tween_property(commit, "modulate:a", 0.42, 0.28)
	_command_tween.tween_property(commit, "modulate:a", 1.0, 0.28)
	_command_tween.set_loops()


func _clear_action_commit() -> void:
	if is_instance_valid(_command_tween):
		_command_tween.kill()
	_command_tween = null
	_queued_action = ""
	for button in [_attack_button, _special_button, _guard_button, _item_button, _switch_button]:
		(button as Button).self_modulate = Color.WHITE
	for commit in _action_commits.values():
		if commit is ColorRect:
			(commit as ColorRect).visible = false
			(commit as ColorRect).scale = Vector2.ONE
			(commit as ColorRect).modulate = Color.WHITE


func _button_for_action(action: String) -> Button:
	match action:
		"surge":
			return _special_button
		"guard":
			return _guard_button
		"item":
			return _item_button
		"switch":
			return _switch_button
		_:
			return _attack_button


func _member_texture(member: Dictionary) -> Texture2D:
	var anima_id := str(member.get("anima_id", ""))
	var loaded := GameState.as_dict(_art_cache.get(anima_id))
	if bool(loaded.get("ok", false)) and loaded.get("frames") is SpriteFrames:
		var frames := loaded.get("frames") as SpriteFrames
		if frames.has_animation("idle"):
			return frames.get_frame_texture("idle", 0)
	if _thumbnail_provider.is_valid():
		var texture: Variant = _thumbnail_provider.call(member)
		if texture is Texture2D:
			return texture
	return null


func _make_commit(button: Button, color: Color) -> ColorRect:
	var commit := ColorRect.new()
	commit.visible = false
	commit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	commit.color = color
	commit.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	commit.offset_top = -7.0
	commit.offset_bottom = 0.0
	button.add_child(commit)
	return commit


func _make_switch_meter(button: Button) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.name = "Hp"
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.custom_minimum_size = Vector2(0, 10)
	meter.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	meter.offset_left = 12.0
	meter.offset_right = -12.0
	meter.offset_top = -18.0
	meter.offset_bottom = -8.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.32, 0.9, 0.82, 1.0)
	fill.set_corner_radius_all(4)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.04, 0.09, 0.96)
	background.set_corner_radius_all(4)
	meter.add_theme_stylebox_override("fill", fill)
	meter.add_theme_stylebox_override("background", background)
	button.add_child(meter)
	return meter


func _emit_arena_open() -> void:
	arena_open_changed.emit(is_arena_open())


func _align_portal(side: String) -> void:
	var sprite := _sprite_for(side)
	var portal := _portal_for(side)
	if not is_instance_valid(sprite) or not is_instance_valid(portal):
		return
	if sprite.sprite_frames == null:
		portal.position = Vector2(0.0, -140.0)
		return
	portal.align_visual_center(sprite.body_center_global())


func _match_anima_opaque_to_seeker() -> void:
	if not is_instance_valid(_seeker) or not _seeker.has_sheet():
		return
	var heights := _active_body_heights()
	var seeker_cm := heights[2]
	if seeker_cm <= 0.0:
		return
	var scales := _arena_scales(_session)
	if scales.size() < 3:
		return
	var metrics := GameState.as_dict(_seeker_loaded.get("render_metrics"))
	var seeker_h := maxf(1.0, float(metrics.get("reference_height_px", 282.0))) * scales[2]
	_fit_sprite_opaque_height(
		_player_sprite, _player_anchor, seeker_h * BattleScale.anima_display_height_cm(heights[0]) / seeker_cm
	)
	_fit_sprite_opaque_height(
		_opponent_sprite,
		_opponent_anchor,
		seeker_h * BattleScale.anima_display_height_cm(heights[1]) / seeker_cm
	)


func _fit_sprite_opaque_height(sprite: AnimaPresenter, anchor: Node2D, target_px: float) -> void:
	if not is_instance_valid(sprite) or target_px <= 0.0:
		return
	sprite.plant_on_anchor()
	var opaque_h := sprite.opaque_local_rect().size.y
	if opaque_h <= 0.0:
		return
	var current := opaque_h * absf(anchor.scale.y)
	if current <= 0.0:
		return
	anchor.scale *= target_px / current


func _sync_seeker_shadow() -> void:
	if is_instance_valid(_seeker):
		_seeker.sync_ground_shadow(_seeker_shadow)
	if is_instance_valid(_player_seeker):
		_player_seeker.sync_ground_shadow(_player_seeker_shadow)


func _sync_shadow(side: String) -> void:
	var sprite := _sprite_for(side)
	var shadow := _player_shadow if side == "player" else _opponent_shadow
	if is_instance_valid(sprite):
		sprite.sync_ground_shadow(shadow)


func _make_ground_shadow(anchor: Node2D) -> Sprite2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.01, 0.02, 0.05, 0.45),
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
	shadow.name = "GroundShadow"
	shadow.centered = true
	shadow.texture = texture
	shadow.z_index = 0
	shadow.position = Vector2.ZERO
	shadow.scale = Vector2(1.35, 0.7)
	anchor.add_child(shadow)
	anchor.move_child(shadow, 0)
	return shadow


func _make_portal(anchor: Node2D) -> IncubatorEffect:
	var portal := IncubatorEffect.new()
	portal.name = "SummonPortal"
	portal.position = Vector2(0.0, -140.0)
	portal.z_index = 0
	anchor.add_child(portal)
	return portal


func _portal_for(side: String) -> IncubatorEffect:
	return _player_portal if side == "player" else _opponent_portal


func _position_fighters(cancel_transition: bool = true) -> void:
	if is_instance_valid(_impact):
		_impact.cancel()
	if cancel_transition and _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
		_layout_tween = null
	if not is_instance_valid(_battle_stage) or not is_instance_valid(_fighter_layer):
		return
	_fighter_layer.position = Vector2.ZERO
	_fighter_layer.scale = Vector2.ONE
	var ground_y := _battle_stage.size.y * _ground_y_ratio()
	_player_anchor.position = Vector2(_battle_stage.size.x * BattleScale.PLAYER_SHOT_X, ground_y)
	_opponent_anchor.position = Vector2(
		_battle_stage.size.x * BattleScale.OPPONENT_SHOT_X, ground_y
	)
	_apply_fighter_scales(_session)
	_position_seeker()
	_position_player_seeker()
	_match_anima_opaque_to_seeker()
	_player_sprite.plant_on_anchor()
	_opponent_sprite.plant_on_anchor()
	_separate_fighter_bodies()
	_sync_shadow("player")
	_sync_shadow("opponent")
	_apply_fighter_layers()
	_apply_dynamic_camera()
	_sync_seeker_shadow()


func _fighter_pair_gap() -> float:
	var player_width := _player_sprite.opaque_local_rect().size.x * absf(_player_anchor.scale.x)
	var opponent_width := (
		_opponent_sprite.opaque_local_rect().size.x * absf(_opponent_anchor.scale.x)
	)
	return (
		(_opponent_anchor.position.x - opponent_width * 0.5)
		- (_player_anchor.position.x + player_width * 0.5)
	)


func _separate_fighter_bodies() -> void:
	var overlap := _battle_stage.size.x * CAMERA_FIGHTER_GAP_RATIO - _fighter_pair_gap()
	if overlap > 0.0:
		_player_anchor.position.x -= overlap * 0.5
		_opponent_anchor.position.x += overlap * 0.5


func _apply_dynamic_camera() -> void:
	var bounds := _fighter_shot_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var side_pad := _battle_stage.size.x * CAMERA_SIDE_PAD_RATIO
	var top_pad := _battle_stage.size.y * CAMERA_TOP_PAD_RATIO
	var ground_y := _battle_stage.size.y * _ground_y_ratio()
	var camera_ground_y := _camera_ground_y(ground_y)
	var camera_top_y := _camera_top_y()
	var fit_zoom := minf(
		(_battle_stage.size.x - side_pad * 2.0) / bounds.size.x,
		maxf(1.0, camera_ground_y - camera_top_y - top_pad) / bounds.size.y
	)
	var heights := _active_body_heights()
	var tallest_anima := maxf(
		BattleScale.anima_display_height_cm(heights[0]),
		BattleScale.anima_display_height_cm(heights[1])
	)
	var size_mix := clampf(
		inverse_lerp(50.0, BattleScale.ANIMA_VISUAL_HEIGHT_CAP_CM, tallest_anima),
		0.0,
		1.0
	)
	var preferred_zoom := lerpf(CAMERA_MAX_ZOOM, CAMERA_LARGE_ANIMA_ZOOM, size_mix)
	var zoom := clampf(minf(fit_zoom, preferred_zoom), CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	_fighter_layer.scale = Vector2(zoom, zoom)
	_fighter_layer.position = Vector2(
		_battle_stage.size.x * 0.5 - bounds.get_center().x * zoom,
		camera_ground_y - ground_y * zoom
	)
	_pin_seeker_to_camera_right(zoom)
	_pin_player_seeker_to_camera_left(zoom)
	_layout_arena_background(_background_zoom_for_camera(zoom, size_mix))
	_set_background_ground_offset(
		(ground_y - camera_ground_y)
		/ maxf(1.0, _arena_background.size.y * _background_camera_zoom())
	)


func _camera_ground_y(cinematic_ground_y: float) -> float:
	if not _gameplay_framing:
		return cinematic_ground_y
	var stage_top := _battle_stage.get_global_rect().position.y
	var dock_top := _arena_dock.get_global_rect().position.y - stage_top
	return clampf(
		dock_top - GAMEPLAY_CHROME_GAP,
		_battle_stage.size.y * 0.50,
		cinematic_ground_y
	)


func _camera_top_y() -> float:
	if not _gameplay_framing or not _turn.visible:
		return 0.0
	var stage_top := _battle_stage.get_global_rect().position.y
	return clampf(
		_turn.get_global_rect().end.y - stage_top + GAMEPLAY_CHROME_GAP,
		0.0,
		_battle_stage.size.y * 0.35
	)


## Background statis tidak boleh diam ketika camera-fit horizontal mengecilkan
## seluruh FighterLayer: itu membuat Seeker dan lawan tampak berubah ukuran di
## dunia yang beku. Baseline absolut menyisakan rentang 1,0–1,08× untuk fighter
## yang sudah besar; saat Switch, `background_zoom_for_switch()` memakai delta
## kamera supaya perubahan tinggi di plateau baseline tetap menggerakkan latar.
func _background_zoom_for_camera(camera_zoom: float, size_mix: float) -> float:
	if not _uses_static_background:
		return lerpf(_background_max_scale(), 1.0, size_mix)
	var camera_response := clampf(
		inverse_lerp(
			TEAM_STATIC_BACKGROUND_CAMERA_FLOOR,
			CAMERA_LARGE_ANIMA_ZOOM,
			camera_zoom
		),
		0.0,
		1.0
	)
	return lerpf(1.0, TEAM_STATIC_BACKGROUND_CAMERA_MAX, camera_response)


static func background_zoom_for_switch(
	previous_camera_zoom: float,
	target_camera_zoom: float,
	previous_background_zoom: float
) -> float:
	if previous_camera_zoom <= 0.0 or target_camera_zoom <= 0.0:
		return clampf(previous_background_zoom, 1.0, TEAM_STATIC_BACKGROUND_CAMERA_MAX)
	var camera_ratio := target_camera_zoom / previous_camera_zoom
	var parallax_ratio := lerpf(1.0, camera_ratio, TEAM_STATIC_BACKGROUND_REFIT_STRENGTH)
	return clampf(
		previous_background_zoom * parallax_ratio,
		1.0,
		TEAM_STATIC_BACKGROUND_CAMERA_MAX
	)


func _uses_expedition_framing() -> bool:
	return _expedition_mode or _is_boss_encounter()


func _ground_y_ratio() -> float:
	return BattleScale.GROUND_Y_RATIO if _uses_expedition_framing() else TEAM_GROUND_Y_RATIO


func _background_max_scale() -> float:
	return CAMERA_BACKGROUND_MAX_SCALE if _uses_expedition_framing() else TEAM_BACKGROUND_MAX_SCALE


func _sync_background_pan() -> void:
	var session_id := str(_session.get("id", ""))
	if session_id == _background_session_id:
		return
	_background_session_id = session_id
	_background_pan = BattleScale.background_pan_for_session(session_id)


func _layout_arena_background(background_zoom: float) -> void:
	_sync_static_background_variant()
	if not is_instance_valid(_arena_background) or not _arena_background.texture is Texture2D:
		return
	var texture_size := _arena_background.texture.get_size()
	var stage_size := _battle_stage.size
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or stage_size.x <= 0.0 or stage_size.y <= 0.0:
		return
	var guard := BattleImpact.background_overscan_px(stage_size.x)
	var geometry_zoom := 1.0 if _uses_static_background else maxf(1.0, background_zoom)
	var draw_size := BattleScale.background_draw_size(
		texture_size, stage_size, guard, geometry_zoom
	)
	var overflow_x := maxf(0.0, draw_size.x - stage_size.x)
	_arena_background.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_arena_background.pivot_offset = Vector2.ZERO
	_arena_background.scale = Vector2.ONE
	_arena_background.size = draw_size
	var pan := 0.5 if _uses_static_background else _background_pan
	_arena_background.position = Vector2(
		-overflow_x * pan,
		BattleScale.grounded_background_y(stage_size.y, draw_size.y)
	)
	_set_background_camera_zoom(background_zoom if _uses_static_background else 1.0)
	_set_background_ground_offset(_background_ground_offset)


func _background_camera_zoom() -> float:
	var background_material := _arena_background.material as ShaderMaterial
	if background_material == null:
		return 1.0
	var value: Variant = background_material.get_shader_parameter("camera_zoom")
	return float(value) if value != null else 1.0


func _set_background_camera_zoom(value: float) -> void:
	var background_material := _arena_background.material as ShaderMaterial
	if background_material != null:
		background_material.set_shader_parameter("camera_zoom", value)
		background_material.set_shader_parameter(
			"camera_pivot_y", BattleScale.GROUND_Y_RATIO
		)


func _set_background_ground_offset(value: float) -> void:
	_background_ground_offset = maxf(0.0, value)
	var background_material := _arena_background.material as ShaderMaterial
	if background_material != null:
		background_material.set_shader_parameter("camera_offset_y", _background_ground_offset)


func _pin_seeker_to_camera_right(camera_zoom: float) -> void:
	if not is_instance_valid(_seeker) or not _seeker.has_sheet() or camera_zoom <= 0.0:
		return
	_seeker.position.x = BattleScale.seeker_pinned_x(
		_seeker_loaded,
		_seeker.scale.x,
		_battle_stage.size.x,
		_fighter_layer.position.x,
		camera_zoom,
		false
	)


## Cermin dari `_pin_seeker_to_camera_right()`: sesudah kamera memilih zoom-nya,
## figur pemain dijepit ke tepi sisi pemain dengan pad yang sama.
func _pin_player_seeker_to_camera_left(camera_zoom: float) -> void:
	if (
		not is_instance_valid(_player_seeker)
		or not _player_seeker.has_sheet()
		or camera_zoom <= 0.0
	):
		return
	_player_seeker.position.x = BattleScale.seeker_pinned_x(
		_player_seeker_loaded,
		_player_seeker.scale.x,
		_battle_stage.size.x,
		_fighter_layer.position.x,
		camera_zoom,
		true
	)


## Kotak yang wajib terlihat kamera. Kedua figur Seeker dijepit ke tepi layar
## **sesudah** kamera memilih zoom dan pusatnya, jadi posisi mereka saat ini
## turunan dari bingkai sebelumnya — memasukkannya sebagai rect di posisi lama
## hanya menjamin figurnya terlihat, bukan memberinya udara. Yang dicadangkan
## karena itu kolom di sisi masing-masing: zoom hanya mengecil kalau memang tidak
## cukup, dan pusatnya bergeser menjauhi figur, jadi Anima yang minggir alih-alih
## komposisi shot yang dipindah.
func _fighter_shot_bounds() -> Rect2:
	var ground_y := _player_anchor.position.y
	var bounds := _anima_shot_rect(_player_sprite, _player_anchor, ground_y).merge(
		_anima_shot_rect(_opponent_sprite, _opponent_anchor, ground_y)
	)
	bounds = bounds.grow_individual(
		_seeker_column(_player_seeker, _player_seeker_loaded),
		0.0,
		_seeker_column(_seeker, _seeker_loaded),
		0.0
	)
	var tallest := maxf(
		_seeker_column_height(_player_seeker, _player_seeker_loaded),
		_seeker_column_height(_seeker, _seeker_loaded)
	)
	if tallest > bounds.size.y:
		bounds = bounds.grow_individual(0.0, tallest - bounds.size.y, 0.0, 0.0)
	return bounds


## Lebar kolom yang harus dicadangkan kamera untuk satu figur, nol kalau di sisi
## itu tidak ada figur.
func _seeker_column(seeker: SeekerPresenter, loaded: Dictionary) -> float:
	if not is_instance_valid(seeker) or not seeker.has_sheet():
		return 0.0
	return BattleScale.seeker_reserved_column(loaded, seeker.scale.x, _battle_stage.size.x)


func _seeker_column_height(seeker: SeekerPresenter, loaded: Dictionary) -> float:
	if not is_instance_valid(seeker) or not seeker.has_sheet():
		return 0.0
	return BattleScale.seeker_reference_height(loaded) * absf(seeker.scale.y)


func _anima_shot_rect(sprite: AnimaPresenter, anchor: Node2D, ground_y: float) -> Rect2:
	var opaque := sprite.opaque_local_rect().size
	var width := opaque.x * absf(anchor.scale.x)
	var height := opaque.y * absf(anchor.scale.y)
	return Rect2(anchor.position.x - width * 0.5, ground_y - height, width, height)


func _apply_fighter_layers() -> void:
	if _intro_pending_summon:
		_set_fighter_z(3, 2, 1)
		return
	var heights := _active_body_heights()
	var seeker_cm := heights[2]
	var player_back := (
		seeker_cm > 0.0 and BattleScale.anima_behind_seeker(heights[0], seeker_cm)
	)
	var opponent_back := (
		seeker_cm > 0.0 and BattleScale.anima_behind_seeker(heights[1], seeker_cm)
	)
	if player_back and opponent_back:
		_set_fighter_z(2, 1, 3)
	elif player_back:
		_set_fighter_z(1, 3, 2)
	elif opponent_back:
		_set_fighter_z(3, 1, 2)
	else:
		_set_fighter_z(3, 2, 1)


func _set_fighter_z(player_z: int, opponent_z: int, seeker_z: int) -> void:
	_player_anchor.z_index = player_z
	_opponent_anchor.z_index = opponent_z
	_player_sprite.z_index = 1
	_opponent_sprite.z_index = 1
	if is_instance_valid(_seeker):
		_seeker.z_index = seeker_z
	_order_stage_fighters()


## Figur pemain berdiri di depan Anima-nya sendiri begitu Anima itu setinggi
## `BattleScale.anima_behind_seeker()`; di bawah ambang itu ia tetap di belakang
## lantai z petarung mana pun. Bayangan kontaknya wajib ikut lantai yang sama —
## dibiarkan di lantai belakang, ia tertinggal di balik Anima yang figurnya baru
## saja melewati.
func _apply_player_seeker_layer() -> void:
	if not is_instance_valid(_player_seeker):
		return
	var lane := BattleScale.player_seeker_z(
		_active_body_heights()[0], PLAYER_SEEKER_HEIGHT_CM
	)
	_player_seeker.z_index = lane
	if is_instance_valid(_player_seeker_shadow):
		_player_seeker_shadow.z_index = lane


func _order_stage_fighters() -> void:
	if not is_instance_valid(_fighter_layer):
		return
	var fighters: Array[Node] = [_player_anchor, _opponent_anchor]
	if is_instance_valid(_seeker):
		fighters.append(_seeker)
	fighters.sort_custom(func(left: Node, right: Node) -> bool: return left.z_index < right.z_index)
	for fighter in fighters:
		_fighter_layer.move_child(fighter, -1)
	if is_instance_valid(_seeker) and is_instance_valid(_seeker_shadow):
		_fighter_layer.move_child(_seeker_shadow, _seeker.get_index())


func _active_body_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array([0.0, 0.0, 0.0])
	var state := GameState.as_dict(_session.get("state"))
	var player_party := GameState.as_dict(state.get("player"))
	var opponent_party := GameState.as_dict(state.get("opponent"))
	var player_roster := _as_array(player_party.get("roster"))
	var opponent_roster := _as_array(opponent_party.get("roster"))
	var player_slot := int(player_party.get("active_slot", -1))
	var opponent_slot := int(opponent_party.get("active_slot", -1))
	if player_slot >= 0 and player_slot < player_roster.size():
		heights[0] = float(
			GameState.as_dict(player_roster[player_slot]).get(
				"body_height_cm", BattleScale.BODY_HEIGHT_REFERENCE_CM
			)
		)
	if opponent_slot >= 0 and opponent_slot < opponent_roster.size():
		heights[1] = float(
			GameState.as_dict(opponent_roster[opponent_slot]).get(
				"body_height_cm", BattleScale.BODY_HEIGHT_REFERENCE_CM
			)
		)
	if (
		is_instance_valid(_seeker)
		and _seeker.has_sheet()
		and not GameState.as_dict(_session.get("boss_seeker")).is_empty()
	):
		heights[2] = float(
			GameState.as_dict(_session.get("boss_seeker")).get(
				"body_height_cm", BattleScale.BODY_HEIGHT_REFERENCE_CM
			)
		)
	return heights


func _apply_fighter_scales(session: Dictionary) -> PackedFloat32Array:
	var scales := _arena_scales(session)
	if scales.size() >= 2:
		_player_anchor.scale = Vector2(scales[0], scales[0])
		_opponent_anchor.scale = Vector2(scales[1], scales[1])
	return scales


func _arena_scales(session: Dictionary) -> PackedFloat32Array:
	var state := GameState.as_dict(session.get("state"))
	var player_party := GameState.as_dict(state.get("player"))
	var opponent_party := GameState.as_dict(state.get("opponent"))
	var player_roster := _as_array(player_party.get("roster"))
	var opponent_roster := _as_array(opponent_party.get("roster"))
	var player_slot := int(player_party.get("active_slot", -1))
	var opponent_slot := int(opponent_party.get("active_slot", -1))
	if (
		player_slot < 0 or player_slot >= player_roster.size()
		or opponent_slot < 0 or opponent_slot >= opponent_roster.size()
	):
		return PackedFloat32Array()
	var player_member := GameState.as_dict(player_roster[player_slot])
	var opponent_member := GameState.as_dict(opponent_roster[opponent_slot])
	var heights: Array = [
		float(player_member.get("body_height_cm", BattleScale.BODY_HEIGHT_REFERENCE_CM)),
		float(opponent_member.get("body_height_cm", BattleScale.BODY_HEIGHT_REFERENCE_CM)),
	]
	var loadeds: Array = [
		GameState.as_dict(_art_cache.get(str(player_member.get("anima_id", "")))),
		GameState.as_dict(_art_cache.get(str(opponent_member.get("anima_id", "")))),
	]
	if (
		is_instance_valid(_seeker)
		and _seeker.has_sheet()
		and not GameState.as_dict(session.get("boss_seeker")).is_empty()
	):
		var seeker := GameState.as_dict(session.get("boss_seeker"))
		heights.append(
			float(seeker.get("body_height_cm", BattleScale.BODY_HEIGHT_REFERENCE_CM))
		)
		loadeds.append(_seeker_loaded)
	return BattleScale.shared_scales(heights, loadeds, _battle_stage.size)


func _position_seeker() -> void:
	if not is_instance_valid(_seeker) or not _seeker.has_sheet():
		if is_instance_valid(_seeker_shadow):
			_seeker_shadow.visible = false
		return
	var scales := _arena_scales(_session)
	if scales.size() < 3:
		return
	var seeker_scale := scales[2]
	# The camera owns the final fit. Place the visible body in the shot first;
	# transparent 3×3 cell padding must not affect composition.
	var x := (
		_battle_stage.size.x * SEEKER_SHOT_X
		- BattleScale.seeker_opaque_center(_seeker_loaded) * seeker_scale
	)
	_seeker.set_layout(Vector2(x, _opponent_anchor.position.y), seeker_scale)
	_seeker.sync_ground_shadow(_seeker_shadow)


## Cermin `_position_seeker()`: sisi pemain, ground line yang sama, dan tanda
## `BattleScale.seeker_opaque_center()` terbalik karena figurnya di-`flip_h`. Skalanya
## sengaja berdiri sendiri alih-alih ikut `_arena_scales()` — Team Battle biasa
## tidak punya Seeker sama sekali di sana, dan menambahkannya akan mengubah
## ukuran setiap Anima yang sudah dikalibrasi.
func _position_player_seeker() -> void:
	if not is_instance_valid(_player_seeker) or not _player_seeker.has_sheet():
		if is_instance_valid(_player_seeker_shadow):
			_player_seeker_shadow.visible = false
		return
	var avatar_scale := BattleScale.fighter_scale(
		PLAYER_SEEKER_HEIGHT_CM, _player_seeker_loaded, _battle_stage.size
	)
	var x := (
		_battle_stage.size.x * PLAYER_SEEKER_SHOT_X
		+ BattleScale.seeker_opaque_center(_player_seeker_loaded) * avatar_scale
	)
	_player_seeker.set_layout(Vector2(x, _player_anchor.position.y), avatar_scale)
	_apply_player_seeker_layer()
	# Zoom yang sedang berlaku, bukan yang akan datang: dipanggil dari
	# `_position_fighters()` layer-nya baru di-reset ke 1.0 dan `_apply_dynamic_camera()`
	# menjepit ulang sesudahnya, sementara dipanggil dari `set_player_avatar()`
	# kamera sudah final dan figur baru harus langsung mendarat di tepinya.
	_pin_player_seeker_to_camera_left(_fighter_layer.scale.x)
	_player_seeker.sync_ground_shadow(_player_seeker_shadow)


func _play_damage(amount: int, multiplier: float) -> void:
	if not is_instance_valid(_damage):
		return
	var color := BattleView.DAMAGE_COLOR
	if multiplier > 1.0:
		color = BattleView.EFFECTIVE_COLOR
	elif multiplier < 1.0:
		color = BattleView.RESISTED_COLOR
	_damage.text = tr("BATTLE_DAMAGE") % LocaleManager.format_integer(amount)
	_damage.add_theme_color_override("font_color", color)
	_damage.visible = true
	_damage.modulate = Color.WHITE
	_damage.pivot_offset = _damage.size * 0.5
	_damage.scale = Vector2(0.72, 0.72)
	var damage_start_y := _damage.position.y
	var float_damage := create_tween()
	float_damage.tween_property(_damage, "scale", Vector2(1.22, 1.22), 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	float_damage.parallel().tween_property(_damage, "position:y", damage_start_y - 10.0, 0.10)
	float_damage.tween_property(_damage, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	float_damage.parallel().tween_property(_damage, "position:y", damage_start_y - 20.0, 0.12)
	float_damage.tween_interval(0.06)
	float_damage.tween_property(_damage, "modulate:a", 0.0, 0.16)
	float_damage.parallel().tween_property(_damage, "position:y", damage_start_y - 42.0, 0.16)
	await float_damage.finished
	_damage.position.y = damage_start_y
	_damage.scale = Vector2.ONE
	_damage.modulate = Color.WHITE
	_damage.visible = false


func _readability_pause(seconds: float = ACTION_CUE_SEC) -> void:
	await get_tree().create_timer(seconds).timeout


func _event_pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _is_boss_encounter() -> bool:
	return (
		str(_session.get("kind", "")) == "boss"
		and not GameState.as_dict(_session.get("boss_seeker")).is_empty()
	)


func _reset_spoken_if_needed() -> void:
	var session_id := str(_session.get("id", ""))
	if session_id == _spoken_session:
		return
	_spoken_session = session_id
	_spoken = {}
	_intro_started = false
	_intro_pending_summon = false
	_command_dialogue_used = false
	_final_ace_pending = false
	_boss_result_pending = false


func _present_seeker() -> void:
	if not is_instance_valid(_seeker):
		return
	if not _is_boss_encounter():
		_seeker.clear()
		return
	var loaded := GameState.as_dict(_art_cache.get("boss_seeker"))
	if bool(loaded.get("ok", false)):
		_seeker_loaded = loaded.duplicate(true)
		_seeker.apply(loaded)
		_position_seeker()
	else:
		_seeker_loaded = {}
		_seeker.clear()


func _should_boss_intro() -> bool:
	return (
		_is_boss_encounter()
		and str(_session.get("status", "")) == "active"
		and int(_session.get("turn_number", 1)) <= 1
		and not _intro_started
		and not bool(_spoken.get("boss_intro", false))
		and not bool(_spoken.get("rematch", false))
	)


func _begin_boss_intro() -> void:
	var trigger := "rematch" if int(_session.get("zone_attempt", 1)) > 1 else "boss_intro"
	_position_seeker()
	await _speak_seeker(trigger, "intro_idle", false)
	await _summon_boss_opening()
	if str(_session.get("status", "")) == "active":
		_busy = false
		_update_arena_actions()


func _summon_boss_opening() -> void:
	if not _intro_pending_summon or not _is_boss_encounter():
		_intro_pending_summon = false
		return
	if is_instance_valid(_seeker) and _seeker.has_sheet():
		_seeker.set_pose("switch_command")
	await _event_pause(0.42)
	_intro_pending_summon = false
	_apply_side(_session, "opponent", true, false)
	# Intro forced the opponent above the Seeker; recompute before reveal.
	_position_fighters()
	var sprite := _opponent_sprite
	var portal := _opponent_portal
	if not is_instance_valid(sprite):
		_apply_side(_session, "opponent", true)
		_restore_seeker_idle()
		return
	_align_portal("opponent")
	if is_instance_valid(portal):
		await portal.start_portal()
		portal.burst()
	if sprite.sprite_frames != null:
		await sprite.summon_reveal()
		_sync_shadow("opponent")
	else:
		sprite.visible = true
	_restore_seeker_idle()


func _react_seeker_attack(event: Dictionary) -> void:
	if (
		not _is_boss_encounter()
		or not is_instance_valid(_seeker)
		or str(event.get("target", "")) != "opponent"
	):
		return
	_seeker.set_pose("concern_hit")


func _cue_seeker_command(trigger: String, pose: String) -> void:
	if not _is_boss_encounter() or not is_instance_valid(_seeker):
		return
	if not _command_dialogue_used:
		var shown := await _speak_seeker(trigger, pose, true, false)
		if shown:
			_command_dialogue_used = true
			return
	await _cue_seeker_pose(pose, true)


func _cue_seeker_pose(pose: String, cut_in: bool = false) -> void:
	if not _is_boss_encounter() or not is_instance_valid(_seeker):
		return
	_seeker.set_pose(pose)
	if cut_in:
		_seeker.play_cut_in()
	await _event_pause(0.42 if cut_in else 0.28)


func _cue_final_ace() -> void:
	_final_ace_pending = true
	await _speak_seeker("last_anima", "last_anima", true, false)


func _play_ace_passive(event: Dictionary) -> void:
	var text := str(event.get("copy", "")).strip_edges()
	if text.is_empty():
		text = tr("TEAM_ACE_PASSIVE") % str(event.get("passive_name", ""))
	await _present_banner(text, BattleView.EFFECTIVE_COLOR, true, BattleView.ToastType.SUCCESS)
	await _hide_effectiveness()


func _restore_seeker_idle() -> void:
	if is_instance_valid(_seeker) and str(_session.get("status", "")) == "active":
		_seeker.set_pose("intro_idle")


## Pemetaan pose sisi pemain dimiliki view, sama seperti pemisahan yang sudah
## berlaku untuk Boss Seeker: perintah saat Attack/Special/Switch, khawatir saat
## Anima pemain kena, menang atau kalah di penutup, idle di antaranya.
func _set_player_seeker_pose(pose: String) -> void:
	if is_instance_valid(_player_seeker) and _player_seeker.has_sheet():
		_player_seeker.set_pose(pose)


func _restore_player_seeker_idle() -> void:
	# Jangan timpa balik "defeat"/"victory" yang baru saja ditetapkan inline oleh
	# knockout/status event ini -- _session.status masih lama sampai
	# set_session() di akhir play_events(), sama seperti BattleView.
	if is_instance_valid(_player_seeker) and _player_seeker.animation in ["defeat", "victory"]:
		return
	if str(_session.get("status", "")) == "active":
		_set_player_seeker_pose("intro_idle")


func _react_player_seeker_attack(event: Dictionary) -> void:
	if str(event.get("target", "")) == "player":
		_set_player_seeker_pose("concern_hit")
		if is_instance_valid(_player_seeker):
			_player_seeker.shake_impact()


func _speak_seeker(
	trigger: String,
	pose: String,
	cut_in: bool,
	restore_idle: bool = true
) -> bool:
	if bool(_spoken.get(trigger, false)) or not _is_boss_encounter():
		return false
	var seeker := GameState.as_dict(_session.get("boss_seeker"))
	var line := str(GameState.as_dict(seeker.get("dialogue")).get(trigger, "")).strip_edges()
	if line.is_empty():
		return false
	_spoken[trigger] = true
	if is_instance_valid(_seeker):
		_seeker.set_pose(pose)
		if cut_in:
			_seeker.play_cut_in()
	if is_instance_valid(_seeker_dialog):
		await _seeker_dialog.present(
			str(seeker.get("display_name", "")),
			line,
			SEEKER_SHEET.portrait(
				GameState.as_dict(_art_cache.get("boss_seeker")),
				str(seeker.get("portrait_pose", "profile"))
			)
		)
	if restore_idle and is_instance_valid(_seeker) and str(_session.get("status", "")) == "active":
		_seeker.set_pose("intro_idle")
	return true


func _present_boss_result(status: String) -> void:
	if status == "won":
		await _speak_seeker("victory", "defeat", false, false)
		await _present_trophy()
	else:
		await _speak_seeker("defeat", "victory", false, false)
	_show_result(status)
	_result.visible = true
	_set_result_actions_visible(true)
	_boss_result_pending = false
	_boss_result_settled.emit()


## Trophy first-clear diumumkan tepat sesudah baris terakhir Seeker dan sebelum
## ringkasan hadiah, memakai dialog tap-to-continue yang sama. Reward tanpa
## trophy melewatinya, dan replay tidak mengulang pengumumannya.
func _present_trophy() -> void:
	var trophy := GameState.as_dict(
		GameState.as_dict(_session.get("last_reward")).get("trophy")
	)
	var trophy_name := str(trophy.get("display_name", "")).strip_edges()
	if trophy_name.is_empty() or bool(_spoken.get("trophy", false)):
		return
	_spoken["trophy"] = true
	if not is_instance_valid(_seeker_dialog):
		return
	await _seeker_dialog.present(
		trophy_name,
		tr("EXPEDITION_TROPHY_AWARDED") % trophy_name,
		_art_cache.get("trophy") as Texture2D
	)


static func _as_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
