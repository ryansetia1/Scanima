class_name BattleView
extends Control

const BATTLE_EVENT := preload("res://scripts/battle_event.gd")

signal start_requested
signal action_requested(action: String)
signal resume_requested
signal forfeit_requested

@export var metal_icon: Texture2D
@export var plant_icon: Texture2D
@export var flow_icon: Texture2D
@export var spark_icon: Texture2D
@export var cloth_icon: Texture2D
@export var stone_icon: Texture2D

@onready var _lobby_panel: PanelContainer = %BattleLobbyPanel
@onready var _lobby_name: Label = %BattleLobbyName
@onready var _lobby_meta: Label = %BattleLobbyMeta
@onready var _start_button: Button = %BattleStartButton
@onready var _battle_content: VBoxContainer = %BattleContent
@onready var _turn_label: Label = %BattleTurn
@onready var _momentum_label: Label = %BattleMomentum
@onready var _player_name: Label = %BattlePlayerName
@onready var _bot_name: Label = %BattleBotName
@onready var _player_element_icon: TextureRect = %BattlePlayerElementIcon
@onready var _bot_element_icon: TextureRect = %BattleBotElementIcon
@onready var _player_element: Label = %BattlePlayerElement
@onready var _bot_element: Label = %BattleBotElement
@onready var _player_hp: ProgressBar = %BattlePlayerHp
@onready var _bot_hp: ProgressBar = %BattleBotHp
@onready var _arena: Control = %BattleArena
@onready var _player_anchor: Node2D = %BattlePlayerAnchor
@onready var _bot_anchor: Node2D = %BattleBotAnchor
@onready var _player_sprite: AnimaPresenter = %BattlePlayerSprite
@onready var _bot_sprite: AnimaPresenter = %BattleBotSprite
@onready var _feedback: Label = %BattleFeedback
@onready var _damage: Label = %BattleDamage
@onready var _actions: HBoxContainer = %Actions
@onready var _strike_button: Button = %BattleStrikeButton
@onready var _surge_button: Button = %BattleSurgeButton
@onready var _guard_button: Button = %BattleGuardButton
@onready var _forfeit_button: Button = %BattleForfeitButton
@onready var _result_panel: PanelContainer = %BattleResultPanel
@onready var _result_title: Label = %BattleResultTitle
@onready var _result_body: Label = %BattleResultBody
@onready var _retry_button: Button = %BattleRetryButton

var _lobby_row: Dictionary = {}
var _session: Dictionary = {}
var _busy := false
var _element_icons: Dictionary = {}


func _ready() -> void:
	_element_icons = {
		"metal": metal_icon,
		"plant": plant_icon,
		"flow": flow_icon,
		"spark": spark_icon,
		"cloth": cloth_icon,
		"stone": stone_icon,
	}
	_start_button.pressed.connect(start_requested.emit)
	_strike_button.pressed.connect(action_requested.emit.bind("strike"))
	_surge_button.pressed.connect(action_requested.emit.bind("surge"))
	_guard_button.pressed.connect(action_requested.emit.bind("guard"))
	_forfeit_button.pressed.connect(forfeit_requested.emit)
	_retry_button.pressed.connect(resume_requested.emit)
	_arena.resized.connect(_position_fighters)
	_position_fighters.call_deferred()
	_player_sprite.set_facing(1.0)
	_bot_sprite.set_facing(-1.0)
	set_lobby({})


func set_lobby(row: Dictionary) -> void:
	_lobby_row = row.duplicate(true)
	_session = {}
	_lobby_panel.visible = true
	_battle_content.visible = false
	_result_panel.visible = false
	_start_button.visible = true
	var unavailable_key := _lobby_unavailable_key()
	if unavailable_key.is_empty():
		_lobby_name.text = LocaleManager.display_name(_lobby_row)
		_lobby_meta.text = tr("BATTLE_LOBBY_READY") % [
			LocaleManager.element_name(str(_lobby_row.get("element", ""))),
			LocaleManager.stage_name(int(_lobby_row.get("stage", 1))),
		]
	else:
		_lobby_name.text = tr("BATTLE_LOBBY_TITLE")
		_lobby_meta.text = tr(unavailable_key)
	_start_button.disabled = _busy or not unavailable_key.is_empty()


func set_loading(message_key: String = "BATTLE_CONNECTING") -> void:
	_result_panel.visible = false
	if not _session.is_empty():
		_lobby_panel.visible = false
		_battle_content.visible = true
		_feedback.text = tr(message_key)
		_actions.visible = false
		_forfeit_button.visible = false
		return
	_lobby_panel.visible = true
	_battle_content.visible = false
	_lobby_name.text = tr("BATTLE_LOBBY_TITLE")
	_lobby_meta.text = tr(message_key)
	_start_button.visible = false


func set_session(
	battle_session: Dictionary,
	player_loaded: Dictionary = {},
	bot_loaded: Dictionary = {}
) -> void:
	_session = battle_session.duplicate(true)
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


func set_busy(busy: bool) -> void:
	_busy = busy
	_start_button.disabled = busy or not _lobby_is_eligible()
	_update_action_state()


func set_error(error_code: String) -> void:
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
	_feedback.text = tr("BATTLE_EVENT_ATTACK") % [
		_actor_name(actor_name),
		tr("BATTLE_ACTION_SURGE")
		if str(event.get("action", "")) == "surge"
		else tr("BATTLE_ACTION_STRIKE"),
	]
	await _event_pause(0.20)
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
			Input.vibrate_handheld(35)
	if not UiMotion.reduced_motion:
		_damage.modulate = Color.WHITE
		var float_damage := create_tween().set_parallel(true)
		float_damage.tween_property(_damage, "position:y", _damage.position.y - 28.0, 0.36)
		float_damage.tween_property(_damage, "modulate:a", 0.0, 0.36)
		await _event_pause(0.40)
		_damage.position.y += 28.0
		_damage.modulate = Color.WHITE
	_damage.visible = false
	if is_instance_valid(attacker):
		attacker.set_pose("idle")


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
	_turn_label.text = tr("BATTLE_TURN") % LocaleManager.format_integer(
		int(_session.get("turn_number", state.get("turn", 1)))
	)
	_momentum_label.text = tr("BATTLE_MOMENTUM") % [
		LocaleManager.format_integer(int(player.get("momentum", 0))),
		LocaleManager.format_integer(5),
	]
	var status := str(_session.get("status", state.get("status", "active")))
	_result_panel.visible = status != "active"
	_actions.visible = status == "active"
	_forfeit_button.visible = status == "active"
	if status == "active":
		_feedback.text = tr("BATTLE_CHOOSE_ACTION")
	else:
		_show_result(status)
	_update_action_state()


func _show_result(status: String) -> void:
	_result_panel.visible = true
	_retry_button.visible = true
	match status:
		"won":
			_result_title.text = tr("BATTLE_WIN_TITLE")
			_result_body.text = tr("BATTLE_WIN_BODY")
		"lost":
			_result_title.text = tr("BATTLE_LOSS_TITLE")
			_result_body.text = tr("BATTLE_LOSS_BODY")
		_:
			_result_title.text = tr("BATTLE_FORFEIT_TITLE")
			_result_body.text = tr("BATTLE_FORFEIT_BODY")
	_retry_button.text = tr("BATTLE_AGAIN")


func _update_action_state() -> void:
	var state := _as_dict(_session.get("state"))
	var player := _as_dict(state.get("player"))
	var active := str(_session.get("status", state.get("status", ""))) == "active"
	_strike_button.disabled = _busy or not active
	_guard_button.disabled = _busy or not active
	_surge_button.disabled = _busy or not active or int(player.get("momentum", 0)) < 2
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


func _event_pause(seconds: float) -> void:
	if UiMotion.reduced_motion:
		return
	await get_tree().create_timer(seconds).timeout


func _error_copy(error_code: String) -> String:
	var key: String = str({
		"ANIMA_SLEEPING": "BATTLE_ANIMA_SLEEPING",
		"ANIMA_DORMANT": "BATTLE_ANIMA_DORMANT",
		"ANIMA_NOT_READY": "BATTLE_ANIMA_NOT_READY",
		"NO_BATTLE_OPPONENT": "BATTLE_NO_OPPONENT",
		"NO_MOMENTUM": "BATTLE_NO_MOMENTUM",
		"BATTLE_EXPIRED": "BATTLE_EXPIRED",
		"AUTH_EXPIRED": "BATTLE_AUTH_EXPIRED",
	}.get(error_code, "BATTLE_ERROR_GENERIC"))
	return tr(key)


func _lobby_unavailable_key() -> String:
	if _lobby_row.is_empty():
		return "BATTLE_NO_ANIMA"
	if str(_lobby_row.get("status", "")) != "ready":
		return "BATTLE_ANIMA_NOT_READY"
	if _has_timestamp(_lobby_row.get("sleep_started_at")):
		return "BATTLE_ANIMA_SLEEPING"
	if _has_timestamp(_lobby_row.get("dormant_since")):
		return "BATTLE_ANIMA_DORMANT"
	return ""


func _lobby_is_eligible() -> bool:
	return _lobby_unavailable_key().is_empty()


static func _has_timestamp(value: Variant) -> bool:
	return value != null and not str(value).is_empty()


static func _as_dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
