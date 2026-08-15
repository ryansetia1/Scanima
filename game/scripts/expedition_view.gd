class_name ExpeditionView
extends Control

signal back_requested
signal chapter_requested(chapter_version_id: String)
signal save_team_requested(anima_ids: Array[String])
signal start_run_requested(chapter_version_id: String, team_id: String)
signal start_zone_requested(run_id: String, team_id: String)
signal enter_node_requested(node_id: String)
signal choice_requested(option_id: String, target_slot: int)
signal refresh_shop_requested
signal abandon_requested
signal action_requested(action: String, switch_to_slot: int)
signal item_picker_requested
signal forfeit_requested
signal combat_continue_requested
signal complete_requested
signal combat_open_changed(open: bool)

const DIM := Color(1.0, 1.0, 1.0, 0.42)

@onready var _column: VBoxContainer = %ExpeditionColumn
@onready var _back: Button = %ExpeditionBack
@onready var _loading: VBoxContainer = %ExpeditionLoading
@onready var _loading_label: Label = %ExpeditionLoadingLabel
@onready var _catalog: VBoxContainer = %ExpeditionCatalog
@onready var _chapter_list: ItemList = %ExpeditionChapterList
@onready var _catalog_meta: Label = %ExpeditionCatalogMeta
@onready var _open_chapter: Button = %ExpeditionOpenChapter
@onready var _catalog_team: Button = %ExpeditionCatalogTeam
@onready var _detail: VBoxContainer = %ExpeditionDetail
@onready var _detail_title: Label = %ExpeditionDetailTitle
@onready var _detail_body: Label = %ExpeditionDetailBody
@onready var _detail_trophy: Label = %ExpeditionDetailTrophy
@onready var _start_run: Button = %ExpeditionStartRun
@onready var _detail_team: Button = %ExpeditionDetailTeam
@onready var _builder: VBoxContainer = %ExpeditionBuilder
@onready var _builder_meta: Label = %ExpeditionBuilderMeta
@onready var _roster_list: ItemList = %ExpeditionRosterList
@onready var _builder_back: Button = %ExpeditionBuilderBack
@onready var _save_team: Button = %ExpeditionSaveTeam
@onready var _map: VBoxContainer = %ExpeditionMap
@onready var _map_meta: Label = %ExpeditionMapMeta
@onready var _party_meta: Label = %ExpeditionPartyMeta
@onready var _node_grid: GridContainer = %ExpeditionNodeGrid
@onready var _start_zone: Button = %ExpeditionStartZone
@onready var _abandon: Button = %ExpeditionAbandon
@onready var _choice: VBoxContainer = %ExpeditionChoice
@onready var _choice_title: Label = %ExpeditionChoiceTitle
@onready var _choice_meta: Label = %ExpeditionChoiceMeta
@onready var _choice_buttons: VBoxContainer = %ExpeditionChoiceButtons
@onready var _target_list: ItemList = %ExpeditionTargetList
@onready var _target_confirm: Button = %ExpeditionTargetConfirm
@onready var _refresh_shop: Button = %ExpeditionRefreshShop
@onready var _choice_abandon: Button = %ExpeditionChoiceAbandon
@onready var _complete: VBoxContainer = %ExpeditionComplete
@onready var _complete_title: Label = %ExpeditionCompleteTitle
@onready var _complete_body: Label = %ExpeditionCompleteBody
@onready var _combat: TeamBattleView = %ExpeditionCombat

var _chapters: Array = []
var _team: Dictionary = {}
var _roster: Array = []
var _chapter: Dictionary = {}
var _run: Dictionary = {}
var _selected_version := ""
var _pending_option: Dictionary = {}
var _busy := false
var _thumbnail_provider: Callable


func _ready() -> void:
	_back.tooltip_text = tr("ACTION_BACK")
	_choice_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_builder_back.flat = true
	_builder_back.custom_minimum_size.x = 112.0
	_builder_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_roster_list.fixed_icon_size = Vector2i(96, 96)
	_roster_list.max_columns = 1
	_roster_list.fixed_column_width = 0
	_back.pressed.connect(_on_back)
	_chapter_list.item_selected.connect(_select_chapter)
	_open_chapter.pressed.connect(_request_chapter)
	_catalog_team.pressed.connect(_open_builder)
	_start_run.pressed.connect(_request_start_run)
	_detail_team.pressed.connect(_open_builder)
	_roster_list.connect("selection_changed", _update_builder)
	_save_team.pressed.connect(_request_save_team)
	_start_zone.pressed.connect(_request_start_zone)
	_abandon.pressed.connect(abandon_requested.emit)
	_target_confirm.pressed.connect(_confirm_target)
	_target_list.item_selected.connect(func(_index: int) -> void:
		_target_confirm.disabled = _busy
	)
	_refresh_shop.pressed.connect(refresh_shop_requested.emit)
	_choice_abandon.pressed.connect(abandon_requested.emit)
	%ExpeditionDetailBack.pressed.connect(func() -> void: _show_only(_catalog))
	_builder_back.pressed.connect(_leave_builder)
	%ExpeditionCompleteBack.pressed.connect(complete_requested.emit)
	_combat.set_expedition_mode(true)
	_combat.action_requested.connect(func(action: String, slot: int) -> void:
		action_requested.emit(action, slot)
	)
	_combat.item_picker_requested.connect(item_picker_requested.emit)
	_combat.forfeit_requested.connect(forfeit_requested.emit)
	_combat.retry_requested.connect(combat_continue_requested.emit)
	_show_only(_loading)


func open_mode() -> void:
	visible = true


func close_mode(force: bool = false) -> void:
	if not force and has_active_encounter():
		return
	visible = false
	_emit_combat_open()


func is_open() -> bool:
	return visible


func set_thumbnail_provider(provider: Callable) -> void:
	_thumbnail_provider = provider


func has_active_encounter() -> bool:
	return (
		_combat.visible
		and str(_combat.session_data().get("status", "")) == "active"
	)


func is_combat_open() -> bool:
	return visible and is_instance_valid(_combat) and _combat.visible


func handle_back() -> bool:
	if not visible:
		return false
	if _combat.visible:
		if _combat.handle_back():
			return true
		if has_active_encounter():
			return true
	if _builder.visible:
		_leave_builder()
		return true
	if _detail.visible or _complete.visible:
		_show_only(_catalog)
		return true
	if _choice.visible:
		# ponytail: entering a node is server-committed. Back cannot undo it;
		# the visible Abandon action is the explicit escape hatch.
		return true
	back_requested.emit()
	return true


func set_loading(message_key: String = "EXPEDITION_LOADING") -> void:
	_show_only(_loading)
	_loading_label.text = tr(message_key)


func set_error(error_code: String) -> void:
	_show_only(_loading)
	_loading_label.text = tr("EXPEDITION_ERROR") % tr(_error_key(error_code))
	_sync_back_chrome()
	_back.disabled = false


func set_busy(busy: bool) -> void:
	_busy = busy
	_sync_back_chrome()
	_open_chapter.disabled = busy or _selected_version.is_empty()
	_catalog_team.disabled = busy
	_detail_team.disabled = busy
	_start_run.disabled = busy or _selected_version.is_empty() or _team_id().is_empty()
	_save_team.disabled = busy or _selected_roster_ids().size() != 4
	_start_zone.disabled = busy or _team_id().is_empty()
	_abandon.disabled = busy
	_choice_abandon.disabled = busy
	_target_confirm.disabled = busy or _target_list.get_selected_items().is_empty()
	_refresh_shop.disabled = busy or bool(_run.get("shop_refreshed", false))
	for child in _choice_buttons.get_children():
		if child is Button:
			(child as Button).disabled = busy or bool(child.get_meta("locked", false))
	_combat.set_busy(busy)


func set_catalog(chapters: Array, team: Dictionary = {}) -> void:
	_chapters = chapters.duplicate(true)
	_team = team.duplicate(true)
	_chapter = {}
	_run = {}
	_selected_version = ""
	_chapter_list.clear()
	for value in _chapters:
		var chapter := GameState.as_dict(value)
		if chapter.is_empty():
			continue
		var unlocked := bool(chapter.get("unlocked", false))
		var cleared := chapter.get("first_cleared_at") != null
		var summary := GameState.as_dict(chapter.get("summary"))
		var title := str(summary.get("title", chapter.get("slug", tr("EXPEDITION_CHAPTER"))))
		var state := tr(
			"EXPEDITION_CHAPTER_CLEARED"
			if cleared else ("EXPEDITION_CHAPTER_OPEN" if unlocked else "EXPEDITION_CHAPTER_LOCKED")
		)
		_chapter_list.add_item("%s\n%s" % [title, state])
		var index := _chapter_list.item_count - 1
		_chapter_list.set_item_metadata(index, chapter)
		_chapter_list.set_item_disabled(index, not unlocked)
		if not unlocked:
			_chapter_list.set_item_icon_modulate(index, DIM)
	_catalog_meta.text = (
		tr("EXPEDITION_CATALOG_EMPTY")
		if _chapter_list.item_count == 0 else tr("EXPEDITION_CATALOG_HINT")
	)
	_catalog_team.text = tr(
		"EXPEDITION_EDIT_TEAM" if not _team_id().is_empty() else "EXPEDITION_BUILD_TEAM"
	)
	_show_only(_catalog)
	if _chapter_list.item_count > 0 and not _chapter_list.is_item_disabled(0):
		_chapter_list.select(0)
		_select_chapter(0)
	set_busy(false)


func set_chapter_detail(data: Dictionary) -> void:
	_chapter = data.duplicate(true)
	var entry := GameState.as_dict(_chapter.get("chapter"))
	var manifest := GameState.as_dict(_chapter.get("manifest"))
	var summary := GameState.as_dict(manifest.get("summary"))
	_selected_version = str(entry.get("version_id", _selected_version))
	_detail_title.text = str(summary.get("title", tr("EXPEDITION_CHAPTER")))
	_detail_body.text = str(summary.get("description", tr("EXPEDITION_CHAPTER_READY")))
	var trophy := GameState.as_dict(entry.get("trophy"))
	_detail_trophy.text = tr("EXPEDITION_TROPHY_PREVIEW") % str(
		trophy.get("display_name", tr("EXPEDITION_TROPHY_UNKNOWN"))
	)
	_show_only(_detail)
	set_busy(false)


func set_builder(roster: Array, team: Dictionary = {}) -> void:
	_roster = roster.duplicate(true)
	if not team.is_empty():
		_team = team.duplicate(true)
	_roster_list.clear()
	var selected_ids := _team_member_ids()
	for value in _roster:
		var row := GameState.as_dict(value)
		var unavailable := _member_unavailable(row)
		_roster_list.add_item(tr("TEAM_ROSTER_ROW") % [
			LocaleManager.display_name(row),
			tr(_member_status_key(unavailable)),
			LocaleManager.element_compact(row),
		], _thumbnail_provider.call(row) if _thumbnail_provider.is_valid() else null)
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
	set_busy(false)


func set_team(team: Dictionary) -> void:
	_team = team.duplicate(true)
	_catalog_team.text = tr("EXPEDITION_EDIT_TEAM")
	_detail_team.text = tr("EXPEDITION_EDIT_TEAM")


func set_run(
	run_data: Dictionary,
	encounter: Dictionary = {},
	art_cache: Dictionary = {}
) -> void:
	_run = run_data.duplicate(true)
	# Present happens while the controller is still busy. Build tappable
	# map/choice controls now; set_busy(false) later cannot rewrite them.
	_busy = false
	if str(_run.get("status", "")) == "complete":
		_complete_title.text = tr("EXPEDITION_COMPLETE_TITLE")
		_complete_body.text = tr("EXPEDITION_COMPLETE_BODY")
		_show_only(_complete)
		return
	if not encounter.is_empty():
		_column.visible = false
		_combat.visible = true
		_combat.set_arena_location(_location_text())
		_combat.set_session(encounter, art_cache)
		_emit_combat_open()
		return
	_combat.set_arena_location("")
	_combat.visible = false
	_column.visible = true
	_emit_combat_open()
	var pending := GameState.as_dict(_run.get("pending_node"))
	if not pending.is_empty() and not str(pending.get("kind", "")) in ["battle", "elite", "boss"]:
		_show_choice(pending)
		return
	_render_map()
	_show_only(_map)
	set_busy(false)


func combat_session_data() -> Dictionary:
	return _combat.session_data()


func begin_combat_action(action: String) -> void:
	_combat.begin_action(action)


func play_combat_events(
	events: Array,
	next_encounter: Dictionary,
	art_cache: Dictionary = {}
) -> void:
	await _combat.play_events(events, next_encounter, art_cache)


func _show_only(panel: Control) -> void:
	_column.visible = true
	_combat.visible = false
	_emit_combat_open()
	for child in [_loading, _catalog, _detail, _builder, _map, _choice, _complete]:
		(child as Control).visible = child == panel
	_sync_back_chrome()


func _select_chapter(index: int) -> void:
	if index < 0 or index >= _chapter_list.item_count:
		return
	var chapter := GameState.as_dict(_chapter_list.get_item_metadata(index))
	_selected_version = str(chapter.get("version_id", ""))
	var summary := GameState.as_dict(chapter.get("summary"))
	_catalog_meta.text = str(summary.get("description", tr("EXPEDITION_CATALOG_HINT")))
	set_busy(_busy)


func _request_chapter() -> void:
	if not _busy and not _selected_version.is_empty():
		chapter_requested.emit(_selected_version)


func _request_start_run() -> void:
	if not _busy and not _selected_version.is_empty() and not _team_id().is_empty():
		start_run_requested.emit(_selected_version, _team_id())


func _open_builder() -> void:
	set_builder(_roster, _team)


func _leave_builder() -> void:
	_show_only(_detail if not _chapter.is_empty() else _catalog)


func _request_save_team() -> void:
	var ids := _selected_roster_ids()
	if not _busy and ids.size() == 4:
		save_team_requested.emit(ids)


func _request_start_zone() -> void:
	if not _busy and not _team_id().is_empty():
		start_zone_requested.emit(str(_run.get("id", "")), _team_id())


func _render_map() -> void:
	for child in _node_grid.get_children():
		child.free()
	var zone := int(_run.get("zone", 1))
	_map_meta.text = tr("EXPEDITION_MAP_STATUS") % [
		LocaleManager.format_integer(zone),
		LocaleManager.format_integer(int(_run.get("supplies", 0))),
	]
	_party_meta.text = _party_text(_as_array(_run.get("party_state")))
	var map := GameState.as_dict(_run.get("zone_map"))
	var nodes := _as_array(map.get("nodes"))
	nodes.sort_custom(func(left: Variant, right: Variant) -> bool:
		var a := GameState.as_dict(left)
		var b := GameState.as_dict(right)
		var a_depth := int(a.get("depth", 0))
		var b_depth := int(b.get("depth", 0))
		return (
			a_depth < b_depth
			or (a_depth == b_depth and str(a.get("id", "")) < str(b.get("id", "")))
		)
	)
	var available := _string_array(_run.get("available_node_ids"))
	for value in nodes:
		var node := GameState.as_dict(value)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 96)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = tr("EXPEDITION_NODE_ROW") % [
			tr(_node_kind_key(str(node.get("kind", "")))),
			tr("EXPEDITION_DEPTH") % LocaleManager.format_integer(int(node.get("depth", 0))),
		]
		var node_id := str(node.get("id", ""))
		button.disabled = not node_id in available
		button.pressed.connect(func() -> void: enter_node_requested.emit(node_id))
		_node_grid.add_child(button)
	var checkpoint := str(_run.get("status", "")) == "checkpoint"
	_start_zone.visible = checkpoint
	_node_grid.visible = not checkpoint
	_party_meta.visible = not checkpoint
	_start_zone.disabled = _busy or _team_id().is_empty()


func _show_choice(node: Dictionary) -> void:
	_choice_title.text = tr(_node_kind_key(str(node.get("kind", ""))))
	for child in _choice_buttons.get_children():
		child.free()
	var options: Array[Dictionary] = []
	var spendable := false
	for value in _as_array(node.get("options")):
		var option := GameState.as_dict(value)
		if option.is_empty():
			continue
		options.append(option)
		if _discounted_cost(int(option.get("cost_supplies", 0))) > 0:
			spendable = true
	var grant := _single_free_grant(options)
	if not grant.is_empty():
		_choice_meta.text = _option_label(grant)
		var continue_button := Button.new()
		continue_button.custom_minimum_size = Vector2(0, 96)
		continue_button.theme_type_variation = &"PrimaryButton"
		continue_button.text = tr("EXPEDITION_CHOICE_CONTINUE")
		continue_button.pressed.connect(_choose_option.bind(grant))
		_choice_buttons.add_child(continue_button)
	else:
		_choice_meta.text = (
			tr("EXPEDITION_CHOICE_SUPPLIES") % LocaleManager.format_integer(
				int(_run.get("supplies", 0))
			)
			if spendable else ""
		)
		for option in options:
			var button := Button.new()
			button.custom_minimum_size = Vector2(0, 96)
			var title := _option_label(option)
			var cost := _discounted_cost(int(option.get("cost_supplies", 0)))
			button.text = (
				tr("EXPEDITION_OPTION_COST") % [title, LocaleManager.format_integer(cost)]
				if cost > 0 else title
			)
			button.set_meta("locked", cost > int(_run.get("supplies", 0)))
			button.disabled = _busy or bool(button.get_meta("locked"))
			button.pressed.connect(_choose_option.bind(option))
			_choice_buttons.add_child(button)
	_choice_meta.visible = not _choice_meta.text.is_empty()
	_target_list.visible = false
	_target_confirm.visible = false
	_pending_option = {}
	var shop := str(node.get("kind", "")) == "shop"
	_refresh_shop.visible = shop and not bool(_run.get("shop_refreshed", false))
	_refresh_shop.disabled = _busy
	_show_only(_choice)


func _choose_option(option: Dictionary) -> void:
	var effect := GameState.as_dict(option.get("effect"))
	if str(effect.get("type", "")) not in ["heal_target", "revive_target"]:
		choice_requested.emit(str(option.get("id", "")), -1)
		return
	_pending_option = option.duplicate(true)
	_target_list.clear()
	var revive := str(effect.get("type", "")) == "revive_target"
	for value in _as_array(_run.get("party_state")):
		var member := GameState.as_dict(value)
		var hp := int(member.get("hp", 0))
		var maximum := maxi(1, int(member.get("max_hp", 1)))
		_target_list.add_item(tr("EXPEDITION_TARGET_ROW") % [
			str(member.get("name", tr("ANIMA_FALLBACK_NAME"))),
			LocaleManager.format_integer(hp),
			LocaleManager.format_integer(maximum),
		])
		var index := _target_list.item_count - 1
		_target_list.set_item_disabled(index, hp > 0 if revive else hp <= 0)
	_target_list.visible = true
	_target_confirm.visible = true
	_target_confirm.disabled = true


func _confirm_target() -> void:
	var selected := _target_list.get_selected_items()
	if _pending_option.is_empty() or selected.is_empty():
		return
	choice_requested.emit(str(_pending_option.get("id", "")), int(selected[0]))


func _update_builder() -> void:
	var count := _selected_roster_ids().size()
	_builder_meta.text = tr("EXPEDITION_TEAM_COUNT") % [
		LocaleManager.format_integer(count),
		LocaleManager.format_integer(4),
	]
	_save_team.disabled = _busy or count != 4


func _selected_roster_ids() -> Array[String]:
	var result: Array[String] = []
	for index in _roster_list.get_selected_items():
		var row := GameState.as_dict(_roster_list.get_item_metadata(index))
		var anima_id := str(row.get("id", ""))
		if not anima_id.is_empty():
			result.append(anima_id)
	return result


func _team_member_ids() -> Array[String]:
	var result: Array[String] = []
	for value in _as_array(_team.get("members")):
		var anima_id := str(GameState.as_dict(value).get("anima_id", ""))
		if not anima_id.is_empty():
			result.append(anima_id)
	return result


func _member_unavailable(row: Dictionary) -> String:
	if str(row.get("status", "")) != "ready":
		return "TEAM_MEMBER_NOT_READY_COPY"
	if row.get("dormant_since") != null and not str(row.get("dormant_since", "")).is_empty():
		return "TEAM_MEMBER_DORMANT_COPY"
	if float(GameState.as_dict(row.get("care")).get("energy", 0.0)) < 30.0:
		return "TEAM_MEMBER_LOW_ENERGY_COPY"
	return ""


static func _member_status_key(unavailable: String) -> String:
	match unavailable:
		"TEAM_MEMBER_NOT_READY_COPY":
			return "BATTLE_PICK_NOT_READY"
		"TEAM_MEMBER_DORMANT_COPY":
			return "BATTLE_PICK_DORMANT"
		"TEAM_MEMBER_LOW_ENERGY_COPY":
			return "BATTLE_PICK_LOW_ENERGY"
		_:
			return "TEAM_ROSTER_READY"


func _team_id() -> String:
	var id := str(_team.get("id", ""))
	if not id.is_empty():
		return id
	return str(_run.get("team_id", ""))


func _location_text() -> String:
	return tr("EXPEDITION_ARENA_LOCATION") % [
		_chapter_title(),
		LocaleManager.format_integer(int(_run.get("zone", 1))),
	]


func _chapter_title() -> String:
	var summary := GameState.as_dict(GameState.as_dict(_chapter.get("manifest")).get("summary"))
	var title := str(summary.get("title", "")).strip_edges()
	if not title.is_empty():
		return title
	var version_id := str(_run.get("chapter_version_id", _selected_version))
	for value in _chapters:
		var chapter := GameState.as_dict(value)
		if str(chapter.get("version_id", "")) != version_id:
			continue
		title = str(GameState.as_dict(chapter.get("summary")).get("title", "")).strip_edges()
		if not title.is_empty():
			return title
	return tr("EXPEDITION_CHAPTER")


func _party_text(party: Array) -> String:
	var labels: PackedStringArray = []
	for value in party:
		var member := GameState.as_dict(value)
		labels.append("%s %s/%s" % [
			str(member.get("name", tr("ANIMA_FALLBACK_NAME"))),
			LocaleManager.format_integer(int(member.get("hp", 0))),
			LocaleManager.format_integer(int(member.get("max_hp", 0))),
		])
	return " · ".join(labels)


func _discounted_cost(base_cost: int) -> int:
	var discount := 0.0
	for value in _as_array(_run.get("boosts")):
		var boost := GameState.as_dict(value)
		if str(boost.get("type", "")) == "shop_discount":
			discount += clampf(float(boost.get("value", 0.0)), 0.0, 0.75)
	return ceili(float(maxi(0, base_cost)) * (1.0 - minf(0.75, discount)))


func _single_free_grant(options: Array[Dictionary]) -> Dictionary:
	if options.size() != 1:
		return {}
	var option := options[0]
	var effect := GameState.as_dict(option.get("effect"))
	if _discounted_cost(int(option.get("cost_supplies", 0))) > 0:
		return {}
	if str(effect.get("type", "")) in ["heal_target", "revive_target"]:
		return {}
	return option


func _sync_back_chrome() -> void:
	var hide := _choice.visible
	_back.visible = not hide
	_back.disabled = _busy or hide


func _option_label(option: Dictionary) -> String:
	var title_key := str(option.get("title_key", ""))
	if not title_key.is_empty():
		return tr(title_key)
	return _effect_label(GameState.as_dict(option.get("effect")))


func _effect_label(effect: Dictionary) -> String:
	match str(effect.get("type", "")):
		"supplies":
			return tr("EXPEDITION_EFFECT_SUPPLIES") % LocaleManager.format_integer(
				int(effect.get("value", 0))
			)
		"heal_party":
			return tr("EXPEDITION_EFFECT_HEAL_PARTY") % _effect_percent(effect)
		"heal_target":
			return tr("EXPEDITION_EFFECT_HEAL_ONE") % _effect_percent(effect)
		"revive_target":
			return tr("EXPEDITION_EFFECT_REVIVE")
		"stat_boost":
			return tr("EXPEDITION_EFFECT_STAT") % [
				tr(_stat_key(str(effect.get("stat", "")))),
				_effect_percent(effect),
			]
		"start_pp":
			return tr("EXPEDITION_EFFECT_START_PP")
		"shop_discount":
			return tr("EXPEDITION_EFFECT_SHOP_DISCOUNT") % _effect_percent(effect)
		_:
			return tr("EXPEDITION_CHOICE")


func _effect_percent(effect: Dictionary) -> String:
	var raw := float(effect.get("ratio", 0.0))
	if raw <= 0.0:
		raw = float(effect.get("value", 0.0))
	return LocaleManager.format_percent(raw * 100.0)


func _stat_key(stat: String) -> String:
	return str({
		"max_hp": "STAT_HP",
		"atk": "STAT_ATK",
		"def": "STAT_DEF",
		"spd": "STAT_SPD",
		"special": "STAT_SPECIAL",
	}.get(stat, "STAT_ATK"))


func _node_kind_key(kind: String) -> String:
	return str({
		"battle": "EXPEDITION_NODE_BATTLE",
		"elite": "EXPEDITION_NODE_ELITE",
		"recovery": "EXPEDITION_NODE_RECOVERY",
		"cache": "EXPEDITION_NODE_CACHE",
		"shop": "EXPEDITION_NODE_SHOP",
		"mystery": "EXPEDITION_NODE_MYSTERY",
		"boss": "EXPEDITION_NODE_BOSS",
	}.get(kind, "EXPEDITION_NODE_UNKNOWN"))


func _error_key(code: String) -> String:
	return str({
		"CHAPTER_REQUIRES_UPDATE": "EXPEDITION_CLIENT_UPDATE",
		"CHAPTER_NOT_AVAILABLE": "EXPEDITION_UNAVAILABLE",
		"CHAPTER_LOCKED": "EXPEDITION_UNAVAILABLE",
		"TEAM_REQUIRES_FOUR": "EXPEDITION_TEAM_INVALID",
		"TEAM_MEMBER_UNAVAILABLE": "EXPEDITION_TEAM_INVALID",
		"TEAM_MEMBER_LOW_ENERGY": "EXPEDITION_ENERGY_LOW",
		"EXPEDITION_TEAM_LOCKED": "EXPEDITION_TEAM_LOCKED",
		"TEAM_ART_NOT_READY": "TEAM_ART_NOT_READY_COPY",
		"NO_SUPPLIES": "EXPEDITION_SUPPLIES_LOW",
		"NO_BITS": "ERROR_NO_BITS",
		"NO_ITEM": "ERROR_NO_ITEM",
		"NO_MOMENTUM": "BATTLE_NO_MOMENTUM",
		"INVALID_EXPEDITION_MAP": "EXPEDITION_INVALID_MAP",
		"INVALID_EXPEDITION_NODE": "EXPEDITION_NODE_UNAVAILABLE",
		"INVALID_EXPEDITION_CHOICE": "EXPEDITION_CHOICE_INVALID",
		"EXPEDITION_SHOP_REFRESH_UNAVAILABLE": "EXPEDITION_SHOP_REFRESH_UNAVAILABLE",
		"EXPEDITION_ENCOUNTER_EXPIRED": "EXPEDITION_ENCOUNTER_EXPIRED",
		"EXPEDITION_RUN_NOT_FOUND": "EXPEDITION_RUN_NOT_FOUND",
		"COMBAT_ALREADY_ACTIVE": "EXPEDITION_COMBAT_ACTIVE",
		"FEATURE_DISABLED": "EXPEDITION_UNAVAILABLE",
	}.get(code, "EXPEDITION_ERROR_GENERIC"))


func _emit_combat_open() -> void:
	combat_open_changed.emit(is_combat_open())


func _on_back() -> void:
	handle_back()


static func _as_array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


static func _string_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	for item in _as_array(value):
		result.append(str(item))
	return result
