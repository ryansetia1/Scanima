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

const SURGE_COST := 1
const ACTION_CUE_SEC := 1.4
const SEEKER_EDGE_PAD := 12.0
const DIM := Color(1.0, 1.0, 1.0, 0.42)
const BATTLE_EVENT := preload("res://scripts/battle_event.gd")
const CARE_RULES: GDScript = preload("res://scripts/care_rules.gd")
const BOSS_SEEKER_PRESENTER := preload("res://scripts/boss_seeker_presenter.gd")
const BOSS_SEEKER_DIALOG := preload("res://scripts/boss_seeker_dialog.gd")
const BOSS_SEEKER_SHEET := preload("res://scripts/boss_seeker_sheet.gd")
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
@onready var _builder: VBoxContainer = %TeamBuilder
@onready var _builder_meta: Label = %TeamBuilderMeta
@onready var _roster_list: ItemList = %TeamRosterList
@onready var _save_button: Button = %TeamSaveButton
@onready var _lobby: VBoxContainer = %TeamLobby
@onready var _lineup: Label = %TeamLineup
@onready var _reward_status: Label = %TeamRewardStatus
@onready var _rival_list: ItemList = %TeamRivalList
@onready var _edit_button: Button = %TeamEditButton
@onready var _defense_button: Button = %TeamDefenseButton
@onready var _refresh_button: Button = %TeamRefreshButton
@onready var _start_button: Button = %TeamStartButton
@onready var _arena: VBoxContainer = %TeamArena
@onready var _arena_hud: PanelContainer = %ArenaHud
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

var _roster: Array = []
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
var _action_commits: Dictionary = {}
var _switch_meters: Array[ProgressBar] = []
var _player_portal: IncubatorEffect
var _opponent_portal: IncubatorEffect
var _player_shadow: Sprite2D
var _opponent_shadow: Sprite2D
var _seeker: BOSS_SEEKER_PRESENTER
var _seeker_dialog: BOSS_SEEKER_DIALOG
var _seeker_loaded: Dictionary = {}
var _spoken: Dictionary = {}
var _spoken_session := ""
var _intro_started := false
var _intro_pending_summon := false
var _command_dialogue_used := false
var _final_ace_pending := false
var _switch_overlay: Control
var _switch_sheet: PanelContainer


func _ready() -> void:
	_back.tooltip_text = tr("ACTION_BACK")
	_roster_list.fixed_icon_size = Vector2i(96, 96)
	_roster_list.max_columns = 1
	_roster_list.fixed_column_width = 0
	_back.pressed.connect(back_requested.emit)
	_roster_list.connect("selection_changed", _update_builder)
	_save_button.pressed.connect(_save_team)
	_rival_list.item_selected.connect(_select_candidate)
	_edit_button.pressed.connect(_edit_team)
	_defense_button.pressed.connect(_toggle_defense)
	_refresh_button.pressed.connect(_refresh_candidates)
	_start_button.pressed.connect(_start_candidate)
	_attack_button.pressed.connect(_request_action.bind("strike", -1))
	_special_button.pressed.connect(_request_action.bind("surge", -1))
	_guard_button.pressed.connect(_request_action.bind("guard", -1))
	_item_button.pressed.connect(item_picker_requested.emit)
	_switch_button.pressed.connect(_open_switch_picker.bind(false))
	_switch_cancel.pressed.connect(_close_switch_picker)
	_forfeit.pressed.connect(forfeit_requested.emit)
	_retry.pressed.connect(retry_requested.emit)
	for slot in _switch_buttons.size():
		_switch_buttons[slot].pressed.connect(_request_switch.bind(slot))
	_battle_stage.resized.connect(_position_fighters)
	_player_sprite.set_facing(1.0)
	_opponent_sprite.set_facing(-1.0)
	_player_sprite.z_index = 2
	_opponent_sprite.z_index = 2
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
	_feedback.visible = false
	_player_portal = _make_portal(_player_anchor)
	_opponent_portal = _make_portal(_opponent_anchor)
	_player_shadow = _make_ground_shadow(_player_anchor)
	_opponent_shadow = _make_ground_shadow(_opponent_anchor)
	_seeker = BOSS_SEEKER_PRESENTER.new()
	_seeker.name = "BossSeeker"
	_battle_stage.add_child(_seeker)
	_seeker_dialog = BOSS_SEEKER_DIALOG.new()
	_seeker_dialog.name = "BossSeekerDialog"
	add_child(_seeker_dialog)
	_position_fighters.call_deferred()


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


func set_expedition_mode(enabled: bool) -> void:
	_expedition_mode = enabled
	_retry.text = tr("EXPEDITION_RETURN_MAP") if enabled else tr("TEAM_RETRY")
	_sync_header()
	_sync_location_chrome()


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
	if _session.is_empty() or str(_session.get("status", "")) != "active":
		back_requested.emit()
		return true
	return false


func set_loading(message_key: String = "TEAM_LOADING") -> void:
	_show_only(_loading)
	_loading_label.text = tr(message_key)
	_back.disabled = _busy


func set_builder(roster: Array, existing_team: Dictionary = {}) -> void:
	_session = {}
	_roster = roster.duplicate(true)
	_team = existing_team.duplicate(true)
	_roster_list.clear()
	var selected_ids := _team_member_ids(_team)
	for value in _roster:
		var row := GameState.as_dict(value)
		if row.is_empty():
			continue
		var unavailable := _team_member_unavailable(row)
		var label := tr("TEAM_ROSTER_ROW") % [
			LocaleManager.display_name(row),
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
		if unavailable.is_empty() and str(row.get("id", "")) in selected_ids:
			_roster_list.select(index, false)
		if not unavailable.is_empty():
			_roster_list.set_item_icon_modulate(index, DIM)
	if _roster_list.has_method("sync_chosen"):
		_roster_list.sync_chosen()
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
	_show_banner(tr("BATTLE_RETREATING"), BattleView.CUE_COLOR, false)


func set_error(error_code: String) -> void:
	_effectiveness.visible = false
	_clear_action_commit()
	_show_only(_loading)
	_loading_label.text = _error_copy(error_code)
	_retry.visible = true
	_back.disabled = false


func set_busy(busy: bool) -> void:
	_busy = busy
	if not busy and is_instance_valid(_seeker_dialog) and _seeker_dialog.is_open():
		_busy = true
	if not _busy:
		_clear_action_commit()
	_back.disabled = _busy
	_save_button.disabled = _busy or _selected_roster_ids().size() != 4
	_update_lobby_actions()
	_update_arena_actions()
	if not _busy and _forced_switch():
		_open_switch_picker(true)


func set_session(session: Dictionary, art_cache: Dictionary = {}) -> void:
	_session = session.duplicate(true)
	_art_cache.merge(art_cache, true)
	_reset_spoken_if_needed()
	_show_only(_arena)
	_apply_arena_background(art_cache)
	_present_seeker()
	if _should_boss_intro():
		_intro_started = true
		_intro_pending_summon = true
		_busy = true
	_apply_session_state()
	if _intro_pending_summon:
		_begin_boss_intro()


func session_data() -> Dictionary:
	return _session.duplicate(true)


func _apply_arena_background(art_cache: Dictionary) -> void:
	var texture: Variant = art_cache.get("arena_background", _art_cache.get("arena_background"))
	var ready := texture is Texture2D
	if ready:
		_arena_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_arena_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_arena_background.texture = texture
	else:
		_arena_background.texture = null
	_arena_background.visible = ready


func begin_action(action: String) -> void:
	if _busy and _queued_action == action:
		return
	_busy = true
	_show_action_commit(action)
	if not UiMotion.reduced_motion:
		Input.vibrate_handheld(18)
	_update_arena_actions()


func play_events(
	events: Array,
	next_session: Dictionary,
	art_cache: Dictionary = {}
) -> void:
	_art_cache.merge(art_cache, true)
	set_busy(true)
	for value in events:
		var event := GameState.as_dict(value)
		match str(event.get("type", "")):
			"guard":
				var guard_actor := str(event.get("actor", ""))
				if guard_actor == "opponent":
					await _cue_seeker_pose("concern_hit")
				await _present_banner(
					tr("BATTLE_EVENT_GUARD") % _actor_name(guard_actor),
					BattleView.CUE_COLOR,
					false
				)
				await _hide_effectiveness()
				if guard_actor == "opponent":
					_restore_seeker_idle()
			"item":
				var item_actor := str(event.get("actor", "player"))
				await _present_banner(
					tr("BATTLE_EVENT_ITEM") % _actor_name(item_actor),
					BattleView.CUE_COLOR,
					false
				)
				var item_sprite := _sprite_for(item_actor)
				if is_instance_valid(item_sprite):
					item_sprite.care_feedback("item")
				await _present_banner(
					BattleView.item_banner_text(event),
					BattleView.EFFECTIVE_COLOR,
					true
				)
				await _hide_effectiveness()
			"final_ace":
				await _cue_final_ace()
			"switch":
				var switch_actor := str(event.get("actor", ""))
				if switch_actor == "opponent" and not _final_ace_pending:
					await _cue_seeker_command("first_switch", "switch_command")
				await _play_switch(event, next_session)
				if switch_actor == "opponent" and not _final_ace_pending:
					_restore_seeker_idle()
			"ace_passive":
				await _play_ace_passive(event)
				_final_ace_pending = false
				_restore_seeker_idle()
			"attack":
				var attack_actor := str(event.get("actor", ""))
				if attack_actor == "opponent":
					var action := str(event.get("action", ""))
					await _cue_seeker_command(
						"first_special" if action == "surge" else "first_attack",
						"special_command" if action == "surge" else "attack_command"
					)
				await _play_attack(event)
				if attack_actor == "opponent":
					_restore_seeker_idle()
				else:
					await _react_seeker_attack(event)
			"knockout":
				var side := str(event.get("actor", ""))
				await _present_banner(
					tr("BATTLE_EVENT_KO") % _actor_name(side),
					BattleView.DAMAGE_COLOR,
					true
				)
				_sprite_for(side).set_pose("defeated")
				# Hold the faint so a KO is readable before the replacement picker.
				await _event_pause(1.2)
				await _hide_effectiveness()
			"timeout":
				await _present_banner(tr("BATTLE_EVENT_TIMEOUT"), BattleView.DAMAGE_COLOR, false)
				await _hide_effectiveness()
	if _final_ace_pending:
		_final_ace_pending = false
		_restore_seeker_idle()
	set_session(next_session)
	set_busy(false)


func _show_only(panel: Control) -> void:
	for child in [_loading, _builder, _lobby, _arena]:
		(child as Control).visible = child == panel
	_result.visible = false
	_retry.visible = false
	_sync_header()
	_emit_arena_open()


func _sync_header() -> void:
	# Arena is a full-bleed fight. Back/title only belong on builder/lobby.
	_header.visible = not _expedition_mode and _session.is_empty()
	_sync_location_chrome()


func _sync_location_chrome() -> void:
	var show := (
		_expedition_mode
		and _arena.visible
		and not _session.is_empty()
		and not _arena_location.is_empty()
	)
	_turn.text = _arena_location
	_turn.visible = show
	if not is_instance_valid(_arena_hud):
		return
	if show:
		_arena_hud.offset_top = 48.0
		_arena_hud.offset_bottom = 196.0
		_effectiveness.offset_top = 208.0
		_effectiveness.offset_bottom = 290.0
	else:
		_arena_hud.offset_top = 8.0
		_arena_hud.offset_bottom = 156.0
		_effectiveness.offset_top = 184.0
		_effectiveness.offset_bottom = 266.0


func _update_builder() -> void:
	var count := _selected_roster_ids().size()
	_builder_meta.text = tr("TEAM_BUILDER_COUNT") % [
		LocaleManager.format_integer(count),
		LocaleManager.format_integer(4),
	]
	_save_button.disabled = _busy or count != 4


func _selected_roster_ids() -> Array[String]:
	var ids: Array[String] = []
	for index in _roster_list.get_selected_items():
		var row := GameState.as_dict(_roster_list.get_item_metadata(index))
		var anima_id := str(row.get("id", ""))
		if not anima_id.is_empty():
			ids.append(anima_id)
	return ids


func _save_team() -> void:
	var ids := _selected_roster_ids()
	if _busy or ids.size() != 4:
		return
	save_team_requested.emit(ids)


func _edit_team() -> void:
	set_builder(_roster, _team)


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
	_start_button.disabled = _busy or _selected_candidate.is_empty()


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
	# TeamArena is a VBoxContainer: a FULL_RECT child becomes a zero-height row.
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
	add_child(overlay)
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
			meter.max_value = float(max_hp)
			meter.value = float(hp)
			meter.visible = true
	_switch_cancel.visible = not forced
	_switch_panel.visible = true
	_layout_switch_panel()
	if is_instance_valid(_switch_overlay):
		_switch_overlay.visible = true
	_layout_switch_panel.call_deferred()
	_actions.visible = true


func _close_switch_picker() -> bool:
	if not _switch_panel.visible or _forced_switch() or _busy:
		return false
	_hide_switch_overlay()
	_actions.visible = true
	return true


func _apply_session_state() -> void:
	var state := GameState.as_dict(_session.get("state"))
	var status := str(_session.get("status", state.get("status", "active")))
	_sync_location_chrome()
	_effectiveness.visible = false
	_apply_side(_session, "player", true)
	_apply_side(_session, "opponent", true, not _intro_pending_summon)
	_position_seeker()
	_player_slots.text = _slots_text("player")
	_opponent_slots.text = _slots_text("opponent")
	_forfeit.visible = status == "active"
	_result.visible = status != "active"
	_retry.visible = status != "active"
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
			_retry.visible = false
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
	name_label.text = _fighter_title(member)
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
		hp.max_value = maxf(1.0, float(member.get("max_hp", 1)))
		hp.value = float(member.get("hp", 0))
		hp_value.text = LocaleManager.format_ratio(
			int(member.get("hp", 0)),
			int(member.get("max_hp", 1))
		)


func _play_switch(event: Dictionary, next_session: Dictionary) -> void:
	var side := str(event.get("actor", ""))
	var slot := int(event.get("to_slot", 0))
	await _present_banner(
		tr("TEAM_EVENT_SWITCH") % _member_name(next_session, side, slot),
		BattleView.CUE_COLOR,
		false
	)
	var sprite := _sprite_for(side)
	var portal := _portal_for(side)
	if UiMotion.reduced_motion or not is_instance_valid(sprite):
		_apply_side(next_session, side, true)
		return
	if sprite.visible and sprite.sprite_frames != null:
		await sprite.summon_dissolve()
	_apply_side(next_session, side, true, false)
	_align_portal(side)
	if is_instance_valid(portal):
		await portal.start_portal()
		portal.burst()
	if sprite.sprite_frames != null:
		await sprite.summon_reveal()
		_sync_shadow(side)
	else:
		sprite.visible = true
	await _hide_effectiveness()


func _play_attack(event: Dictionary) -> void:
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
		false
	)
	actor.set_pose("attack")
	if is_instance_valid(target):
		var fx := "fx_surge" if str(event.get("action", "")) == "surge" else "fx_strike"
		actor.play_fx(fx, target.body_center_global())
	var element_multiplier := float(event.get("element_multiplier", 1.0))
	var effect_key := BattleView.effectiveness_key(element_multiplier)
	await _event_pause(AnimaPresenter.FX_TRAVEL_SEC)
	var hp := int(event.get("target_hp", 0))
	if target_side == "player":
		_player_hp.value = hp
		_player_hp_value.text = LocaleManager.format_ratio(hp, int(_player_hp.max_value))
	else:
		_opponent_hp.value = hp
		_opponent_hp_value.text = LocaleManager.format_ratio(hp, int(_opponent_hp.max_value))
	if is_instance_valid(target):
		target.hit_react()
		if UiMotion.reduced_motion:
			target.modulate = Color.WHITE
		else:
			target.modulate = Color(1.65, 0.45, 0.55, 1.0)
			var flash := create_tween()
			flash.tween_property(target, "modulate", Color.WHITE, 0.28)
			Input.vibrate_handheld(55 if element_multiplier > 1.0 else 35)
	await _play_damage(int(event.get("damage", 0)), element_multiplier)
	if not effect_key.is_empty():
		await _present_banner(
			tr(effect_key),
			BattleView.EFFECTIVE_COLOR if effect_key == "BATTLE_EFFECTIVE" else BattleView.RESISTED_COLOR,
			effect_key == "BATTLE_EFFECTIVE"
		)
	await _hide_effectiveness()
	actor.set_pose("idle")


func _present_banner(text: String, color: Color, big: bool = true) -> void:
	_show_banner(text, color, big)
	if is_instance_valid(_effectiveness_tween):
		await _effectiveness_tween.finished
	await _readability_pause()


func _show_effectiveness(multiplier: float) -> void:
	var key := BattleView.effectiveness_key(multiplier)
	var color := BattleView.DAMAGE_COLOR
	if key == "BATTLE_EFFECTIVE":
		color = BattleView.EFFECTIVE_COLOR
	elif key == "BATTLE_NOT_EFFECTIVE":
		color = BattleView.RESISTED_COLOR
	_show_banner(tr(key) if not key.is_empty() else "", color, key == "BATTLE_EFFECTIVE")


func _show_banner(text: String, color: Color, big: bool = true) -> void:
	if is_instance_valid(_effectiveness_tween):
		_effectiveness_tween.kill()
	_effectiveness.visible = not text.is_empty()
	if not _effectiveness.visible:
		return
	_effectiveness.modulate = Color.WHITE
	_effectiveness.scale = Vector2.ONE
	_effectiveness.pivot_offset = _effectiveness.size * 0.5
	_effectiveness_label.text = text
	_effectiveness_label.add_theme_color_override("font_color", color)
	_effectiveness_label.add_theme_color_override(
		"font_shadow_color", Color(color.r, color.g, color.b, 0.48)
	)
	_effectiveness_label.add_theme_font_size_override("font_size", 40 if big else 32)
	if UiMotion.reduced_motion:
		return
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
	if UiMotion.reduced_motion:
		_effectiveness.visible = false
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
	var locked := _busy or _forced_switch()
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
	_item_button.disabled = (
		not active or _item_already_used() or (locked and not committed)
	)
	_switch_button.disabled = (
		not active or not _has_living_bench() or (locked and not committed)
	)
	var accepts_input := active and not _busy and not _forced_switch()
	for button in [_attack_button, _special_button, _guard_button, _item_button, _switch_button]:
		var action_button := button as Button
		action_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if accepts_input and not action_button.disabled
			else Control.MOUSE_FILTER_IGNORE
		)
	_forfeit.disabled = not active or _busy


func _show_result(status: String) -> void:
	var reward := GameState.as_dict(_session.get("last_reward"))
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match status:
		"won":
			_result_title.text = tr(
				"EXPEDITION_ENCOUNTER_WIN_TITLE" if _expedition_mode else "TEAM_WIN_TITLE"
			)
			var exp_lines := _exp_reward_lines(reward)
			_result_body.text = _win_reward_text(reward, exp_lines)
			if not exp_lines.is_empty():
				_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_player_sprite.set_pose("happy")
		"lost":
			_result_title.text = tr(
				"EXPEDITION_WIPE_TITLE" if _expedition_mode else "TEAM_LOSS_TITLE"
			)
			_result_body.text = tr(
				"EXPEDITION_WIPE_BODY" if _expedition_mode else "TEAM_LOSS_BODY"
			)
		"draw":
			_result_title.text = tr(
				"EXPEDITION_WIPE_TITLE" if _expedition_mode else "TEAM_DRAW_TITLE"
			)
			_result_body.text = tr(
				"EXPEDITION_WIPE_BODY" if _expedition_mode else "TEAM_DRAW_BODY"
			)
		_:
			_result_title.text = tr("BATTLE_FORFEIT_TITLE")
			_result_body.text = tr("BATTLE_FORFEIT_BODY")


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


func _forced_switch() -> bool:
	return bool(_party("player").get("forced_switch", false))


func _fighter_title(member: Dictionary) -> String:
	var anima_name := str(member.get("name", tr("ANIMA_FALLBACK_NAME")))
	var level := int(member.get("level", 0))
	if level <= 0:
		level = CARE_RULES.level_from_exp(int(member.get("care_score", 0)))
	return "%s %s" % [anima_name, LocaleManager.level_label(maxi(1, level))]


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


func _item_already_used() -> bool:
	var used: Variant = _session.get("item_used_id")
	return (
		used != null and not str(used).is_empty() and str(used) != "<null>"
	) or bool(_party("player").get("item_used", false))


func _total_reward_exp(reward: Dictionary) -> int:
	var total := 0
	for value in _as_array(reward.get("anima_exp")):
		total += int(GameState.as_dict(value).get("exp", 0))
	return total


func _win_reward_text(reward: Dictionary, exp_lines: PackedStringArray) -> String:
	if _expedition_mode:
		var tokens := tr("EXPEDITION_ENCOUNTER_WIN_TOKENS") % LocaleManager.format_integer(
			int(reward.get("supplies", 0))
		)
		return tokens if exp_lines.is_empty() else "%s\n%s" % [tokens, "\n".join(exp_lines)]
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
	if UiMotion.reduced_motion:
		commit.scale = Vector2.ONE
		return
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


func _sync_shadow(side: String) -> void:
	var sprite := _sprite_for(side)
	var shadow := _player_shadow if side == "player" else _opponent_shadow
	if is_instance_valid(sprite):
		sprite.sync_ground_shadow(shadow)


func _make_ground_shadow(anchor: Node2D) -> Sprite2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.01, 0.02, 0.05, 0.82),
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
	shadow.texture = texture
	shadow.z_index = 0
	shadow.position = Vector2(0.0, 8.0)
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


func _position_fighters() -> void:
	if not is_instance_valid(_battle_stage):
		return
	var ground_y := _battle_stage.size.y * 0.88
	_player_anchor.position = Vector2(_battle_stage.size.x * 0.27, ground_y)
	_opponent_anchor.position = Vector2(_battle_stage.size.x * 0.73, ground_y)
	_apply_fighter_scales(_session)
	_position_seeker()


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
		return
	var scales := _apply_fighter_scales(_session)
	if scales.size() < 3:
		return
	var seeker_scale := scales[2]
	var metrics := GameState.as_dict(_seeker_loaded.get("render_metrics"))
	var seeker_width := float(metrics.get("reference_width_px", 240.0))
	var frame_value: Variant = _seeker_loaded.get("frame_size", Vector2i(341, 341))
	var frame_w := 341.0
	if typeof(frame_value) == TYPE_VECTOR2I:
		frame_w = float((frame_value as Vector2i).x)
	elif typeof(frame_value) == TYPE_VECTOR2:
		frame_w = (frame_value as Vector2).x
	var min_x := float(metrics.get("reference_min_x_px", (frame_w - seeker_width) * 0.5))
	var opaque_right := (min_x + seeker_width) - frame_w * 0.5
	# ponytail: pin the opaque right edge, not the 341 empty frame. Ceiling:
	# no per-pose used-rect; upgrade if a command pose overhangs more than Idle.
	var x := _battle_stage.size.x - SEEKER_EDGE_PAD - maxf(opaque_right, 1.0) * seeker_scale
	var y := _opponent_anchor.position.y - _battle_stage.size.y * 0.055
	_seeker.set_layout(Vector2(x, y), seeker_scale)


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
	if UiMotion.reduced_motion:
		_damage.visible = false
		return
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
	if not UiMotion.reduced_motion:
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
	_position_seeker()
	var sprite := _opponent_sprite
	var portal := _opponent_portal
	if UiMotion.reduced_motion or not is_instance_valid(sprite):
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
	if not _is_boss_encounter() or not is_instance_valid(_seeker):
		return
	if str(event.get("target", "")) == "opponent":
		await _cue_seeker_pose("concern_hit")
		_restore_seeker_idle()


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
	await _present_banner(text, BattleView.EFFECTIVE_COLOR, true)
	await _hide_effectiveness()


func _restore_seeker_idle() -> void:
	if is_instance_valid(_seeker) and str(_session.get("status", "")) == "active":
		_seeker.set_pose("intro_idle")


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
			BOSS_SEEKER_SHEET.portrait(
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
	else:
		await _speak_seeker("defeat", "victory", false, false)
	_show_result(status)
	_result.visible = true
	_retry.visible = true


static func _as_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
