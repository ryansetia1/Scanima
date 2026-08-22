class_name AnimaDetailsView
extends Control

signal delete_requested(anima_id: String)
signal rename_requested(anima_id: String)
signal gallery_publish_requested(anima_id: String, publish: bool)
signal evolve_requested(row: Dictionary)
signal synthesis_requested(row: Dictionary)
signal help_requested(title: String, body: String)

## Cermin `_validated_anima_name()` di Postgres. Preflight ini hanya menghemat
## satu round trip; database tetap pagar terakhirnya, dan daftar impersonasi
## sengaja tidak ikut turun ke client — ia berubah tanpa build baru.
const NAME_PATTERN := "^[A-Za-z0-9][A-Za-z0-9 '-]{0,31}$"
const NAME_MAX_LENGTH := 32
const HISTORY_SKELETON_ART_PX := 112.0
const PROFILE_MENU_MARGIN := 16.0
const PROFILE_MENU_GAP := 8.0
const PROFILE_MENU_ICON: Texture2D = preload("res://assets/icons/more-vertical.svg")

@onready var _empty_state: Label = %DetailsEmpty
@onready var _details_scroll: ScrollContainer = $Column/DetailsScroll
@onready var _content: Control = %DetailsContent
@onready var _portrait: TextureRect = %DetailsPortrait
@onready var _name: Label = %DetailsName
@onready var _meta: Label = %DetailsMeta
@onready var _trait_element: Label = %TraitElement
@onready var _trait_rarity: Label = %TraitRarity
@onready var _trait_stage: Label = %TraitStage
@onready var _trait_exp: Label = %TraitExp
@onready var _trait_strike: Label = %TraitStrike
@onready var _trait_surge: Label = %TraitSurge
@onready var _stat_hp: Label = %StatHp
@onready var _stat_atk: Label = %StatAtk
@onready var _stat_def: Label = %StatDef
@onready var _stat_spd: Label = %StatSpd
@onready var _stat_special: Label = %StatSpecial
@onready var _about_help: Button = %AboutHelp
@onready var _combat_help: Button = %CombatHelp
@onready var _menu_button: Button = %ProfileMenuButton
@onready var _action_popover: Control = %ProfileActionPopover
@onready var _action_backdrop: Button = %ProfileActionBackdrop
@onready var _action_panel: PanelContainer = %ProfileActionPanel
@onready var _action_rename: Button = %ProfileActionRename
@onready var _action_delete: Button = %ProfileActionDelete
@onready var _primary_actions: HBoxContainer = %PrimaryActions
@onready var _gallery_button: Button = %GalleryPublishButton
@onready var _evolve_button: Button = %EvolveAnimaButton
@onready var _evolution_status: Label = %EvolutionStatusLabel
@onready var _synthesis_button: Button = %SynthesisAnimaButton
@onready var _synthesis_history: Control = %SynthesisHistoryPanel
@onready var _history_title: Label = %SynthesisHistoryTitle
@onready var _history_source_a: TextureRect = %SynthesisHistorySourceA
@onready var _history_source_a_label: Label = %SynthesisHistorySourceALabel
@onready var _history_source_b: TextureRect = %SynthesisHistorySourceB
@onready var _history_source_b_label: Label = %SynthesisHistorySourceBLabel
@onready var _history_mode: Label = %SynthesisHistoryMode
@onready var _history_help: Button = %SynthesisHistoryHelp
@onready var _history_summary: Label = %SynthesisHistorySummary

var _anima_id := ""
var _element_code := ""
var _row: Dictionary = {}
var _busy := false
var _gallery_published := false
var _gallery_available := false
var _evolution_enabled := false
var _synthesis_enabled := false
var _synthesis_history_textures: Dictionary = {}
var _history_source_names: Dictionary = {}
var _history_source_a_skeleton: UiSkeleton
var _history_source_b_skeleton: UiSkeleton
var _layout_refresh_queued := false


func _ready() -> void:
	_menu_button.icon = PROFILE_MENU_ICON
	_menu_button.pressed.connect(_toggle_action_menu)
	_action_backdrop.pressed.connect(close_action_menu)
	_action_rename.pressed.connect(_request_rename)
	_action_delete.pressed.connect(_request_delete)
	_action_popover.resized.connect(_position_action_menu)
	_gallery_button.pressed.connect(_request_gallery_toggle)
	_evolve_button.pressed.connect(_request_evolve)
	_synthesis_button.pressed.connect(_request_synthesis)
	_about_help.pressed.connect(_show_about_help)
	_combat_help.pressed.connect(_show_combat_help)
	_history_help.pressed.connect(_show_history_help)
	visibility_changed.connect(_queue_layout_refresh)
	resized.connect(_queue_layout_refresh)
	UiJuice.install_button(_history_help)
	UiJuice.install_button(_menu_button)
	UiJuice.install_button(_action_rename)
	UiJuice.install_button(_action_delete)
	_action_delete.add_theme_color_override("font_color", Color("ff667d"))
	_action_delete.add_theme_color_override("font_hover_color", Color("ff8fa0"))
	_action_delete.add_theme_color_override("font_pressed_color", Color("ff8fa0"))
	_history_source_a_skeleton = _build_history_art_skeleton(
		_history_source_a, "SynthesisHistorySourceASkeleton"
	)
	_history_source_b_skeleton = _build_history_art_skeleton(
		_history_source_b, "SynthesisHistorySourceBSkeleton"
	)
	refresh_localized_ui()
	_queue_layout_refresh()


func set_anima(row: Dictionary, portrait: Texture2D) -> void:
	var next_id := str(row.get("id", ""))
	if next_id != _anima_id:
		_synthesis_history_textures.clear()
		_details_scroll.scroll_vertical = 0
		close_action_menu(false)
	_row = row.duplicate(true) if not row.is_empty() else {}
	if row.is_empty():
		_anima_id = ""
		_element_code = ""
		_empty_state.visible = true
		_content.visible = false
		_menu_button.disabled = true
		_action_rename.disabled = true
		_action_delete.disabled = true
		_gallery_button.disabled = true
		_evolve_button.visible = false
		_evolution_status.visible = false
		_synthesis_button.visible = false
		_synthesis_history.visible = false
		set_synthesis_history_loading(false)
		_queue_layout_refresh()
		return

	_anima_id = str(row.get("id", ""))
	_element_code = str(row.get("element", ""))
	_empty_state.visible = false
	_content.visible = true
	var evolving := CareRules.is_evolving(row)
	var actions_disabled := _busy or _anima_id.is_empty() or evolving
	_menu_button.disabled = actions_disabled
	_action_rename.disabled = actions_disabled
	_action_delete.disabled = actions_disabled
	_gallery_button.disabled = actions_disabled or not _gallery_available
	if actions_disabled:
		close_action_menu(false)
	_portrait.texture = portrait
	_name.text = LocaleManager.display_name(row)
	var level := CareRules.level_from_exp(int(row.get("care_score", 0)))
	_meta.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(level),
		LocaleManager.element_compact(row),
	]
	_trait_element.text = LocaleManager.element_compact(row)
	_trait_rarity.text = LocaleManager.format_ratio(int(row.get("rarity", 1)), 5)
	_trait_stage.text = tr("HOME_IDENTITY_META") % [
		LocaleManager.level_label(level),
		LocaleManager.form_name_for_row(row),
	]
	_trait_exp.text = LocaleManager.format_integer(int(row.get("care_score", 0)))
	_trait_strike.text = _move_line(row, "strike")
	_trait_surge.text = _move_line(row, "surge")

	var stats := GameState.as_dict(row.get("base_stats"))
	_stat_hp.text = _stat_for_row(stats, "hp", row)
	_stat_atk.text = _stat_for_row(stats, "atk", row)
	_stat_def.text = _stat_for_row(stats, "def", row)
	_stat_spd.text = _stat_for_row(stats, "spd", row)
	_stat_special.text = _stat_for_row(stats, "special", row)
	_apply_evolution_ui(row)
	_apply_synthesis_ui(row)
	_apply_synthesis_history(
		GameState.as_dict(row.get("synthesis_history")),
		_synthesis_history_textures
	)
	_queue_layout_refresh()


func set_busy(busy: bool) -> void:
	_busy = busy
	var evolving := CareRules.is_evolving(_row)
	var actions_disabled := _busy or _anima_id.is_empty() or evolving
	_menu_button.disabled = actions_disabled
	_action_rename.disabled = actions_disabled
	_action_delete.disabled = actions_disabled
	_gallery_button.disabled = actions_disabled or not _gallery_available
	if actions_disabled:
		close_action_menu(false)
	if not _row.is_empty():
		_apply_evolution_ui(_row)
		_apply_synthesis_ui(_row)


func set_evolution_enabled(enabled: bool) -> void:
	_evolution_enabled = enabled
	if not _row.is_empty():
		_apply_evolution_ui(_row)


func set_synthesis_enabled(enabled: bool) -> void:
	_synthesis_enabled = enabled
	if not _row.is_empty():
		_apply_synthesis_ui(_row)


func set_history_source_names(names: Dictionary) -> void:
	_history_source_names = names.duplicate()


func set_synthesis_history(history: Dictionary, textures: Dictionary = {}) -> void:
	if _row.is_empty():
		return
	if not textures.is_empty():
		_synthesis_history_textures = textures.duplicate()
	_apply_synthesis_history(history, _synthesis_history_textures)


func set_synthesis_history_loading(loading: bool) -> void:
	_history_source_a_skeleton.set_loading(loading and _history_source_a.texture == null)
	_history_source_b_skeleton.set_loading(loading and _history_source_b.texture == null)


func set_gallery_status(status: Dictionary) -> void:
	_gallery_available = bool(status.get("available", false))
	_gallery_published = bool(status.get("published", false))
	_gallery_button.visible = _gallery_available
	if _gallery_available:
		_gallery_button.text = (
			tr("GALLERY_UNPUBLISH") if _gallery_published else tr("GALLERY_PUBLISH")
		)
		_gallery_button.disabled = (
			_busy or _anima_id.is_empty() or CareRules.is_evolving(_row)
		)
	_update_primary_actions_visibility()


func _apply_synthesis_ui(row: Dictionary) -> void:
	var eligible := SynthesisLabView.is_eligible_source(row)
	_synthesis_button.visible = _synthesis_enabled
	# `_busy` hanya menunda tap, bukan menolak Anima-nya, jadi tooltip alasan
	# ketidaklayakan cuma dipasang kalau Anima ini memang tidak memenuhi syarat.
	_synthesis_button.disabled = _busy or not eligible
	_synthesis_button.tooltip_text = (
		tr("SYNTHESIS_USE_SOURCE_ACTION") if eligible else tr("SYNTHESIS_SOURCE_INELIGIBLE")
	)
	_update_primary_actions_visibility()


func _update_primary_actions_visibility() -> void:
	_primary_actions.visible = _synthesis_button.visible or _gallery_button.visible
	_queue_layout_refresh()


func _apply_synthesis_history(history: Dictionary, textures: Dictionary) -> void:
	_synthesis_history.visible = not history.is_empty()
	if history.is_empty():
		_queue_layout_refresh()
		return
	var source_a := GameState.as_dict(history.get("source_a"))
	var source_b := GameState.as_dict(history.get("source_b"))
	_history_source_a.texture = textures.get("source_a") as Texture2D
	_history_source_b.texture = textures.get("source_b") as Texture2D
	_history_source_a_label.text = tr("SYNTHESIS_HISTORY_SOURCE") % [
		_history_source_name(source_a),
		tr(_form_key(int(source_a.get("selected_stage", 1)))),
	]
	_history_source_b_label.text = tr("SYNTHESIS_HISTORY_SOURCE") % [
		_history_source_name(source_b),
		tr(_form_key(int(source_b.get("selected_stage", 1)))),
	]
	_history_mode.text = tr("SYNTHESIS_HISTORY_MODE") % [
		tr(_mode_key(str(history.get("mode", "balanced")))),
		LocaleManager.format_integer(int(history.get("resonance", 0))),
	]
	var summary := GameState.as_dict(history.get("inheritance_summary"))
	var note_a := str(summary.get("source_a", "")).strip_edges()
	var note_b := str(summary.get("source_b", "")).strip_edges()
	var note_c := str(summary.get("coherence", "")).strip_edges()
	_history_summary.text = tr("SYNTHESIS_HISTORY_SUMMARY") % [note_a, note_b, note_c]
	_history_summary.visible = false
	_history_help.visible = not (note_a.is_empty() and note_b.is_empty() and note_c.is_empty())
	_queue_layout_refresh()


## Root skeleton tetap memenuhi slot 150 px agar layout tidak meloncat, tetapi
## tinta loading-nya hanya satu squircle 112 px di tengah. Mengisi seluruh lebar
## kolom membuat dua placeholder terbaca sebagai banner kosong, bukan art yang
## sedang dimuat.
func _build_history_art_skeleton(parent: TextureRect, node_name: String) -> UiSkeleton:
	var skeleton := UiSkeleton.new()
	skeleton.name = node_name
	skeleton.visible = false
	skeleton.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(skeleton)
	skeleton.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skeleton.add_child(center)
	var placeholder := PanelContainer.new()
	placeholder.name = node_name.replace("Skeleton", "Placeholder")
	placeholder.custom_minimum_size = Vector2(
		HISTORY_SKELETON_ART_PX, HISTORY_SKELETON_ART_PX
	)
	placeholder.theme_type_variation = &"StatValuePanel"
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(placeholder)
	return skeleton


func _apply_evolution_ui(row: Dictionary) -> void:
	var evolving := CareRules.is_evolving(row)
	var evolution_ready := _evolution_enabled and CareRules.evolution_ready(row)
	var stage3 := CareRules.committed_stage(row) >= 3
	_evolve_button.visible = evolution_ready and not stage3 and not evolving
	_evolve_button.disabled = _busy or not evolution_ready
	_evolution_status.visible = evolving
	if evolving:
		_evolution_status.text = tr("EVOLUTION_CHAMBER_STATUS")
	elif evolution_ready and not stage3:
		_evolve_button.text = tr("EVOLVE_ACTION")
	_queue_layout_refresh()


## View yang di-instance tersembunyi dapat kehilangan notifikasi sort pertama.
## Tanpa refresh sinkron, ScrollContainer tetap setinggi 0 sampai perubahan layout
## lain kebetulan terjadi, sehingga gesture yang sama terasa acak.
func _queue_layout_refresh() -> void:
	if _layout_refresh_queued:
		return
	_layout_refresh_queued = true
	_refresh_layout.call_deferred()


func _refresh_layout() -> void:
	_layout_refresh_queued = false
	if not is_visible_in_tree():
		return
	_sort_container_tree(self)


func _sort_container_tree(node: Node) -> void:
	if node is Container:
		(node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children():
		_sort_container_tree(child)


func _move_line(row: Dictionary, action: String) -> String:
	var move := LocaleManager.move_name(row, action)
	if CareRules.evolution_version(row) < 1:
		return move
	var effect_id := str(
		row.get("surge_effect_id" if action == "surge" else "strike_effect_id", "")
	).strip_edges()
	if effect_id.is_empty():
		return move
	return tr("DETAILS_MOVE_EFFECT") % [move, LocaleManager.effect_name(effect_id)]


func _request_evolve() -> void:
	if _row.is_empty() or not CareRules.evolution_ready(_row):
		return
	evolve_requested.emit(_row.duplicate(true))


func _request_synthesis() -> void:
	if not _synthesis_button.disabled and not _row.is_empty():
		synthesis_requested.emit(_row.duplicate(true))


static func _form_key(stage: int) -> String:
	return SynthesisLabView._form_key(stage)


static func _mode_key(mode: String) -> String:
	match mode:
		"dominant_a":
			return "SYNTHESIS_MODE_DOMINANT_A"
		"dominant_b":
			return "SYNTHESIS_MODE_DOMINANT_B"
		_:
			return "SYNTHESIS_MODE_BALANCED"


static func is_valid_anima_name(value: String) -> bool:
	var name := value.strip_edges()
	return (
		RegEx.create_from_string(NAME_PATTERN).search(name) != null
		and RegEx.create_from_string("[A-Za-z]").search(name) != null
		and not name.contains("  ")
	)


func is_action_menu_open() -> bool:
	return _action_popover.visible


func close_action_menu(restore_focus: bool = true) -> void:
	if not _action_popover.visible:
		return
	_action_popover.visible = false
	if restore_focus and _menu_button.is_visible_in_tree() and not _menu_button.disabled:
		_menu_button.grab_focus()


func _toggle_action_menu() -> void:
	if _menu_button.disabled:
		return
	if _action_popover.visible:
		close_action_menu()
		return
	_action_popover.visible = true
	_position_action_menu()
	_focus_action_menu.call_deferred()


func _position_action_menu() -> void:
	if not _action_popover.visible:
		return
	var anchor_rect := _menu_button.get_global_rect()
	var to_local := _action_popover.get_global_transform_with_canvas().affine_inverse()
	var anchor_position := to_local * anchor_rect.position
	var anchor_end := to_local * anchor_rect.end
	var anchor_size := anchor_end - anchor_position
	var panel_size := _action_panel.get_combined_minimum_size()
	var below_y := anchor_position.y + anchor_size.y + PROFILE_MENU_GAP
	var above_y := anchor_position.y - panel_size.y - PROFILE_MENU_GAP
	var max_x := maxf(PROFILE_MENU_MARGIN, _action_popover.size.x - panel_size.x - PROFILE_MENU_MARGIN)
	var max_y := maxf(PROFILE_MENU_MARGIN, _action_popover.size.y - panel_size.y - PROFILE_MENU_MARGIN)
	var panel_x := clampf(
		anchor_position.x + anchor_size.x - panel_size.x,
		PROFILE_MENU_MARGIN,
		max_x
	)
	var panel_y := below_y if below_y <= max_y else maxf(PROFILE_MENU_MARGIN, above_y)
	_action_panel.position = Vector2(panel_x, panel_y)
	_action_panel.size = panel_size


func _focus_action_menu() -> void:
	if _action_popover.visible and not _action_rename.disabled:
		_action_rename.grab_focus()


func _request_rename() -> void:
	close_action_menu(false)
	if not _anima_id.is_empty():
		rename_requested.emit(_anima_id)


func _request_gallery_toggle() -> void:
	if _anima_id.is_empty():
		return
	gallery_publish_requested.emit(_anima_id, not _gallery_published)


func _request_delete() -> void:
	close_action_menu(false)
	if not _anima_id.is_empty():
		delete_requested.emit(_anima_id)


func refresh_localized_ui() -> void:
	_about_help.tooltip_text = tr("DETAILS_TRAITS")
	_combat_help.tooltip_text = tr("DETAILS_ATTRIBUTES")
	_menu_button.tooltip_text = tr("ANIMA_PROFILE_MENU")
	_action_rename.text = tr("ANIMA_RENAME_ACTION")
	_action_delete.text = tr("ANIMA_DELETE_ACTION")
	_evolve_button.text = tr("EVOLVE_ACTION")
	_synthesis_button.text = tr("SYNTHESIS_USE_SOURCE_ACTION")
	_history_title.text = tr("SYNTHESIS_HISTORY_TITLE")
	_history_help.tooltip_text = tr("SYNTHESIS_HISTORY_HELP")
	if not _row.is_empty():
		set_anima(_row, _portrait.texture)


func _show_about_help() -> void:
	help_requested.emit(
		tr("DETAILS_TRAITS"),
		"\n\n".join([
			"%s — %s" % [tr("DETAILS_ELEMENT"), ElementCatalog.help_text(_element_code)],
			"%s — %s" % [tr("DETAILS_RARITY"), tr("DETAILS_RARITY_HELP")],
			"%s — %s" % [tr("DETAILS_STAGE"), tr("DETAILS_STAGE_HELP")],
			"%s — %s" % [tr("DETAILS_CARE_SCORE"), tr("DETAILS_CARE_SCORE_HELP")],
			"%s — %s" % [tr("DETAILS_STRIKE"), tr("DETAILS_STRIKE_HELP")],
			"%s — %s" % [tr("DETAILS_SURGE"), tr("DETAILS_SURGE_HELP")],
		])
	)


func _show_history_help() -> void:
	if _history_summary.text.strip_edges().is_empty():
		return
	help_requested.emit(tr("SYNTHESIS_HISTORY_TITLE"), _history_summary.text)


func _history_source_name(source: Dictionary) -> String:
	var raw := str(source.get("name", "")).strip_edges()
	var fallback := tr("ANIMA_FALLBACK_NAME")
	if not raw.is_empty() and raw != fallback:
		return raw
	var resolved := str(_history_source_names.get(str(source.get("id", "")), "")).strip_edges()
	if not resolved.is_empty():
		return resolved
	return raw if not raw.is_empty() else fallback


func _show_combat_help() -> void:
	help_requested.emit(
		tr("DETAILS_ATTRIBUTES"),
		"\n\n".join([
			"%s — %s" % [tr("STAT_HP"), tr("STAT_HP_HELP")],
			"%s — %s" % [tr("STAT_ATK"), tr("STAT_ATK_HELP")],
			"%s — %s" % [tr("STAT_DEF"), tr("STAT_DEF_HELP")],
			"%s — %s" % [tr("STAT_SPD"), tr("STAT_SPD_HELP")],
			"%s — %s" % [tr("STAT_SPECIAL"), tr("STAT_SPECIAL_HELP")],
		])
	)


func _stat_for_row(stats: Dictionary, key: String, row: Dictionary) -> String:
	return (
		LocaleManager.format_integer(CareRules.grown_stat_for_row(stats[key], row))
		if stats.has(key)
		else tr("VALUE_UNAVAILABLE")
	)
