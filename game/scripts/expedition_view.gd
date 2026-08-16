class_name ExpeditionView
extends Control

signal back_requested
signal chapter_requested(chapter_version_id: String)
signal save_team_requested(anima_ids: Array[String])
signal start_run_requested(chapter_version_id: String, team_id: String)
signal start_zone_requested(run_id: String, team_id: String)
signal checkpoint_choice_requested(option_id: String)
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
const SHOP_SKIP_OPTION_ID := "shop-skip"
const BOSS_SEEKER_DIALOG := preload("res://scripts/boss_seeker_dialog.gd")
const BOSS_SEEKER_SHEET := preload("res://scripts/boss_seeker_sheet.gd")

@onready var _column: VBoxContainer = %ExpeditionColumn
@onready var _back: Button = %ExpeditionBack
@onready var _subtitle: Label = %Subtitle
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
@onready var _route_map: ExpeditionRouteMap = %ExpeditionRouteMap
@onready var _map_primary: Button = %ExpeditionMapPrimary
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
var _selected_route_node: Dictionary = {}
var _busy := false
var _thumbnail_provider: Callable
var _seeker_dialog: BOSS_SEEKER_DIALOG
var _chapter_intro_run := ""


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
	_map_primary.pressed.connect(_request_map_primary)
	_route_map.node_previewed.connect(_preview_route_node)
	_abandon.pressed.connect(abandon_requested.emit)
	_map_primary.focus_neighbor_bottom = _abandon.get_path()
	_abandon.focus_neighbor_top = _map_primary.get_path()
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
	_seeker_dialog = BOSS_SEEKER_DIALOG.new()
	_seeker_dialog.name = "ChapterSeekerDialog"
	add_child(_seeker_dialog)
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
	if is_instance_valid(_seeker_dialog) and _seeker_dialog.is_open():
		_seeker_dialog.dismiss()
		return true
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


func show_retreat_banner() -> void:
	_combat.show_retreat_banner()


func set_busy(busy: bool) -> void:
	_busy = busy
	_sync_back_chrome()
	_open_chapter.disabled = busy or _selected_version.is_empty()
	_catalog_team.disabled = busy
	_detail_team.disabled = busy
	_start_run.disabled = busy or _selected_version.is_empty() or _team_id().is_empty()
	_save_team.disabled = busy or _selected_roster_ids().size() != 4
	_sync_map_primary()
	_route_map.set_busy(busy)
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
		_complete_body.text = _completion_text()
		_show_only(_complete)
		return
	if not encounter.is_empty():
		_column.visible = false
		_combat.visible = true
		_combat.set_arena_location(_location_text(encounter))
		_combat.set_session(encounter, art_cache)
		_emit_combat_open()
		return
	_combat.set_arena_location("")
	_combat.visible = false
	_column.visible = true
	_emit_combat_open()
	if bool(_run.get("checkpoint_choice_pending", false)):
		_show_checkpoint_choice()
		return
	var pending := GameState.as_dict(_run.get("pending_node"))
	if not pending.is_empty() and not str(pending.get("kind", "")) in ["battle", "elite", "boss"]:
		_show_choice(pending)
		return
	_render_map()
	_show_only(_map)
	set_busy(false)
	_begin_chapter_intro(art_cache)


func combat_session_data() -> Dictionary:
	return _combat.session_data()


func begin_combat_action(action: String) -> void:
	_combat.begin_action(action)


func set_level_up_sequence_busy(busy: bool) -> void:
	_combat.set_result_continue_enabled(not busy)


func play_combat_events(
	events: Array,
	next_encounter: Dictionary,
	art_cache: Dictionary = {}
) -> void:
	await _combat.play_events(events, next_encounter, art_cache)


## Memasang encounter authoritative tanpa memutar ulang event-nya. Dipakai saat
## turn sudah dianimasikan dari simulasi lokal dan server setuju hasilnya.
func set_combat_encounter(encounter: Dictionary, art_cache: Dictionary = {}) -> void:
	_combat.set_session(encounter, art_cache)


func _show_only(panel: Control) -> void:
	_column.visible = true
	_combat.visible = false
	_emit_combat_open()
	for child in [_loading, _catalog, _detail, _builder, _map, _choice, _complete]:
		(child as Control).visible = child == panel
	_subtitle.visible = panel not in [_map, _choice]
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


func _request_map_primary() -> void:
	if _busy:
		return
	if str(_run.get("status", "")) == "checkpoint":
		if not _team_id().is_empty():
			start_zone_requested.emit(str(_run.get("id", "")), _team_id())
		return
	var node_id := str(_selected_route_node.get("id", ""))
	if not node_id.is_empty():
		enter_node_requested.emit(node_id)


func _render_map() -> void:
	_selected_route_node = {}
	var zone := int(_run.get("zone", 1))
	var daily := GameState.as_dict(_run.get("daily_bits"))
	var limit := int(daily.get("bits_limit", 0))
	_map_meta.text = (
		tr("EXPEDITION_MAP_STATUS_BITS") % [
			LocaleManager.format_integer(zone),
			LocaleManager.format_integer(int(_run.get("supplies", 0))),
			LocaleManager.format_integer(int(daily.get("bits_earned", 0))),
			LocaleManager.format_integer(limit),
		]
		if limit > 0 else tr("EXPEDITION_MAP_STATUS") % [
			LocaleManager.format_integer(zone),
			LocaleManager.format_integer(int(_run.get("supplies", 0))),
		]
	)
	var checkpoint := str(_run.get("status", "")) == "checkpoint"
	_route_map.visible = not checkpoint
	_map_primary.text = tr("EXPEDITION_START_ZONE" if checkpoint else "EXPEDITION_ENTER_NODE")
	if checkpoint:
		_route_map.clear_preview()
		_abandon.focus_neighbor_top = _map_primary.get_path()
		_party_meta.text = _checkpoint_text()
		_party_meta.visible = true
	else:
		_route_map.set_route(
			GameState.as_dict(_run.get("zone_map")),
			_string_array(_run.get("available_node_ids")),
			_string_array(_run.get("visited_node_ids"))
		)
		_wire_route_exit_focus()
		_party_meta.text = _injured_party_text(_as_array(_run.get("party_state")))
		# ponytail: keep one empty preview row mounted so selection cannot resize
		# the route. If localized copy needs multiple lines, move it to an overlay.
		_party_meta.visible = true
	_map_primary.visible = true
	_sync_map_primary()


func _preview_route_node(node: Dictionary) -> void:
	_selected_route_node = node.duplicate(true)
	_party_meta.text = _route_preview_text(node)
	_party_meta.visible = true
	_sync_map_primary()
	var selected := _route_map.node_button(str(node.get("id", "")))
	if selected != null:
		selected.focus_neighbor_bottom = _map_primary.get_path()
		_map_primary.focus_neighbor_top = selected.get_path()
	_abandon.focus_neighbor_top = _map_primary.get_path()


func _wire_route_exit_focus() -> void:
	var first: Button
	for node_id: String in _string_array(_run.get("available_node_ids")):
		var button := _route_map.node_button(node_id)
		if button == null:
			continue
		button.focus_neighbor_bottom = _abandon.get_path()
		if first == null:
			first = button
	if first != null:
		_abandon.focus_neighbor_top = first.get_path()


func _sync_map_primary() -> void:
	if not is_instance_valid(_map_primary):
		return
	var checkpoint := str(_run.get("status", "")) == "checkpoint"
	_map_primary.disabled = _busy or (
		(_team_id().is_empty() or bool(_run.get("checkpoint_choice_pending", false)))
		if checkpoint else _selected_route_node.is_empty()
	)


func _route_preview_text(node: Dictionary) -> String:
	var kind := str(node.get("kind", ""))
	var detail_key := str({
		"battle": "EXPEDITION_ROUTE_BATTLE_DETAIL",
		"elite": "EXPEDITION_ROUTE_ELITE_DETAIL",
		"recovery": "EXPEDITION_ROUTE_RECOVERY_DETAIL",
		"cache": "EXPEDITION_ROUTE_CACHE_DETAIL",
		"shop": "EXPEDITION_ROUTE_SHOP_DETAIL",
		"mystery": "EXPEDITION_ROUTE_MYSTERY_DETAIL",
		"boss": "EXPEDITION_ROUTE_BOSS_DETAIL",
	}.get(kind, "EXPEDITION_ROUTE_UNKNOWN_DETAIL"))
	return tr("EXPEDITION_ROUTE_PREVIEW") % [
		tr(_node_kind_key(kind)),
		tr(detail_key),
	]


func _checkpoint_text() -> String:
	var reward := GameState.as_dict(_run.get("last_zone_reward"))
	if reward.is_empty():
		return tr("EXPEDITION_CHECKPOINT_READY")
	return tr("EXPEDITION_TWO_LINES") % [
		tr("EXPEDITION_ZONE_REWARD") % [
			LocaleManager.format_integer(int(reward.get("zone", 0))),
			LocaleManager.format_integer(int(reward.get("bits", 0))),
		],
		tr("EXPEDITION_CHECKPOINT_READY"),
	]


func _completion_text() -> String:
	var reward := GameState.as_dict(_run.get("last_zone_reward"))
	if reward.is_empty():
		return tr("EXPEDITION_COMPLETE_BODY")
	return tr("EXPEDITION_TWO_LINES") % [
		tr("EXPEDITION_COMPLETE_BODY"),
		tr("EXPEDITION_ZONE_REWARD") % [
			LocaleManager.format_integer(int(reward.get("zone", 0))),
			LocaleManager.format_integer(int(reward.get("bits", 0))),
		],
	]


func _show_checkpoint_choice() -> void:
	_choice_title.text = tr("EXPEDITION_CHECKPOINT_CHOICE_TITLE")
	var reward := GameState.as_dict(_run.get("last_zone_reward"))
	var reward_text := ""
	if not reward.is_empty():
		reward_text = tr("EXPEDITION_ZONE_REWARD") % [
			LocaleManager.format_integer(int(reward.get("zone", 0))),
			LocaleManager.format_integer(int(reward.get("bits", 0))),
		]
	var hp_text := _injured_party_text(_as_array(_run.get("party_state")))
	_choice_meta.text = (
		tr("EXPEDITION_TWO_LINES") % [reward_text, hp_text]
		if not reward_text.is_empty() and not hp_text.is_empty()
		else (reward_text if not reward_text.is_empty() else hp_text)
	)
	_choice_meta.visible = not _choice_meta.text.is_empty()
	for child in _choice_buttons.get_children():
		child.free()
	for option_id: String in ["recover", "power_up"]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 96)
		button.theme_type_variation = &"PrimaryButton"
		button.text = tr(
			"EXPEDITION_CHECKPOINT_RECOVER"
			if option_id == "recover" else "EXPEDITION_CHECKPOINT_POWER_UP"
		)
		button.pressed.connect(checkpoint_choice_requested.emit.bind(option_id))
		_choice_buttons.add_child(button)
	_target_list.visible = false
	_target_confirm.visible = false
	_pending_option = {}
	_refresh_shop.visible = false
	_show_only(_choice)
	set_busy(false)


func _show_choice(node: Dictionary) -> void:
	var shop := str(node.get("kind", "")) == "shop"
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
	if shop:
		var skip_button := Button.new()
		skip_button.custom_minimum_size = Vector2(0, 96)
		skip_button.text = tr("EXPEDITION_SKIP_SHOP")
		skip_button.pressed.connect(
			choice_requested.emit.bind(SHOP_SKIP_OPTION_ID, -1)
		)
		_choice_buttons.add_child(skip_button)
	_choice_meta.visible = not _choice_meta.text.is_empty()
	_target_list.visible = false
	_target_confirm.visible = false
	_pending_option = {}
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


func _location_text(encounter: Dictionary = {}) -> String:
	if str(encounter.get("kind", "")) == "boss":
		var seeker := GameState.as_dict(encounter.get("boss_seeker"))
		if seeker.is_empty():
			seeker = GameState.as_dict(_run.get("boss_seeker"))
		var seeker_name := str(seeker.get("display_name", "")).strip_edges()
		if seeker_name.is_empty():
			seeker_name = tr("EXPEDITION_CHAPTER")
		return tr("EXPEDITION_ARENA_BOSS") % seeker_name
	return tr("EXPEDITION_ARENA_LOCATION") % [
		_chapter_title(),
		LocaleManager.format_integer(int(_run.get("zone", 1))),
	]


func _chapter_title() -> String:
	var title := str(
		GameState.as_dict(GameState.as_dict(_chapter.get("manifest")).get("summary")).get("title", "")
	).strip_edges()
	if title.is_empty():
		title = str(GameState.as_dict(_chapter.get("summary")).get("title", "")).strip_edges()
	if not title.is_empty():
		return title
	var version_id := str(_run.get("chapter_version_id", _selected_version))
	for value in _chapters:
		var chapter := GameState.as_dict(value)
		if (
			str(chapter.get("version_id", "")) != version_id
			and str(chapter.get("id", "")) != version_id
		):
			continue
		title = str(GameState.as_dict(chapter.get("summary")).get("title", "")).strip_edges()
		if title.is_empty():
			title = str(
				GameState.as_dict(GameState.as_dict(chapter.get("manifest")).get("summary")).get(
					"title", ""
				)
			).strip_edges()
		if title.is_empty():
			title = str(chapter.get("slug", "")).strip_edges()
		if not title.is_empty():
			return title
	return tr("EXPEDITION_CHAPTER")


func _injured_party_text(party: Array) -> String:
	var current_hp := 0
	var maximum_hp := 0
	var hurt_members := 0
	for value in party:
		var member := GameState.as_dict(value)
		var maximum := maxi(1, int(member.get("max_hp", 1)))
		var current := clampi(int(member.get("hp", 0)), 0, maximum)
		current_hp += current
		maximum_hp += maximum
		if current < maximum:
			hurt_members += 1
	if hurt_members == 0 or maximum_hp == 0:
		return ""
	return tr("EXPEDITION_TEAM_HP_STATUS") % [
		LocaleManager.format_percent(float(current_hp) / float(maximum_hp) * 100.0),
		LocaleManager.format_integer(hurt_members),
	]


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
		"INVALID_EXPEDITION_CHECKPOINT_CHOICE": "EXPEDITION_CHECKPOINT_CHOICE_INVALID",
		"EXPEDITION_CHECKPOINT_CHOICE_REQUIRED": "EXPEDITION_CHECKPOINT_CHOICE_REQUIRED",
		"EXPEDITION_CHECKPOINT_CHOICE_UNAVAILABLE": "EXPEDITION_CHECKPOINT_CHOICE_INVALID",
		"EXPEDITION_SHOP_REFRESH_UNAVAILABLE": "EXPEDITION_SHOP_REFRESH_UNAVAILABLE",
		"EXPEDITION_ENCOUNTER_EXPIRED": "EXPEDITION_ENCOUNTER_EXPIRED",
		"EXPEDITION_RUN_NOT_FOUND": "EXPEDITION_RUN_NOT_FOUND",
		"COMBAT_ALREADY_ACTIVE": "EXPEDITION_COMBAT_ACTIVE",
		"FEATURE_DISABLED": "EXPEDITION_UNAVAILABLE",
	}.get(code, "EXPEDITION_ERROR_GENERIC"))


func _begin_chapter_intro(art_cache: Dictionary) -> void:
	if not _should_chapter_intro():
		return
	var seeker := GameState.as_dict(_run.get("boss_seeker"))
	var line := str(GameState.as_dict(seeker.get("dialogue")).get("chapter_intro", "")).strip_edges()
	if line.is_empty() or not is_instance_valid(_seeker_dialog):
		return
	_chapter_intro_run = str(_run.get("id", ""))
	set_busy(true)
	await _seeker_dialog.present(
		str(seeker.get("display_name", "")),
		line,
		BOSS_SEEKER_SHEET.portrait(
			GameState.as_dict(art_cache.get("boss_seeker")),
			str(seeker.get("portrait_pose", "profile"))
		)
	)
	set_busy(false)


func _should_chapter_intro() -> bool:
	var run_id := str(_run.get("id", ""))
	if run_id.is_empty() or run_id == _chapter_intro_run:
		return false
	if int(_run.get("zone", 1)) != 1 or int(_run.get("nodes_completed", 0)) > 0:
		return false
	if not str(_run.get("current_node_id", "")).is_empty():
		return false
	var line := str(
		GameState.as_dict(GameState.as_dict(_run.get("boss_seeker")).get("dialogue")).get(
			"chapter_intro",
			""
		)
	).strip_edges()
	return not line.is_empty()


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
