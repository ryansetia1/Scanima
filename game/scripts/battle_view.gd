class_name BattleView
extends Control

const BATTLE_EVENT := preload("res://scripts/battle_event.gd")

# Nama identifier mengikuti _shared/battle.mjs; kata player-facing "PP"/"Special"
# hidup di locales/ui.csv supaya wire value dan copy bisa berubah terpisah.
# Kedua angka wajib sama dengan modul itu: client yang lebih longgar akan
# menyalakan Special yang lalu ditolak server sebagai NO_MOMENTUM.
const MOMENTUM_MAX := 3
const SURGE_COST := 1
const DAMAGE_COLOR := Color(1.0, 0.35, 0.48, 1.0)
const EFFECTIVE_COLOR := Color(1.0, 0.82, 0.4, 1.0)
const RESISTED_COLOR := Color(0.55, 0.68, 0.9, 1.0)

signal start_requested
signal choose_anima_requested
signal action_requested(action: String)
signal item_picker_requested
signal resume_requested
signal forfeit_requested
signal reward_status_refresh_requested

@export var metal_icon: Texture2D
@export var plant_icon: Texture2D
@export var flow_icon: Texture2D
@export var spark_icon: Texture2D
@export var cloth_icon: Texture2D
@export var stone_icon: Texture2D

@onready var _header: Control = %Header
@onready var _lobby_panel: PanelContainer = %BattleLobbyPanel
@onready var _lobby_name: Label = %BattleLobbyName
@onready var _lobby_meta: Label = %BattleLobbyMeta
@onready var _start_button: Button = %BattleStartButton
@onready var _battle_content: VBoxContainer = %BattleContent
@onready var _turn_label: Label = %BattleTurn
@onready var _daily_reward_label: Label = %BattleDailyReward
@onready var _player_name: Label = %BattlePlayerName
@onready var _bot_name: Label = %BattleBotName
@onready var _player_element_icon: TextureRect = %BattlePlayerElementIcon
@onready var _bot_element_icon: TextureRect = %BattleBotElementIcon
@onready var _player_element: Label = %BattlePlayerElement
@onready var _bot_element: Label = %BattleBotElement
@onready var _player_hp: ProgressBar = %BattlePlayerHp
@onready var _bot_hp: ProgressBar = %BattleBotHp
@onready var _player_hp_value: Label = %BattlePlayerHpValue
@onready var _bot_hp_value: Label = %BattleBotHpValue
@onready var _arena: Control = %BattleArena
@onready var _player_anchor: Node2D = %BattlePlayerAnchor
@onready var _bot_anchor: Node2D = %BattleBotAnchor
@onready var _player_sprite: AnimaPresenter = %BattlePlayerSprite
@onready var _bot_sprite: AnimaPresenter = %BattleBotSprite
@onready var _feedback: Label = %BattleFeedback
@onready var _damage: Label = %BattleDamage
@onready var _effectiveness: Control = %BattleEffectiveness
@onready var _effectiveness_badge: CenterContainer = %BattleEffectivenessBadge
@onready var _effectiveness_label: Label = %BattleEffectivenessLabel
@onready var _actions: HBoxContainer = %Actions
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
@onready var _reward_reset_timer: Timer = %BattleRewardResetTimer

var _lobby_row: Dictionary = {}
var _lobby_daily_reward: Dictionary = {}
var _session: Dictionary = {}
var _busy := false
var _element_icons: Dictionary = {}
var _effectiveness_tween: Tween
var _queued_action := ""
var _last_reward: Dictionary = {}
var _command_tween: Tween


func _ready() -> void:
	_element_icons = {
		"metal": metal_icon,
		"plant": plant_icon,
		"flow": flow_icon,
		"spark": spark_icon,
		"cloth": cloth_icon,
		"stone": stone_icon,
	}
	_start_button.pressed.connect(_on_start_pressed)
	_strike_button.pressed.connect(_request_action.bind("strike"))
	_surge_button.pressed.connect(_request_action.bind("surge"))
	_guard_button.pressed.connect(_request_action.bind("guard"))
	_item_button.pressed.connect(_request_item)
	_forfeit_button.pressed.connect(forfeit_requested.emit)
	_retry_button.pressed.connect(resume_requested.emit)
	_arena.resized.connect(_position_fighters)
	_reward_reset_timer.timeout.connect(reward_status_refresh_requested.emit)
	_position_fighters.call_deferred()
	_player_sprite.set_facing(1.0)
	_bot_sprite.set_facing(-1.0)
	set_lobby({})


func set_lobby(row: Dictionary) -> void:
	_clear_action_commit()
	_lobby_row = row.duplicate(true)
	_session = {}
	_header.visible = true
	_lobby_panel.visible = true
	_battle_content.visible = false
	_result_panel.visible = false
	_start_button.visible = true
	_apply_lobby()


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
	if not unavailable_key.is_empty():
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
			LocaleManager.element_name(str(_lobby_row.get("element", ""))),
			LocaleManager.level_label(CareRules.level_from_exp(int(_lobby_row.get("care_score", 0)))),
		]
	if unavailable_key.is_empty():
		var care: Variant = _lobby_row.get("care")
		if CareRules.is_hungry(care):
			_lobby_meta.text = _lobby_meta.text + "\n" + tr("BATTLE_HUNGRY_PENALTY")
		if CareRules.need_is_low(care, "hygiene"):
			_lobby_meta.text = _lobby_meta.text + "\n" + tr("BATTLE_DIRTY_PENALTY")
		_start_button.text = tr("BATTLE_TRAIN") if training else tr("BATTLE_START")
	else:
		_start_button.text = tr("BATTLE_CHOOSE_ANIMA")
	_start_button.disabled = _busy
	_schedule_daily_reward_reset(_lobby_daily_reward)


func set_loading(message_key: String = "BATTLE_CONNECTING") -> void:
	_clear_action_commit()
	_reward_reset_timer.stop()
	_result_panel.visible = false
	if not _session.is_empty():
		_header.visible = false
		_lobby_panel.visible = false
		_battle_content.visible = true
		_feedback.text = tr(message_key)
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
	bot_loaded: Dictionary = {}
) -> void:
	_clear_action_commit()
	_session = battle_session.duplicate(true)
	_remember_lobby_daily_reward(_as_dict(_session.get("daily_reward")))
	_header.visible = false
	_lobby_panel.visible = false
	_battle_content.visible = true
	if bool(player_loaded.get("ok", false)):
		_player_sprite.apply(player_loaded)
	if bool(bot_loaded.get("ok", false)):
		_bot_sprite.apply(bot_loaded)
	_player_sprite.visible = _player_sprite.sprite_frames != null
	_bot_sprite.visible = _bot_sprite.sprite_frames != null

	var player_snapshot := _as_dict(_session.get("player_snapshot"))
	var bot_snapshot := _as_dict(_session.get("bot_snapshot"))
	_player_name.text = str(player_snapshot.get("name", tr("ANIMA_FALLBACK_NAME")))
	_bot_name.text = tr("BATTLE_BOT_NAME")
	_apply_element(
		_player_element_icon,
		_player_element,
		str(player_snapshot.get("element", "stone"))
	)
	_apply_element(_bot_element_icon, _bot_element, str(bot_snapshot.get("element", "stone")))
	_apply_state()


func session_data() -> Dictionary:
	return _session.duplicate(true)


func begin_action(action: String) -> void:
	if _busy or action not in ["strike", "surge", "guard", "item"]:
		return
	_queued_action = action
	_busy = true
	var feedback_key: String = str({
		"strike": "BATTLE_ACTION_PENDING_STRIKE",
		"surge": "BATTLE_ACTION_PENDING_SURGE",
		"guard": "BATTLE_ACTION_PENDING_GUARD",
		"item": "BATTLE_ACTION_PENDING_ITEM",
	}.get(action, "BATTLE_CHOOSE_ACTION"))
	if action == "guard" or action == "item":
		_feedback.text = tr(feedback_key)
	else:
		_feedback.text = tr(feedback_key) % _move_label(action, _as_dict(_session.get("player_snapshot")))
	_show_action_commit(action)
	_update_action_state()


func set_busy(busy: bool) -> void:
	_busy = busy
	if not busy:
		_clear_action_commit()
	_start_button.disabled = busy
	_update_action_state()


func is_training_lobby() -> bool:
	return _is_training(_lobby_daily_reward)


func _on_start_pressed() -> void:
	if _busy:
		return
	if _lobby_unavailable_key().is_empty():
		start_requested.emit()
		return
	choose_anima_requested.emit()


func _request_item() -> void:
	if _busy:
		return
	if not str(_session.get("item_used_id", "")).is_empty() or bool(_as_dict(_as_dict(_session.get("state")).get("player")).get("item_used", false)):
		_feedback.text = tr("BATTLE_ITEM_USED")
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
	if UiMotion.reduced_motion:
		selected_commit.scale = Vector2.ONE
		return
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


func set_error(error_code: String) -> void:
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
	_feedback.text = _error_copy(error_code)
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
				_feedback.text = tr("BATTLE_EVENT_GUARD") % _actor_name(
					str(event.get("actor", ""))
				)
				await _event_pause(0.24)
			"item":
				_feedback.text = tr("BATTLE_EVENT_ITEM") % _actor_name(
					str(event.get("actor", ""))
				)
				if str(event.get("actor", "")) == "player":
					_player_hp.value = int(event.get("hp", _player_hp.value))
				await _event_pause(0.28)
			"attack":
				await _play_attack(event)
			"knockout":
				var defeated := _sprite_for(str(event.get("actor", "")))
				if is_instance_valid(defeated):
					defeated.set_pose("defeated")
			"timeout":
				_feedback.text = tr("BATTLE_EVENT_TIMEOUT")
			"finished":
				_feedback.text = tr("BATTLE_EVENT_FINISHED")
	set_session(next_session)
	set_busy(false)


func _play_attack(event: Dictionary) -> void:
	var actor_name := str(event.get("actor", ""))
	var target_name := str(event.get("target", ""))
	var attacker := _sprite_for(actor_name)
	var target := _sprite_for(target_name)
	if is_instance_valid(attacker):
		attacker.set_pose("attack")
		var fx_pose := "fx_surge" if str(event.get("action", "")) == "surge" else "fx_strike"
		if is_instance_valid(target):
			attacker.play_fx(fx_pose, target.to_global(target.offset))
		else:
			attacker.play_fx(fx_pose)
	var actor_snapshot := _as_dict(
		_session.get("player_snapshot" if actor_name == "player" else "bot_snapshot")
	)
	var action_label := _move_label(str(event.get("action", "")), actor_snapshot)
	var element_multiplier := float(event.get("element_multiplier", 1.0))
	var effect_key := effectiveness_key(element_multiplier)
	_show_effectiveness(element_multiplier)
	if effect_key.is_empty():
		_feedback.text = tr("BATTLE_EVENT_ATTACK") % [_actor_name(actor_name), action_label]
	else:
		_feedback.text = tr("BATTLE_EVENT_ATTACK_EFFECTIVE") % [
			_actor_name(actor_name), action_label, tr(effect_key),
		]
	await _event_pause(AnimaPresenter.FX_TRAVEL_SEC)
	_damage.text = tr("BATTLE_DAMAGE") % LocaleManager.format_integer(int(event.get("damage", 0)))
	_damage.visible = true
	if target_name == "player":
		_player_hp.value = int(event.get("target_hp", 0))
	else:
		_bot_hp.value = int(event.get("target_hp", 0))
	if is_instance_valid(target):
		if UiMotion.reduced_motion:
			target.modulate = Color.WHITE
		else:
			target.modulate = Color(1.65, 0.45, 0.55, 1.0)
			var flash := create_tween()
			flash.tween_property(target, "modulate", Color.WHITE, 0.28)
			Input.vibrate_handheld(55 if element_multiplier > 1.0 else 35)
	if not UiMotion.reduced_motion:
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
	await _hide_effectiveness()
	if is_instance_valid(attacker):
		attacker.set_pose("idle")


func _show_effectiveness(multiplier: float) -> void:
	var key := effectiveness_key(multiplier)
	var color := DAMAGE_COLOR
	if key == "BATTLE_EFFECTIVE":
		color = EFFECTIVE_COLOR
	elif key == "BATTLE_NOT_EFFECTIVE":
		color = RESISTED_COLOR
	_effectiveness.visible = not key.is_empty()
	if not _effectiveness.visible:
		_damage.add_theme_color_override("font_color", color)
		return
	if is_instance_valid(_effectiveness_tween):
		_effectiveness_tween.kill()
	_effectiveness.modulate = Color.WHITE
	_effectiveness.scale = Vector2.ONE
	_effectiveness_badge.rotation = 0.0
	_effectiveness_label.text = tr(key)
	_effectiveness_label.add_theme_color_override("font_color", color)
	_effectiveness_label.add_theme_color_override(
		"font_shadow_color", Color(color.r, color.g, color.b, 0.48)
	)
	_damage.add_theme_color_override("font_color", color)
	_damage.add_theme_font_size_override(
		"font_size", 54 if key == "BATTLE_EFFECTIVE" else 46
	)
	if UiMotion.reduced_motion:
		return
	_effectiveness.modulate.a = 0.0
	_effectiveness.scale = Vector2(0.70, 0.70)
	_effectiveness_badge.rotation = deg_to_rad(
		-3.5 if key == "BATTLE_EFFECTIVE" else 3.5
	)
	_effectiveness_tween = create_tween().set_parallel(true)
	_effectiveness_tween.tween_property(_effectiveness, "modulate:a", 1.0, 0.08)
	_effectiveness_tween.tween_property(_effectiveness, "scale", Vector2(1.08, 1.08), 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_effectiveness_tween.tween_property(_effectiveness_badge, "rotation", 0.0, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
static func effectiveness_key(multiplier: float) -> String:
	if multiplier > 1.0:
		return "BATTLE_EFFECTIVE"
	if multiplier < 1.0:
		return "BATTLE_NOT_EFFECTIVE"
	return ""


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
		var target := str(event.get("target", ""))
		var state := _as_dict(_session.get("state"))
		var actor_state := _as_dict(state.get(actor))
		var target_state := _as_dict(state.get(target))
		var actor_speed := int(actor_state.get("spd", 0))
		var target_speed := int(target_state.get("spd", 0))
		if actor_speed == target_speed:
			_feedback.text = tr("BATTLE_INITIATIVE_TIE") % _actor_name(actor)
		else:
			_feedback.text = tr("BATTLE_INITIATIVE") % [
				_actor_name(actor),
				LocaleManager.format_integer(actor_speed),
				LocaleManager.format_integer(target_speed),
			]
		await _event_pause(0.36)
		return


func _apply_state() -> void:
	var state := _as_dict(_session.get("state"))
	var player := _as_dict(state.get("player"))
	var bot := _as_dict(state.get("bot"))
	_player_hp.max_value = maxf(1.0, float(player.get("max_hp", 1)))
	_bot_hp.max_value = maxf(1.0, float(bot.get("max_hp", 1)))
	_player_hp.value = float(player.get("hp", 0))
	_bot_hp.value = float(bot.get("hp", 0))
	_player_hp_value.text = LocaleManager.format_ratio(
		int(player.get("hp", 0)), int(player.get("max_hp", 1))
	)
	_bot_hp_value.text = LocaleManager.format_ratio(
		int(bot.get("hp", 0)), int(bot.get("max_hp", 1))
	)
	_turn_label.text = tr("BATTLE_TURN") % LocaleManager.format_integer(
		int(_session.get("turn_number", state.get("turn", 1)))
	)
	var daily_reward := _as_dict(_session.get("daily_reward"))
	var training := _is_training(daily_reward)
	_daily_reward_label.visible = not daily_reward.is_empty()
	if _daily_reward_label.visible:
		var counter := _daily_counter_text(daily_reward)
		var tier := str(_session.get("reward_tier", ""))
		if not tier.is_empty():
			counter = "%s · %s" % [
				counter,
				tr("BATTLE_REWARD_PAYOUT") % [
					_tier_label(tier),
					LocaleManager.format_integer(int(_session.get("reward_bits", 0))),
				],
			]
		_daily_reward_label.text = counter
	var status := str(_session.get("status", state.get("status", "active")))
	_result_panel.visible = status != "active"
	_actions.visible = status == "active"
	_forfeit_button.visible = status == "active"
	if status == "active":
		# PP hanya pulih lewat Guard, jadi tombol yang mati butuh satu kalimat yang
		# menyebutkan jalan keluarnya; tanpa ini pemain kehabisan PP tanpa tahu sebabnya.
		if int(player.get("momentum", 0)) < SURGE_COST:
			_feedback.text = tr("BATTLE_NO_MOMENTUM")
		elif training and _is_bits_capped(daily_reward):
			_feedback.text = tr("BATTLE_TRAINING_HINT")
		elif training:
			_feedback.text = tr("BATTLE_TRAINING_BITS_HINT")
		else:
			_feedback.text = tr("BATTLE_CHOOSE_ACTION")
	else:
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
			_result_body.text = _win_body(reward)
			if is_instance_valid(_player_sprite):
				_player_sprite.set_pose("happy")
		"lost":
			_result_title.text = tr("BATTLE_LOSS_TITLE")
			_result_body.text = tr("BATTLE_LOSS_BODY")
		_:
			_result_title.text = tr("BATTLE_FORFEIT_TITLE")
			_result_body.text = tr("BATTLE_FORFEIT_BODY")
	_retry_button.text = tr("BATTLE_TRAIN_AGAIN" if training else "BATTLE_AGAIN")


func _win_body(reward: Dictionary) -> String:
	var bits := int(reward.get("bits", 0))
	if int(reward.get("care_score", 0)) > 0:
		return tr("BATTLE_WIN_BODY") % LocaleManager.format_integer(bits)
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
	var item_used := (
		not str(_session.get("item_used_id", "")).is_empty()
		or bool(player.get("item_used", false))
	)
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
	_item_button.text = tr("BATTLE_ITEM_USED" if item_used else "BATTLE_ACTION_ITEM")
	_item_button.self_modulate = (
		Color(1, 1, 1, 0.42) if item_used and not committed else Color.WHITE
	)
	_forfeit_button.disabled = _busy or not active


func _apply_element(icon: TextureRect, label: Label, element: String) -> void:
	var normalized := element.to_lower()
	if not _element_icons.has(normalized):
		normalized = "stone"
	icon.texture = _element_icons[normalized] as Texture2D
	label.text = LocaleManager.element_name(normalized)


func _position_fighters() -> void:
	if not is_instance_valid(_arena):
		return
	var ground_y := _arena.size.y * 0.88
	_player_anchor.position = Vector2(_arena.size.x * 0.27, ground_y)
	_bot_anchor.position = Vector2(_arena.size.x * 0.73, ground_y)


func _sprite_for(actor: String) -> AnimaPresenter:
	return _player_sprite if actor == "player" else _bot_sprite


func _actor_name(actor: String) -> String:
	return _player_name.text if actor == "player" else _bot_name.text


func _move_label(action: String, snapshot: Dictionary) -> String:
	return LocaleManager.move_name(snapshot, action)


func _event_pause(seconds: float) -> void:
	if UiMotion.reduced_motion:
		return
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
