extends SceneTree

const CATALOG_PATH := "res://locales/ui.csv"
const REQUIRED_KEYS := [
	"NAV_HOME",
	"NAV_SCAN",
	"NAV_BATTLE",
	"NAV_COLLECTION",
	"NAV_ANIMA",
	"CORE_INFO_TITLE",
	"CORE_INFO_BODY",
	"CORE_INFO_CLOSE",
	"BITS_INFO_TITLE",
	"BITS_INFO_BODY",
	"SCAN_PRIMARY_ACTION",
	"CARE_FEED",
	"CARE_CLEAN",
	"CARE_SLEEP",
	"CARE_PLAY",
	"ERROR_PLAY_CAPPED",
	"HOME_LEVEL_EXP",
	"HOME_LEVEL_MAX",
	"LEVEL_UP",
	"LEVEL_UP_STATS_TITLE",
	"LEVEL_UP_STAT_ROW",
	"SCAN_NO_CORE_HINT",
	"SCAN_VIBE_TITLE",
	"STATUS_NEED_CORE",
	"BATTLE_ANIMA_HUNGRY",
	"BATTLE_HUNGRY_PENALTY",
	"BATTLE_DIRTY_PENALTY",
	"BATTLE_LOBBY_TITLE_HUNGRY",
	"BATTLE_CHOOSE_ANIMA",
	"BATTLE_PICK_HUNGRY",
	"BATTLE_PICK_LOW_ENERGY",
	"LEVEL_SHORT",
	"FORM_HATCHLING",
	"FORM_ADULT",
	"FORM_EVOLVED",
	"BATTLE_ACTION_STRIKE",
	"BATTLE_ACTION_SURGE",
	"BATTLE_ACTION_GUARD",
	"BATTLE_ACTION_ITEM",
	"SHOP_OPEN",
	"BAG_OPEN",
	"BATTLE_ERROR_GENERIC",
	"STATUS_GATE_REJECTED",
	"STATUS_VIBE_UNAVAILABLE",
	"GATE_HUMAN_FACE",
	"ELEMENT_FLOW",
	"ELEMENT_PAIR",
	"ELEMENT_WOOD",
	"ELEMENT_FAUNA",
	"ELEMENT_FLAME_HELP",
	"PHOTO_SOURCE_TITLE",
	"PHOTO_SOURCE_CAMERA",
	"FEEDBACK_WEEKLY_CORE",
	"UPDATE_REQUIRED_TITLE",
	"UPDATE_REQUIRED_BODY",
	"BATTLE_ATTACK_ELEMENT",
	"HOME_CARE_SUMMARY",
	"DETAILS_ELEMENT_HELP",
	"DETAILS_RARITY_HELP",
	"DETAILS_STAGE_HELP",
	"DETAILS_CARE_SCORE_HELP",
	"DETAILS_STRIKE_HELP",
	"DETAILS_SURGE_HELP",
	"STAT_HP_HELP",
	"STAT_ATK_HELP",
	"STAT_DEF_HELP",
	"STAT_SPD_HELP",
	"STAT_SPECIAL_HELP",
	"FORMAT_RATIO",
	"FORMAT_PERCENT",
	"VALUE_UNAVAILABLE",
	"EXPEDITION_NODE_UNKNOWN",
]
const GATE_REASON_CODES := [
	"human_face",
	"human_body",
	"unsafe_content",
	"personal_info",
	"too_unclear",
	"no_object",
	"animal_distress",
	"animal_abuse",
	"dangerous_situation",
	"known_character",
]
const PLAYER_UI_FILES := [
	"res://scripts/scan_flow.gd",
	"res://scripts/home_view.gd",
	"res://scripts/scan_view.gd",
	"res://scripts/collection_view.gd",
	"res://scripts/battle_view.gd",
	"res://scripts/team_battle_view.gd",
	"res://scripts/expedition_view.gd",
	"res://scripts/expedition_route_map.gd",
	"res://scripts/expedition_controller.gd",
	"res://scripts/anima_details_view.gd",
	"res://scripts/shop_sheet.gd",
	"res://scripts/battle_pick_sheet.gd",
	"res://scripts/element_catalog.gd",
	"res://scripts/client_version.gd",
	"res://scripts/photo_source_sheet.gd",
	"res://scenes/scan_flow.tscn",
	"res://scenes/ui/home_view.tscn",
	"res://scenes/ui/scan_view.tscn",
	"res://scenes/ui/collection_view.tscn",
	"res://scenes/ui/battle_view.tscn",
	"res://scenes/ui/team_battle_view.tscn",
	"res://scenes/ui/expedition_view.tscn",
	"res://scenes/ui/anima_details_view.tscn",
	"res://scenes/ui/shop_sheet.tscn",
	"res://scenes/ui/battle_pick_sheet.tscn",
	"res://scenes/ui/bottom_nav.tscn",
]

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	await process_frame
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	_check(file != null, "translation catalog must open")
	if file == null:
		_finish()
		return

	var header := file.get_csv_line()
	_check(header.size() == 2, "catalog must contain keys and English columns")
	_check(header[0] == "keys" and header[1] == "en", "English must be the source locale")

	var keys: Dictionary = {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty() or (row.size() == 1 and row[0].is_empty()):
			continue
		_check(row.size() == 2, "every catalog row must have one English value")
		if row.size() != 2:
			continue
		_check(not row[0].is_empty(), "translation keys cannot be empty")
		_check(not row[1].is_empty(), "%s must have English copy" % row[0])
		_check(not keys.has(row[0]), "%s must be unique" % row[0])
		keys[row[0]] = row[1]

	for key in REQUIRED_KEYS:
		_check(keys.has(key), "%s must exist" % key)
	for code in GATE_REASON_CODES:
		var key := "GATE_%s" % code.to_upper()
		_check(keys.has(key), "%s must exist for server gate code" % key)
	_check_referenced_keys(keys)

	var locale_manager := root.get_node("LocaleManager")
	_check(locale_manager != null, "LocaleManager autoload must exist")
	if locale_manager != null:
		locale_manager.call("set_locale", "en")
		_check(TranslationServer.translate("CARE_PLAY") == "Play", "English translation must resolve")
		_check(locale_manager.call("format_integer", 12345) == "12,345", "numbers use one formatter")
		_check(locale_manager.call("format_ratio", 3, 5) == "3 / 5", "ratios use one formatter")
		_check(
			locale_manager.call("move_name", {"strike_name": "Button Bash"}, "strike") == "Button Bash",
			"named Attack uses the generated move"
		)
		_check(
			locale_manager.call("move_name", {}, "surge") == TranslationServer.translate("BATTLE_ACTION_SURGE"),
			"unnamed Special falls back to the catalog"
		)
		for code in GATE_REASON_CODES:
			var key := "GATE_%s" % code.to_upper()
			_check(
				locale_manager.call("gate_reason", code) == TranslationServer.translate(key),
				"%s must map to its player copy" % code
			)
	_check_scene_copy(keys)
	_finish()


func _check_referenced_keys(keys: Dictionary) -> void:
	var pattern := RegEx.new()
	pattern.compile(
		"(?:tr\\(|set_loading\\(|text = |title = |ok_button_text = )"
		+ "\\s*\\\"([A-Z][A-Z0-9_]+)\\\""
	)
	var direct_text := RegEx.new()
	direct_text.compile("\\.text\\s*=\\s*\\\"")
	for path in PLAYER_UI_FILES:
		var source := FileAccess.get_file_as_string(path)
		_check(not source.is_empty(), "%s must be readable" % path)
		for result in pattern.search_all(source):
			var key := result.get_string(1)
			_check(keys.has(key), "%s referenced by %s must exist" % [key, path])
		if path.ends_with(".gd"):
			_check(direct_text.search(source) == null, "%s cannot assign raw UI copy" % path)


func _check_scene_copy(keys: Dictionary) -> void:
	var packed := load("res://scenes/scan_flow.tscn") as PackedScene
	_check(packed != null, "production scene must load for copy audit")
	if packed == null:
		return
	var scene := packed.instantiate()
	_check_node_copy(scene, keys)
	for name in [
		"Subtitle", "AnimaMeta", "ScanStatus", "ScanPhaseHint",
		"CollectionStatus", "DetailsEmpty", "DetailsMeta",
		"BattleSubtitle", "BattleLobbyMeta", "BattleResultBody",
		"LevelUpTitle", "LevelUpLabel",
	]:
		var label := scene.find_child(name, true, false) as Label
		if label != null:
			_check(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "%s must wrap long locales" % name)
	scene.free()


func _check_node_copy(node: Node, keys: Dictionary) -> void:
	if node is Label or node is Button:
		var copy := str(node.get("text"))
		if not copy.is_empty():
			_check(keys.has(copy), "%s uses catalog key %s" % [node.name, copy])
	if node is FileDialog:
		var dialog := node as FileDialog
		# FileDialog replaces its title from file_mode while off-tree; _ready()
		# restores the translated title. The source audit above proves its key.
		_check(
			keys.has(dialog.ok_button_text) or keys.values().has(dialog.ok_button_text),
			"FileDialog action comes from the catalog"
		)
	for child in node.get_children():
		_check_node_copy(child, keys)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_i18n: OK (%d checks)" % _checks)
		quit(0)
		return
	printerr("test_i18n: FAILED %d of %d checks" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - %s" % failure)
	quit(1)
