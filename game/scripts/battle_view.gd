class_name BattleView
extends Control

const BATTLE_EVENT := preload("res://scripts/battle_event.gd")

# Nama identifier mengikuti _shared/battle.mjs; kata player-facing "PP"/"Special"
# hidup di locales/ui.csv supaya wire value dan copy bisa berubah terpisah.
# Kedua angka wajib sama dengan modul itu: client yang lebih longgar akan
# menyalakan Special yang lalu ditolak server sebagai NO_MOMENTUM.
const MOMENTUM_MAX := 3
const SURGE_COST := 1
const ACTION_CUE_SEC := 1.4
# The opaque feet stay planted by AnimaPresenter; this line only chooses where
# that shared anchor sits in Duel's static arena composition.
const DUEL_GROUND_Y_RATIO := 0.82
const DUEL_BACKGROUND_MAX_SCALE := 1.18
const CUE_COLOR := Color(0.92, 0.97, 1.0, 1.0)
const DAMAGE_COLOR := Color(1.0, 0.35, 0.48, 1.0)
const HP_FULL_COLOR := Color(0.28, 0.90, 1.0, 1.0)
const HP_WARNING_COLOR := Color(1.0, 0.58, 0.20, 1.0)
const HP_EMPTY_COLOR := DAMAGE_COLOR
const EFFECTIVE_COLOR := Color(1.0, 0.82, 0.4, 1.0)
const RESISTED_COLOR := Color(0.55, 0.68, 0.9, 1.0)

signal start_requested
signal choose_anima_requested
signal team_mode_requested
signal expedition_mode_requested
signal action_requested(action: String)
signal item_picker_requested
signal resume_requested
signal forfeit_requested
signal reward_status_refresh_requested
signal exit_requested
signal arena_open_changed(open: bool)

const BACKGROUND_DOF_SHADER: Shader = preload("res://shaders/battle_background_dof.gdshader")
const DUEL_BACKGROUND_DAY: Texture2D = preload(
	"res://assets/backgrounds/duel_day_background.png"
)
const DUEL_BACKGROUND_NIGHT: Texture2D = preload(
	"res://assets/backgrounds/duel_background.png"
)
const DUEL_BACKGROUND_DAY_LANDSCAPE: Texture2D = preload(
	"res://assets/backgrounds/duel_day_landscape_background.png"
)
const DUEL_BACKGROUND_NIGHT_LANDSCAPE: Texture2D = preload(
	"res://assets/backgrounds/duel_landscape_background.png"
)

@onready var _header: Control = %Header
@onready var _duel_column: VBoxContainer = %Column
@onready var _lobby_panel: PanelContainer = %BattleLobbyPanel
@onready var _lobby_name: Label = %BattleLobbyName
@onready var _lobby_meta: Label = %BattleLobbyMeta
@onready var _start_button: Button = %BattleStartButton
@onready var _team_button: Button = %BattleTeamButton
@onready var _team_view: TeamBattleView = %TeamBattleView
@onready var _expedition_button: Button = %BattleExpeditionButton
@onready var _expedition_view: ExpeditionView = %ExpeditionView
@onready var _battle_content: VBoxContainer = %BattleContent
@onready var _turn_label: Label = %BattleTurn
@onready var _daily_reward_label: Label = %BattleDailyReward
@onready var _player_name: Label = %BattlePlayerName
@onready var _bot_name: Label = %BattleBotName
@onready var _player_hp: ProgressBar = %BattlePlayerHp
@onready var _bot_hp: ProgressBar = %BattleBotHp
@onready var _player_hp_value: Label = %BattlePlayerHpValue
@onready var _bot_hp_value: Label = %BattleBotHpValue
@onready var _arena: Control = %BattleArena
@onready var _arena_background: TextureRect = %BattleArenaBackground
@onready var _player_anchor: Node2D = %BattlePlayerAnchor
@onready var _bot_anchor: Node2D = %BattleBotAnchor
@onready var _player_sprite: AnimaPresenter = %BattlePlayerSprite
@onready var _bot_sprite: AnimaPresenter = %BattleBotSprite
@onready var _feedback: Label = %BattleFeedback
@onready var _damage: Label = %BattleDamage
@onready var _effectiveness: Control = %BattleEffectiveness
@onready var _effectiveness_label: Label = %BattleEffectivenessLabel
@onready var _actions: GridContainer = %Actions
@onready var _strike_button: Button = %BattleStrikeButton
@onready var _surge_button: Button = %BattleSurgeButton
@onready var _guard_button: Button = %BattleGuardButton
@onready var _item_button: Button = %BattleItemButton
@onready var _strike_commit: ColorRect = %BattleStrikeCommit
@onready var _surge_commit: ColorRect = %BattleSurgeCommit
@onready var _guard_commit: ColorRect = %BattleGuardCommit
@onready var _item_commit: ColorRect = %BattleItemCommit
@onready var _forfeit_button: Button = %BattleForfeitButton
@onready var _result_panel: PanelContainer = %BattleResultPanel
@onready var _result_title: Label = %BattleResultTitle
@onready var _result_body: Label = %BattleResultBody
@onready var _retry_button: Button = %BattleRetryButton
@onready var _leave_button: Button = %BattleLeaveButton
@onready var _reward_reset_timer: Timer = %BattleRewardResetTimer

var _lobby_row: Dictionary = {}
var _result_body_base := ""
var _retry_picks_anima := false
var _lobby_daily_reward: Dictionary = {}
var _session: Dictionary = {}
var _busy := false
var _team_available := true
var _expedition_available := true
var _duel_pending := false
var _team_pending := false
var _expedition_pending := false
var _effectiveness_tween: Tween
var _queued_action := ""
var _last_reward: Dictionary = {}
var _command_tween: Tween
var _player_loaded: Dictionary = {}
var _bot_loaded: Dictionary = {}
var _fighter_layer: Node2D
var _art_cache: Dictionary = {}
var _background_session_id := ""
var _background_pan := 0.5
var _uses_static_background := false
var _background_material: ShaderMaterial
var _background_timer: Timer
var _player_shadow: Sprite2D
var _bot_shadow: Sprite2D


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_team_button.pressed.connect(team_mode_requested.emit)
	_expedition_button.pressed.connect(expedition_mode_requested.emit)
	_strike_button.pressed.connect(_request_action.bind("strike"))
	_surge_button.pressed.connect(_request_action.bind("surge"))
	_guard_button.pressed.connect(_request_action.bind("guard"))
	_item_button.pressed.connect(_request_item)
	_forfeit_button.pressed.connect(forfeit_requested.emit)
	_retry_button.pressed.connect(_on_retry_pressed)
	_leave_button.pressed.connect(exit_requested.emit)
	_arena.resized.connect(_position_fighters)
	_reward_reset_timer.timeout.connect(reward_status_refresh_requested.emit)
	_feedback.visible = false
	_turn_label.visible = false
	var fighter_index := _player_anchor.get_index()
	_fighter_layer = Node2D.new()
	_fighter_layer.name = "DuelFighterLayer"
	_arena.add_child(_fighter_layer)
	_arena.move_child(_fighter_layer, fighter_index)
	_player_anchor.reparent(_fighter_layer)
	_bot_anchor.reparent(_fighter_layer)
	_position_fighters.call_deferred()
	_player_sprite.set_facing(1.0)
	_bot_sprite.set_facing(-1.0)
	_player_sprite.z_index = 3
	_bot_sprite.z_index = 2
	_background_material = ShaderMaterial.new()
	_background_material.shader = BACKGROUND_DOF_SHADER
	_arena_background.material = _background_material
	_background_timer = Timer.new()
	_background_timer.name = "DuelBackgroundTimer"
	_background_timer.wait_time = 1.0
	_background_timer.autostart = true
	add_child(_background_timer)
	_background_timer.timeout.connect(_refresh_static_background)
	_player_shadow = _make_ground_shadow(_player_anchor)
	_bot_shadow = _make_ground_shadow(_bot_anchor)
	_player_sprite.pose_changed.connect(func(_pose: String) -> void: _sync_shadow("player"))
	_bot_sprite.pose_changed.connect(func(_pose: String) -> void: _sync_shadow("bot"))
	set_team_available(GameState.team_battle_available())
	set_expedition_available(GameState.expedition_available())
	set_lobby({})


func set_team_available(available: bool) -> void:
	_team_available = available
	_refresh_pending_entries()


func set_expedition_available(available: bool) -> void:
	_expedition_available = available
	_refresh_pending_entries()


func set_duel_pending(pending: bool) -> void:
	_duel_pending = pending
	_refresh_pending_entries()


func set_team_pending(pending: bool) -> void:
	_team_pending = pending
	_refresh_pending_entries()


func set_expedition_pending(pending: bool) -> void:
	_expedition_pending = pending
	_refresh_pending_entries()


func _refresh_pending_entries() -> void:
	var has_pending := _duel_pending or _team_pending or _expedition_pending
	_team_button.visible = true
	_team_button.text = tr("TEAM_CONTINUE" if _team_pending else "TEAM_OPEN")
	_team_button.disabled = (
		(not _team_available and not _team_pending)
		or (has_pending and not _team_pending)
	)
	_expedition_button.visible = true
	_expedition_button.text = tr(
		"EXPEDITION_CONTINUE" if _expedition_pending else "EXPEDITION_OPEN"
	)
	_expedition_button.disabled = (
		(not _expedition_available and not _expedition_pending)
		or (has_pending and not _expedition_pending)
	)
	if _session.is_empty() and _lobby_panel.visible:
		_apply_lobby()


func set_expedition_new(has_new: bool) -> void:
	%ExpeditionNewBadge.visible = has_new


func show_team_mode() -> void:
	_duel_column.visible = false
	_expedition_view.close_mode(true)
	_team_view.open_mode()
	_emit_arena_open()


func show_expedition_mode() -> void:
	_duel_column.visible = false
	_team_view.close_mode()
	if _team_view.is_open():
		return
	_expedition_view.open_mode()
	_emit_arena_open()


func show_duel_mode() -> void:
	_team_view.close_mode()
	_expedition_view.close_mode()
	if _team_view.is_open() or _expedition_view.is_open():
		return
	_duel_column.visible = true
	_emit_arena_open()


func is_team_mode() -> bool:
	return _team_view.is_open()


func is_expedition_mode() -> bool:
	return _expedition_view.is_open()


func set_lobby(row: Dictionary) -> void:
	_clear_action_commit()
	_lobby_row = row.duplicate(true)
	_session = {}
	_duel_pending = not GameState.pending_battle.is_empty()
	_team_pending = not GameState.pending_team_battle.is_empty()
	_expedition_pending = not GameState.pending_expedition.is_empty()
	_header.visible = true
	_lobby_panel.visible = true
	_battle_content.visible = false
	_result_panel.visible = false
	_start_button.visible = true
	_refresh_pending_entries()
	_emit_arena_open()


## Result CTA harus membaca Energy sesudah battle, bukan row lobby sebelum start.
func set_companion(row: Dictionary) -> void:
	_lobby_row = row.duplicate(true)
	if not can_leave_result():
		return
	_apply_result_actions(_is_training(_as_dict(_session.get("daily_reward"))))


func can_leave_result() -> bool:
	return (
		not _session.is_empty()
		and str(_session.get("status", "active")) != "active"
	)


func set_daily_reward(daily_reward: Dictionary) -> void:
	if daily_reward.is_empty():
		return
	_remember_lobby_daily_reward(daily_reward)
	if _session.is_empty():
		_apply_lobby()
	else:
		_session["daily_reward"] = daily_reward.duplicate(true)
		_apply_state()


func set_daily_reward_error() -> void:
	if not _session.is_empty():
		return
	_lobby_daily_reward = {}
	_apply_lobby()
	if _lobby_unavailable_key().is_empty():
		_lobby_meta.text = tr("BATTLE_REWARD_STATUS_ERROR")


func _remember_lobby_daily_reward(daily_reward: Dictionary) -> void:
	if daily_reward.is_empty():
		return
	_lobby_daily_reward = daily_reward.duplicate(true)
	_lobby_daily_reward["rewarded"] = false


func _apply_lobby() -> void:
	var unavailable_key := _lobby_unavailable_key()
	var training := _is_training(_lobby_daily_reward)
	var bits_capped := _is_bits_capped(_lobby_daily_reward)
	var other_pending_key := ""
	if _team_pending:
		other_pending_key = "BATTLE_PENDING_TEAM"
	elif _expedition_pending:
		other_pending_key = "BATTLE_PENDING_EXPEDITION"
	if _duel_pending:
		_lobby_name.text = LocaleManager.display_name(_lobby_row)
		_lobby_meta.text = tr("BATTLE_PENDING")
	elif not other_pending_key.is_empty():
		_lobby_name.text = LocaleManager.display_name(_lobby_row)
		_lobby_meta.text = tr(other_pending_key)
	elif not unavailable_key.is_empty():
		_lobby_name.text = tr(_lobby_title_key(unavailable_key))
		_lobby_meta.text = tr(unavailable_key)
	elif training and bits_capped:
		_lobby_name.text = LocaleManager.display_name(_lobby_row)
		_lobby_meta.text = tr("BATTLE_LOBBY_TRAINING") % [
			LocaleManager.format_integer(_display_bits_earned(_lobby_daily_reward)),
			LocaleManager.format_integer(int(_lobby_daily_reward.get("bits_limit", 100))),
		]
	elif training:
		_lobby_name.text = LocaleManager.display_name(_lobby_row)
		_lobby_meta.text = tr("BATTLE_LOBBY_TRAINING_BITS") % [
			LocaleManager.format_integer(_display_bits_earned(_lobby_daily_reward)),
			LocaleManager.format_integer(int(_lobby_daily_reward.get("bits_limit", 100))),
		]
	else:
		_lobby_name.text = LocaleManager.display_name(_lobby_row)
		_lobby_meta.text = tr("BATTLE_LOBBY_READY") % [
			LocaleManager.element_compact(_lobby_row),
			LocaleManager.level_label(CareRules.level_from_exp(int(_lobby_row.get("care_score", 0)))),
		]
	if unavailable_key.is_empty() and not _duel_pending and other_pending_key.is_empty():
		var care: Variant = _lobby_row.get("care")
		if CareRules.is_hungry(care):
			_lobby_meta.text = _lobby_meta.text + "\n" + tr("BATTLE_HUNGRY_PENALTY")
		if CareRules.need_is_low(care, "hygiene"):
			_lobby_meta.text = _lobby_meta.text + "\n" + tr("BATTLE_DIRTY_PENALTY")
	if _duel_pending:
		_start_button.text = tr("BATTLE_CONTINUE")
	elif not unavailable_key.is_empty():
		_start_button.text = tr("BATTLE_CHOOSE_ANIMA")
	else:
		_start_button.text = tr("BATTLE_TRAIN") if training else tr("BATTLE_START")
	_start_button.disabled = _busy or not other_pending_key.is_empty()
	_schedule_daily_reward_reset(_lobby_daily_reward)


func set_loading(message_key: String = "BATTLE_CONNECTING") -> void:
	_clear_action_commit()
	_reward_reset_timer.stop()
	_result_panel.visible = false
	if not _session.is_empty():
		_header.visible = false
		_lobby_panel.visible = false
		_battle_content.visible = true
		_actions.visible = false
		_forfeit_button.visible = false
		return
	_header.visible = true
	_lobby_panel.visible = true
	_battle_content.visible = false
	_lobby_name.text = tr("BATTLE_LOBBY_TITLE")
	_lobby_meta.text = tr(message_key)
	_start_button.disabled = true
	_start_button.visible = false


func set_session(
	battle_session: Dictionary,
	player_loaded: Dictionary = {},
	bot_loaded: Dictionary = {},
	art_cache: Dictionary = {}
) -> void:
	_clear_action_commit()
	_session = battle_session.duplicate(true)
	_remember_lobby_daily_reward(_as_dict(_session.get("daily_reward")))
	_header.visible = false
	_lobby_panel.visible = false
	_battle_content.visible = true
	if bool(player_loaded.get("ok", false)):
		_player_loaded = player_loaded.duplicate(true)
		_player_sprite.apply(player_loaded)
	if bool(bot_loaded.get("ok", false)):
		_bot_loaded = bot_loaded.duplicate(true)
		_bot_sprite.apply(bot_loaded)
	_player_sprite.visible = _player_sprite.sprite_frames != null
	_bot_sprite.visible = _bot_sprite.sprite_frames != null
	_apply_arena_background(art_cache)

	var player_snapshot := _as_dict(_session.get("player_snapshot"))
	var bot_snapshot := _as_dict(_session.get("bot_snapshot"))
	_player_name.text = _fighter_hud_title(player_snapshot)
	_bot_name.text = _fighter_hud_title(bot_snapshot, tr("BATTLE_BOT_NAME"))
	_position_fighters()
	_apply_state()
	_emit_arena_open()


func session_data() -> Dictionary:
	return _session.duplicate(true)


func has_session() -> bool:
	return not _session.is_empty()


func is_duel_arena_open() -> bool:
	# Packed scene starts hidden; scan_flow already gates HUD on _battle_view.visible.
	return _duel_column.visible and not _session.is_empty() and _battle_content.visible


func begin_action(action: String) -> void:
	if _busy or action not in ["strike", "surge", "guard", "item"]:
		return
	_queued_action = action
	_busy = true
	_show_action_commit(action)
	Input.vibrate_handheld(18)
	_update_action_state()


func set_busy(busy: bool) -> void:
	_busy = busy
	if not busy:
		_clear_action_commit()
	if _session.is_empty():
		_apply_lobby()
	else:
		_start_button.disabled = busy
	_update_action_state()


func is_training_lobby() -> bool:
	return _is_training(_lobby_daily_reward)


func _on_start_pressed() -> void:
	if _busy or _team_pending or _expedition_pending:
		return
	if _duel_pending:
		resume_requested.emit()
		return
	if _lobby_unavailable_key().is_empty():
		start_requested.emit()
		return
	choose_anima_requested.emit()


func _on_retry_pressed() -> void:
	if _retry_picks_anima:
		choose_anima_requested.emit()
		return
	resume_requested.emit()


func _request_item() -> void:
	if _busy:
		return
	if _item_already_used():
		return
	item_picker_requested.emit()


func _request_action(action: String) -> void:
	if _busy:
		return
	begin_action(action)
	action_requested.emit(action)


func _show_action_commit(action: String) -> void:
	_clear_action_commit()
	_queued_action = action
	var selected_button := _button_for_action(action)
	var selected_commit := _commit_for_action(action)
	for button in [_strike_button, _surge_button, _guard_button, _item_button]:
		(button as Button).self_modulate = (
			Color.WHITE if button == selected_button else Color(1.0, 1.0, 1.0, 0.48)
		)
	selected_commit.visible = true
	selected_commit.pivot_offset = selected_commit.size * 0.5
	selected_commit.scale = Vector2(0.0, 1.0)
	selected_commit.modulate = Color.WHITE
	_command_tween = create_tween()
	_command_tween.tween_property(selected_commit, "scale:x", 1.0, 0.10) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_command_tween.tween_property(selected_commit, "modulate:a", 0.42, 0.28)
	_command_tween.tween_property(selected_commit, "modulate:a", 1.0, 0.28)
	_command_tween.set_loops()


func _clear_action_commit() -> void:
	if is_instance_valid(_command_tween):
		_command_tween.kill()
	_command_tween = null
	_queued_action = ""
	for button in [_strike_button, _surge_button, _guard_button, _item_button]:
		(button as Button).self_modulate = Color.WHITE
	for commit in [_strike_commit, _surge_commit, _guard_commit, _item_commit]:
		(commit as ColorRect).visible = false
		(commit as ColorRect).scale = Vector2.ONE
		(commit as ColorRect).modulate = Color.WHITE


func _button_for_action(action: String) -> Button:
	if action == "surge":
		return _surge_button
	if action == "guard":
		return _guard_button
	if action == "item":
		return _item_button
	return _strike_button


func _commit_for_action(action: String) -> ColorRect:
	if action == "surge":
		return _surge_commit
	if action == "guard":
		return _guard_commit
	if action == "item":
		return _item_commit
	return _strike_commit


func show_retreat_banner() -> void:
	_show_banner(tr("BATTLE_RETREATING"), CUE_COLOR, false)


func set_error(error_code: String) -> void:
	_effectiveness.visible = false
	_clear_action_commit()
	_header.visible = _session.is_empty()
	if _session.is_empty():
		_lobby_panel.visible = true
		_battle_content.visible = false
		_result_panel.visible = false
		_lobby_name.text = tr("BATTLE_ERROR_TITLE")
		_lobby_meta.text = _error_copy(error_code)
		_start_button.visible = false
	else:
		_lobby_panel.visible = false
		_battle_content.visible = true
		_result_panel.visible = true
	_result_title.text = tr("BATTLE_ERROR_TITLE")
	_result_body.text = _error_copy(error_code)
	_retry_button.visible = true
	_retry_button.text = tr("ACTION_RETRY")
	_retry_picks_anima = false
	_actions.visible = false
	_forfeit_button.visible = false
	_update_action_state()


func play_events(events: Array, next_session: Dictionary) -> void:
	_clear_action_commit()
	set_busy(true)
	await _announce_initiative(events)
	for value in events:
		var event: Dictionary = BATTLE_EVENT.normalized(value)
		if event.is_empty():
			continue
		match str(event.get("type", "")):
			"guard":
				var guard_side := str(event.get("actor", ""))
				var bracing := _sprite_for(guard_side)
				if is_instance_valid(bracing):
					bracing.guard_shimmer()
				await _present_banner(
					tr("BATTLE_EVENT_GUARD") % _actor_name(guard_side),
					CUE_COLOR,
					false
				)
				await _hide_effectiveness()
			"item":
				await _play_item(event)
			"attack":
				await _play_attack(event)
			"knockout":
				var defeated_side := str(event.get("actor", ""))
				var defeated := _sprite_for(defeated_side)
				if is_instance_valid(defeated):
					defeated.set_pose("defeated")
				await _present_banner(
					tr("BATTLE_EVENT_KO") % _actor_name(defeated_side),
					DAMAGE_COLOR,
					true
				)
				await _hide_effectiveness()
			"timeout":
				await _present_banner(tr("BATTLE_EVENT_TIMEOUT"), DAMAGE_COLOR, false)
				await _hide_effectiveness()
			"finished":
				await _present_banner(tr("BATTLE_EVENT_FINISHED"), DAMAGE_COLOR, false)
				await _hide_effectiveness()
			"move_effect", "status_tick", "status_expired":
				_apply_effect_hp_event(event)
				var plate := BATTLE_EVENT.plate_text(event)
				if not plate.is_empty():
					await _present_banner(plate, CUE_COLOR, false)
					await _hide_effectiveness()
	set_session(next_session)
	set_busy(false)


func _apply_effect_hp_event(event: Dictionary) -> void:
	if not event.has("target_hp"):
		return
	var target := str(event.get("target", event.get("actor", "")))
	var hp := int(event.get("target_hp", 0))
	if target == "player":
		apply_hp_bar_state(_player_hp, float(hp), _player_hp.max_value)
		_player_hp_value.text = LocaleManager.format_ratio(hp, int(_player_hp.max_value))
	elif target == "bot":
		apply_hp_bar_state(_bot_hp, float(hp), _bot_hp.max_value)
		_bot_hp_value.text = LocaleManager.format_ratio(hp, int(_bot_hp.max_value))
	if hp <= 0:
		var fainting := _sprite_for(target)
		if is_instance_valid(fainting):
			fainting.set_pose("defeated")


func _play_item(event: Dictionary) -> void:
	var actor_name := str(event.get("actor", ""))
	await _present_banner(
		tr("BATTLE_EVENT_ITEM") % _actor_name(actor_name),
		CUE_COLOR,
		false
	)
	var actor := _sprite_for(actor_name)
	if is_instance_valid(actor):
		actor.care_feedback("item")
	if actor_name == "player":
		apply_hp_bar_state(
			_player_hp, float(event.get("hp", _player_hp.value)), _player_hp.max_value
		)
		_player_hp_value.text = LocaleManager.format_ratio(
			int(event.get("hp", _player_hp.value)), int(_player_hp.max_value)
		)
	await _present_banner(item_banner_text(event), EFFECTIVE_COLOR, true)
	await _hide_effectiveness()


func _play_attack(event: Dictionary) -> void:
	var actor_name := str(event.get("actor", ""))
	var target_name := str(event.get("target", ""))
	var attacker := _sprite_for(actor_name)
	var target := _sprite_for(target_name)
	var actor_snapshot := _as_dict(
		_session.get("player_snapshot" if actor_name == "player" else "bot_snapshot")
	)
	var action_label := _move_label(str(event.get("action", "")), actor_snapshot)
	var element_multiplier := float(event.get("element_multiplier", 1.0))
	var effect_key := effectiveness_key(element_multiplier)
	await _present_banner(
		tr("BATTLE_EVENT_ATTACK") % [_actor_name(actor_name), action_label],
		CUE_COLOR,
		false
	)
	await _hide_effectiveness()
	if is_instance_valid(attacker):
		attacker.set_pose("attack")
		var fx_pose := "fx_surge" if str(event.get("action", "")) == "surge" else "fx_strike"
		if is_instance_valid(target):
			attacker.play_fx(fx_pose, target.body_center_global())
		else:
			attacker.play_fx(fx_pose)
	await _event_pause(AnimaPresenter.FX_TRAVEL_SEC)
	if is_instance_valid(attacker):
		attacker.set_pose("idle")
	_damage.text = tr("BATTLE_DAMAGE") % LocaleManager.format_integer(int(event.get("damage", 0)))
	_damage.visible = true
	if target_name == "player":
		apply_hp_bar_state(_player_hp, float(event.get("target_hp", 0)), _player_hp.max_value)
	else:
		apply_hp_bar_state(_bot_hp, float(event.get("target_hp", 0)), _bot_hp.max_value)
	if is_instance_valid(target):
		target.hit_react(element_multiplier)
		target.modulate = Color(1.65, 0.45, 0.55, 1.0)
		var flash := create_tween()
		flash.tween_property(target, "modulate", Color.WHITE, 0.28)
		Input.vibrate_handheld(55 if element_multiplier > 1.0 else 35)
		if int(event.get("target_hp", 0)) <= 0:
			target.set_pose("defeated")
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
	if not effect_key.is_empty():
		await _present_banner(
			tr(effect_key),
			EFFECTIVE_COLOR if effect_key == "BATTLE_EFFECTIVE" else RESISTED_COLOR,
			effect_key == "BATTLE_EFFECTIVE"
		)
	await _hide_effectiveness()


func _present_banner(text: String, color: Color, big: bool = true) -> void:
	_show_banner(text, color, big)
	if is_instance_valid(_effectiveness_tween):
		await _effectiveness_tween.finished
	await _readability_pause()


func _show_effectiveness(multiplier: float) -> void:
	var key := effectiveness_key(multiplier)
	var color := DAMAGE_COLOR
	if key == "BATTLE_EFFECTIVE":
		color = EFFECTIVE_COLOR
	elif key == "BATTLE_NOT_EFFECTIVE":
		color = RESISTED_COLOR
	_show_banner(tr(key) if not key.is_empty() else "", color, key == "BATTLE_EFFECTIVE")


func _show_banner(text: String, color: Color, big: bool = true) -> void:
	if is_instance_valid(_effectiveness_tween):
		_effectiveness_tween.kill()
	_effectiveness.visible = not text.is_empty()
	if not _effectiveness.visible:
		_damage.add_theme_color_override("font_color", color)
		return
	_effectiveness.modulate = Color.WHITE
	_effectiveness.scale = Vector2.ONE
	_effectiveness.pivot_offset = _effectiveness.size * 0.5
	_effectiveness_label.text = text
	_effectiveness_label.add_theme_color_override("font_color", color)
	_effectiveness_label.add_theme_color_override(
		"font_shadow_color", Color(color.r, color.g, color.b, 0.48)
	)
	_damage.add_theme_color_override("font_color", color)
	_damage.add_theme_font_size_override("font_size", 54 if big else 46)
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


static func item_banner_text(event: Dictionary) -> String:
	var effect := str(event.get("effect", ""))
	var value := int(event.get("effect_value", 0))
	if effect.is_empty():
		match str(event.get("item_id", "")):
			"vital_patch":
				effect = "heal_hp_pct"
				value = 30
			"power_chip":
				effect = "buff_atk"
				value = 35
			"surge_lens":
				effect = "buff_special"
				value = 35
			"aegis_plate":
				effect = "buff_guard"
				value = 25
			"tempo_coil":
				effect = "buff_spd"
				value = 40
			"pp_capsule":
				effect = "pp_boost"
				value = 2
			"phase_shield":
				effect = "phase_shield"
				value = 80
	var key := ""
	match effect:
		"heal_hp_pct":
			key = "BATTLE_ITEM_HEAL"
		"buff_atk":
			key = "BATTLE_ITEM_ATK"
		"buff_special":
			key = "BATTLE_ITEM_SPECIAL"
		"buff_guard":
			key = "BATTLE_ITEM_GUARD"
		"buff_spd":
			key = "BATTLE_ITEM_SPD"
		"pp_boost":
			key = "BATTLE_ITEM_PP"
		"phase_shield":
			key = "BATTLE_ITEM_SHIELD"
		_:
			key = "BATTLE_ITEM_GENERIC"
	var copy := TranslationServer.translate(key)
	return copy % str(value) if copy.find("%s") >= 0 else copy


static func effectiveness_key(multiplier: float) -> String:
	if multiplier > 1.0:
		return "BATTLE_EFFECTIVE"
	if multiplier < 1.0:
		return "BATTLE_NOT_EFFECTIVE"
	return ""


static func apply_hp_bar_state(meter: ProgressBar, current: float, maximum: float) -> void:
	if not is_instance_valid(meter):
		return
	var safe_maximum := maxf(1.0, maximum)
	meter.max_value = safe_maximum
	meter.value = clampf(current, 0.0, safe_maximum)
	var fill_style := meter.get_theme_stylebox("fill")
	if fill_style is StyleBoxFlat:
		var fill := fill_style.duplicate() as StyleBoxFlat
		var ratio := meter.value / safe_maximum
		if ratio <= 0.2:
			fill.bg_color = HP_EMPTY_COLOR
		elif ratio <= 0.5:
			fill.bg_color = HP_WARNING_COLOR
		else:
			fill.bg_color = HP_FULL_COLOR
		meter.add_theme_stylebox_override("fill", fill)


func _announce_initiative(events: Array) -> void:
	for value in events:
		var event: Dictionary = BATTLE_EVENT.normalized(value)
		if str(event.get("type", "")) == "guard":
			return
	for value in events:
		var event: Dictionary = BATTLE_EVENT.normalized(value)
		if str(event.get("type", "")) != "attack":
			continue
		var actor := str(event.get("actor", ""))
		await _present_banner(tr("BATTLE_INITIATIVE") % _actor_name(actor), CUE_COLOR, false)
		await _hide_effectiveness()
		return


func _apply_state() -> void:
	var state := _as_dict(_session.get("state"))
	var player := _as_dict(state.get("player"))
	var bot := _as_dict(state.get("bot"))
	apply_hp_bar_state(
		_player_hp, float(player.get("hp", 0)), float(player.get("max_hp", 1))
	)
	apply_hp_bar_state(
		_bot_hp, float(bot.get("hp", 0)), float(bot.get("max_hp", 1))
	)
	_player_hp_value.text = LocaleManager.format_ratio(
		int(player.get("hp", 0)), int(player.get("max_hp", 1))
	)
	_bot_hp_value.text = LocaleManager.format_ratio(
		int(bot.get("hp", 0)), int(bot.get("max_hp", 1))
	)
	_player_name.text = _fighter_hud_title(_as_dict(_session.get("player_snapshot")), "", player)
	_bot_name.text = _fighter_hud_title(
		_as_dict(_session.get("bot_snapshot")), tr("BATTLE_BOT_NAME"), bot
	)
	_turn_label.visible = false
	var daily_reward := _as_dict(_session.get("daily_reward"))
	# Reward limits explain the lobby/result, not the turn decision inside the arena.
	_daily_reward_label.visible = false
	var status := str(_session.get("status", state.get("status", "active")))
	_result_panel.visible = status != "active"
	_actions.visible = status == "active"
	_forfeit_button.visible = status == "active"
	if status != "active":
		_show_result(status)
	_update_action_state()
	_schedule_daily_reward_reset(daily_reward)


func _show_result(status: String) -> void:
	_result_panel.visible = true
	_retry_button.visible = true
	var daily_reward := _as_dict(_session.get("daily_reward"))
	var training := _is_training(daily_reward)
	var reward := _as_dict(_session.get("last_reward"))
	match status:
		"won":
			_result_title.text = tr(
				"BATTLE_TRAINING_TITLE" if training else "BATTLE_WIN_TITLE"
			)
			_result_body_base = _win_body(reward)
			_player_sprite.victory_celebration(_companion_level())
		"lost":
			_result_title.text = tr("BATTLE_LOSS_TITLE")
			_result_body_base = tr("BATTLE_LOSS_BODY")
		_:
			_result_title.text = tr("BATTLE_FORFEIT_TITLE")
			_result_body_base = tr("BATTLE_FORFEIT_BODY")
	_apply_result_actions(training)


## Anima yang Energy-nya habis tidak bisa rematch, jadi CTA-nya menjadi Choose
## Anima plus alasannya — bukan tombol yang baru saja ditolak server.
func _apply_result_actions(training: bool) -> void:
	var blocked := _lobby_unavailable_key()
	_retry_picks_anima = not blocked.is_empty()
	if _retry_picks_anima:
		# Chip pendek, bukan kalimat penuh: CTA-nya sudah bilang Choose Anima, dan
		# panel result tumbuh ke atas menutupi arena kalau alasannya empat baris.
		var reason := tr("BATTLE_RESULT_BLOCKED") % tr(
			CareRules.battle_pick_reason_key(blocked)
		)
		_result_body.text = _result_body_base + "\n" + reason
		_retry_button.text = tr("BATTLE_CHOOSE_ANIMA")
		return
	_result_body.text = _result_body_base
	_retry_button.text = tr("BATTLE_TRAIN_AGAIN" if training else "BATTLE_AGAIN")


func _companion_level() -> int:
	var player := _as_dict(_as_dict(_session.get("state")).get("player"))
	var level := int(player.get("level", 0))
	if level > 0:
		return level
	return CareRules.level_from_exp(int(_lobby_row.get("care_score", 0)))


func _win_body(reward: Dictionary) -> String:
	var bits := int(reward.get("bits", 0))
	var exp := int(reward.get("care_score", 0))
	if exp > 0:
		return tr("BATTLE_WIN_BODY") % [
			LocaleManager.format_integer(bits),
			_actor_name("player"),
			LocaleManager.format_integer(exp),
		]
	if bits > 0:
		return tr("BATTLE_TRAINING_BITS_BODY") % LocaleManager.format_integer(bits)
	return tr("BATTLE_TRAINING_WIN_BODY")


func _daily_counter_text(daily_reward: Dictionary) -> String:
	return "%s · %s" % [
		tr("BATTLE_DAILY_PROGRESS") % [
			LocaleManager.format_integer(_display_daily_earned(daily_reward)),
			LocaleManager.format_integer(int(daily_reward.get("limit", 0))),
		],
		tr("BATTLE_DAILY_BITS") % [
			LocaleManager.format_integer(_display_bits_earned(daily_reward)),
			LocaleManager.format_integer(int(daily_reward.get("bits_limit", 100))),
		],
	]


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


func _update_action_state() -> void:
	var state := _as_dict(_session.get("state"))
	var player := _as_dict(state.get("player"))
	var active := str(_session.get("status", state.get("status", ""))) == "active"
	var momentum := int(player.get("momentum", 0))
	var momentum_max := int(player.get("momentum_max", MOMENTUM_MAX))
	var item_used := _item_already_used()
	var committed := _busy and not _queued_action.is_empty()
	_strike_button.disabled = not active or (_busy and not committed)
	_guard_button.disabled = not active or (_busy and not committed)
	_item_button.disabled = not active or (_busy and not committed)
	_surge_button.disabled = (
		not active or momentum < SURGE_COST or (_busy and not committed)
	)
	var accepts_input := active and not _busy
	for button in [_strike_button, _surge_button, _guard_button, _item_button]:
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
	# Counter menempel di tombol yang membelanjakannya, bukan hanya di header.
	var player_snapshot := _as_dict(_session.get("player_snapshot"))
	_strike_button.text = _move_label("strike", player_snapshot)
	_surge_button.text = tr("BATTLE_ACTION_SURGE_COST") % [
		_move_label("surge", player_snapshot),
		LocaleManager.format_integer(momentum),
		LocaleManager.format_integer(momentum_max),
	]
	_item_button.text = tr("BATTLE_ACTION_ITEM")
	_item_button.self_modulate = (
		Color(1, 1, 1, 0.42) if item_used and not committed else Color.WHITE
	)
	_forfeit_button.disabled = _busy or not active


func _position_fighters() -> void:
	if not is_instance_valid(_arena) or not is_instance_valid(_fighter_layer):
		return
	_fighter_layer.position = Vector2.ZERO
	_fighter_layer.scale = Vector2.ONE
	var ground_y := _arena.size.y * DUEL_GROUND_Y_RATIO
	_player_anchor.position = Vector2(_arena.size.x * BattleScale.PLAYER_SHOT_X, ground_y)
	_bot_anchor.position = Vector2(_arena.size.x * BattleScale.OPPONENT_SHOT_X, ground_y)
	var player_snapshot := _as_dict(_session.get("player_snapshot"))
	var bot_snapshot := _as_dict(_session.get("bot_snapshot"))
	var player_height := float(
		player_snapshot.get("body_height_cm", BattleScale.BODY_HEIGHT_REFERENCE_CM)
	)
	var bot_height := float(
		bot_snapshot.get("body_height_cm", BattleScale.BODY_HEIGHT_REFERENCE_CM)
	)
	var scales := BattleScale.fighter_pair_scales(
		player_height,
		_player_loaded,
		bot_height,
		_bot_loaded,
		_arena.size
	)
	_player_anchor.scale = Vector2(scales.x, scales.x)
	_bot_anchor.scale = Vector2(scales.y, scales.y)
	_player_sprite.plant_on_anchor()
	_bot_sprite.plant_on_anchor()
	var player_size := _player_sprite.opaque_local_rect().size * absf(_player_anchor.scale.x)
	var bot_size := _bot_sprite.opaque_local_rect().size * absf(_bot_anchor.scale.x)
	var gap := _arena.size.x * TeamBattleView.CAMERA_FIGHTER_GAP_RATIO
	var overlap := (
		_player_anchor.position.x + player_size.x * 0.5 + gap
		- (_bot_anchor.position.x - bot_size.x * 0.5)
	)
	if overlap > 0.0:
		_player_anchor.position.x -= overlap * 0.5
		_bot_anchor.position.x += overlap * 0.5
	var bounds := Rect2(
		_player_anchor.position.x - player_size.x * 0.5,
		ground_y - player_size.y,
		player_size.x,
		player_size.y
	).merge(Rect2(
		_bot_anchor.position.x - bot_size.x * 0.5,
		ground_y - bot_size.y,
		bot_size.x,
		bot_size.y
	))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var fit_zoom := minf(
		(_arena.size.x * 0.90) / bounds.size.x,
		(_arena.size.y * (DUEL_GROUND_Y_RATIO - 0.05)) / bounds.size.y
	)
	var tallest := maxf(
		BattleScale.anima_display_height_cm(player_height),
		BattleScale.anima_display_height_cm(bot_height)
	)
	var size_mix := clampf(
		inverse_lerp(50.0, BattleScale.ANIMA_VISUAL_HEIGHT_CAP_CM, tallest), 0.0, 1.0
	)
	var preferred_zoom := lerpf(
		TeamBattleView.CAMERA_MAX_ZOOM, 0.72, size_mix
	)
	var zoom := clampf(
		minf(fit_zoom, preferred_zoom),
		TeamBattleView.CAMERA_MIN_ZOOM,
		TeamBattleView.CAMERA_MAX_ZOOM
	)
	_fighter_layer.scale = Vector2(zoom, zoom)
	_fighter_layer.position = Vector2(
		_arena.size.x * 0.5 - bounds.get_center().x * zoom,
		ground_y * (1.0 - zoom)
	)
	_sync_shadow("player")
	_sync_shadow("bot")
	var background_zoom := lerpf(DUEL_BACKGROUND_MAX_SCALE, 1.0, size_mix)
	_layout_arena_background(background_zoom)


func _sprite_for(actor: String) -> AnimaPresenter:
	return _player_sprite if actor == "player" else _bot_sprite


func _fighter_title(snapshot: Dictionary, fallback_name: String = "") -> String:
	var anima_name := fallback_name
	if anima_name.is_empty():
		anima_name = str(snapshot.get("name", tr("ANIMA_FALLBACK_NAME")))
	var level := int(snapshot.get("level", 0))
	if level <= 0:
		level = CareRules.level_from_exp(int(snapshot.get("care_score", 0)))
	return "%s %s" % [anima_name, LocaleManager.level_label(maxi(1, level))]


func _fighter_hud_title(
	snapshot: Dictionary,
	fallback_name: String = "",
	state_fighter: Dictionary = {}
) -> String:
	var title := _fighter_title(snapshot, fallback_name)
	var fighter := state_fighter if not state_fighter.is_empty() else snapshot
	var summary := CareRules.fighter_status_summary(fighter)
	if summary.is_empty():
		return title
	return "%s · %s" % [title, summary]


func _actor_name(actor: String) -> String:
	var snapshot := _as_dict(
		_session.get("player_snapshot" if actor == "player" else "bot_snapshot")
	)
	var anima_name := str(snapshot.get("name", "")).strip_edges()
	if anima_name.is_empty():
		return tr("ANIMA_FALLBACK_NAME") if actor == "player" else tr("BATTLE_BOT_NAME")
	return anima_name


func _move_label(action: String, snapshot: Dictionary) -> String:
	return LocaleManager.move_name(snapshot, action)


func _readability_pause(seconds: float = ACTION_CUE_SEC) -> void:
	await get_tree().create_timer(seconds).timeout


func _event_pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _error_copy(error_code: String) -> String:
	var key: String = str({
		"ANIMA_SLEEPING": "BATTLE_ANIMA_SLEEPING",
		"ANIMA_DORMANT": "BATTLE_ANIMA_DORMANT",
		"ANIMA_LOW_ENERGY": "BATTLE_ANIMA_LOW_ENERGY",
		"ANIMA_HUNGRY": "BATTLE_ANIMA_HUNGRY",
		"ANIMA_NOT_READY": "BATTLE_ANIMA_NOT_READY",
		"NO_BATTLE_OPPONENT": "BATTLE_NO_OPPONENT",
		"NO_MOMENTUM": "BATTLE_NO_MOMENTUM",
		"NO_ITEM": "ERROR_NO_ITEM",
		"ITEM_ALREADY_USED": "BATTLE_ITEM_USED",
		"INVALID_ITEM": "ERROR_INVALID_ITEM",
		"BATTLE_EXPIRED": "BATTLE_EXPIRED",
		"AUTH_EXPIRED": "BATTLE_AUTH_EXPIRED",
	}.get(error_code, "BATTLE_ERROR_GENERIC"))
	return tr(key)


func _lobby_unavailable_key() -> String:
	return CareRules.battle_unavailable_key(_lobby_row)


func _lobby_title_key(unavailable_key: String) -> String:
	if unavailable_key == "BATTLE_ANIMA_LOW_ENERGY":
		return "BATTLE_LOBBY_TITLE_LOW_ENERGY"
	if unavailable_key == "BATTLE_ANIMA_HUNGRY":
		return "BATTLE_LOBBY_TITLE_HUNGRY"
	return "BATTLE_LOBBY_TITLE"


func _lobby_is_eligible() -> bool:
	return _lobby_unavailable_key().is_empty()


func _schedule_daily_reward_reset(daily_reward: Dictionary) -> void:
	_reward_reset_timer.stop()
	var delay := reward_reset_delay(daily_reward)
	if delay > 0.0:
		_reward_reset_timer.start(delay + 0.1)


static func reward_reset_delay(daily_reward: Dictionary) -> float:
	var server_now := _timestamp_seconds(daily_reward.get("server_now"))
	var reset_at := _timestamp_seconds(daily_reward.get("reset_at"))
	if server_now <= 0.0 or reset_at <= server_now:
		return -1.0
	return reset_at - server_now


static func _is_training(daily_reward: Dictionary) -> bool:
	return (
		not daily_reward.is_empty()
		and int(daily_reward.get("remaining", 0)) <= 0
		and not bool(daily_reward.get("rewarded", false))
	)


static func _is_bits_capped(daily_reward: Dictionary) -> bool:
	if daily_reward.is_empty() or bool(daily_reward.get("rewarded", false)):
		return false
	if daily_reward.has("bits_remaining"):
		return int(daily_reward.get("bits_remaining")) <= 0
	if daily_reward.has("bits_earned"):
		return int(daily_reward.get("bits_earned")) >= int(daily_reward.get("bits_limit", 100))
	return false


static func _display_daily_earned(daily_reward: Dictionary) -> int:
	return mini(
		maxi(0, int(daily_reward.get("earned", 0))),
		maxi(0, int(daily_reward.get("limit", 0)))
	)


static func _display_bits_earned(daily_reward: Dictionary) -> int:
	return mini(
		maxi(0, int(daily_reward.get("bits_earned", 0))),
		maxi(0, int(daily_reward.get("bits_limit", 100)))
	)


static func _timestamp_seconds(value: Variant) -> float:
	var timestamp := str(value)
	if timestamp.is_empty():
		return -1.0
	return float(Time.get_unix_time_from_datetime_string(timestamp))


static func _as_dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _item_already_used() -> bool:
	# Payload session selalu membawa item_used_id: null. str(null) == "<null>".
	var used_id: Variant = _session.get("item_used_id")
	if used_id != null:
		var text := str(used_id).strip_edges()
		if not text.is_empty() and text != "<null>":
			return true
	return bool(_as_dict(_as_dict(_session.get("state")).get("player")).get("item_used", false))


func _emit_arena_open() -> void:
	arena_open_changed.emit(is_duel_arena_open())


func _apply_arena_background(art_cache: Dictionary) -> void:
	if not art_cache.is_empty():
		_art_cache = art_cache.duplicate(true)
	var texture: Variant = _art_cache.get("arena_background")
	_uses_static_background = not texture is Texture2D
	if _uses_static_background:
		texture = _static_duel_background()
		_background_material.set_shader_parameter("day_texture", _static_duel_day_background())
		_refresh_static_background()
	else:
		_background_material.set_shader_parameter("daylight_blend", 0.0)
	_arena_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arena_background.stretch_mode = TextureRect.STRETCH_SCALE
	_arena_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_arena_background.texture = texture
	_arena_background.visible = texture is Texture2D
	_sync_background_pan()


func _refresh_static_background() -> void:
	if not _uses_static_background or not is_instance_valid(_background_material):
		return
	_background_material.set_shader_parameter(
		"daylight_blend", LocalDaylight.daylight_blend()
	)


func _sync_static_background_variant() -> void:
	if not _uses_static_background:
		return
	var night := _static_duel_background()
	if _arena_background.texture == night:
		return
	_arena_background.texture = night
	_background_material.set_shader_parameter("day_texture", _static_duel_day_background())


func _static_duel_background() -> Texture2D:
	return (
		DUEL_BACKGROUND_NIGHT_LANDSCAPE
		if static_background_uses_landscape(_arena.size)
		else DUEL_BACKGROUND_NIGHT
	)


func _static_duel_day_background() -> Texture2D:
	return (
		DUEL_BACKGROUND_DAY_LANDSCAPE
		if static_background_uses_landscape(_arena.size)
		else DUEL_BACKGROUND_DAY
	)


static func static_background_uses_landscape(stage_size: Vector2) -> bool:
	return stage_size.x > stage_size.y


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
	var stage_size := _arena.size
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or stage_size.x <= 0.0 or stage_size.y <= 0.0:
		return
	var cover_scale := maxf(stage_size.x / texture_size.x, stage_size.y / texture_size.y)
	var draw_size := texture_size * cover_scale * maxf(1.0, background_zoom)
	var overflow := Vector2(
		maxf(0.0, draw_size.x - stage_size.x),
		maxf(0.0, draw_size.y - stage_size.y)
	)
	_arena_background.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_arena_background.pivot_offset = Vector2.ZERO
	_arena_background.scale = Vector2.ONE
	_arena_background.size = draw_size
	var pan := 0.5 if _uses_static_background else _background_pan
	var vertical_pan := 1.0 if _uses_static_background else 0.5
	_arena_background.position = Vector2(
		-overflow.x * pan,
		-overflow.y * vertical_pan
	)


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


func _sync_shadow(side: String) -> void:
	var sprite := _player_sprite if side == "player" else _bot_sprite
	var shadow := _player_shadow if side == "player" else _bot_shadow
	if is_instance_valid(sprite):
		sprite.sync_ground_shadow(shadow)
