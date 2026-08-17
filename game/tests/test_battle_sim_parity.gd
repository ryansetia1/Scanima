extends SceneTree

## Paritas simulasi lokal terhadap resolver server. Vektornya digenerasi dari
## `.mjs` produksi, jadi yang diuji adalah kecocokan dengan sumber kebenaran,
## bukan dengan tebakan port-nya.
##
##   node backend/tools/emit_sim_vectors.mjs --out /tmp/scanima_sim_vectors.json
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##     --script res://tests/test_battle_sim_parity.gd \
##     -- --vectors=/tmp/scanima_sim_vectors.json

const DEFAULT_VECTORS := "/tmp/scanima_sim_vectors.json"

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	var path := DEFAULT_VECTORS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vectors="):
			path = arg.substr("--vectors=".length())
	if not FileAccess.file_exists(path):
		printerr("test_battle_sim_parity: vektor tidak ada di %s" % path)
		printerr("  jalankan: node backend/tools/emit_sim_vectors.mjs --out %s" % path)
		quit(1)
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("test_battle_sim_parity: vektor tidak bisa dibaca sebagai JSON")
		quit(1)
		return
	var vectors: Dictionary = parsed
	var catalog := BattleSim.index_catalog(vectors.get("catalog", []))

	print("1. PRNG splitmix32 identik dengan runtime Deno")
	_check_eq(
		int(vectors.get("rules_version", 0)),
		BattleSim.RULES_VERSION,
		"rules_version client harus sama dengan server"
	)
	for value in vectors.get("rng", []):
		var case: Dictionary = value
		var seed_text := str(case["seed"])
		var rng := DeterministicRng.new(seed_text)
		var floats: Array = []
		var uints: Array = []
		for _i in (case["floats"] as Array).size():
			var raw := rng.next_uint32()
			uints.append(raw)
			floats.append(float(raw) / 4294967296.0)
		_diff_check(uints, case["uints"], "rng[%s].uints" % seed_text)
		_diff_check(floats, case["floats"], "rng[%s].floats" % seed_text)

	print("2. stat, care multiplier, EXP, dan elemen")
	var scalars: Dictionary = vectors.get("scalars", {})
	for value in scalars.get("to_battle_stats", []):
		var case: Dictionary = value
		_diff_check(
			BattleSim.to_battle_stats(case["base_stats"], case["level"]),
			case["stats"],
			"to_battle_stats(level=%s)" % str(case["level"])
		)
	for value in scalars.get("care_multiplier", []):
		var case: Dictionary = value
		_diff_check(
			BattleSim.care_combat_multiplier(case["hunger"], case["hygiene"]),
			case["value"],
			"care_combat_multiplier(%s, %s)" % [str(case["hunger"]), str(case["hygiene"])]
		)
	for value in scalars.get("crit_chance", []):
		var case: Dictionary = value
		_diff_check(
			BattleSim.crit_chance(case["spd"]), case["value"], "crit_chance(%s)" % str(case["spd"])
		)
	for value in scalars.get("exp_yield", []):
		var case: Dictionary = value
		_diff_check(
			BattleSim.battle_exp_yield(
				int(case["recipient"]), int(case["opponent"]), str(case["difficulty"])
			),
			case["value"],
			"battle_exp_yield(%s)" % str(case["difficulty"])
		)
	for value in scalars.get("element_normalize", []):
		var case: Dictionary = value
		_diff_check(
			ElementRules.normalize(case["input"]),
			case["with_stone"],
			"normalize(%s)" % str(case["input"])
		)
		_diff_check(
			ElementRules.normalize(case["input"], ""),
			case["with_empty"],
			"normalize(%s, \"\")" % str(case["input"])
		)
	for value in scalars.get("element_matchup", []):
		var case: Dictionary = value
		_diff_check(
			ElementRules.dual_defender_multiplier(
				case["attacker"], case["primary"], case["secondary"]
			),
			case["value"],
			"dual_defender_multiplier(%s)" % str(case["attacker"])
		)

	print("3. createFighter memetakan input yang bolong dan care null")
	var inputs: Dictionary = scalars.get("fighter_inputs", {})
	var fighters: Dictionary = scalars.get("fighters", {})
	_check(inputs.size() == fighters.size(), "setiap fighter yang diuji harus punya input-nya")
	for key in fighters:
		_diff_check(
			BattleSim.create_fighter(inputs.get(key, {})),
			fighters[key],
			"create_fighter(%s)" % str(key)
		)

	print("4. resolveTurn Duel turn demi turn")
	var duel_turns := 0
	for value in vectors.get("duel", []):
		var case: Dictionary = value
		var label := "%s(rules=%s)" % [str(case["name"]), str(case["rules_version"])]
		var state: Dictionary = (case["initial"] as Dictionary).duplicate(true)
		for index in (case["steps"] as Array).size():
			var step: Dictionary = case["steps"][index]
			var outcome := BattleSim.resolve_turn(
				state,
				str(step["action"]),
				str(step["key"]),
				str(step.get("item_id", "")),
				catalog
			)
			var expected_error := str(step.get("error", ""))
			if not expected_error.is_empty():
				_check_eq(
					str(outcome["error"]),
					expected_error,
					"%s turn %d harus gagal dengan kode yang sama" % [label, index]
				)
				break
			if not bool(outcome["ok"]):
				_check(false, "%s turn %d gagal tak terduga: %s" % [label, index, outcome["error"]])
				break
			if step.has("turn_seed"):
				_diff_check(
					BattleSim.turn_seed(state, str(step["key"])),
					step["turn_seed"],
					"%s turn %d seed" % [label, index]
				)
			_diff_check(outcome["events"], step["events"], "%s turn %d events" % [label, index])
			_diff_check(outcome["state"], step["state"], "%s turn %d state" % [label, index])
			_diff_check(
				outcome["bot_action"], step["bot_action"], "%s turn %d bot_action" % [label, index]
			)
			state = outcome["state"]
			duel_turns += 1
	_check(duel_turns >= 40, "vektor Duel harus mencakup banyak turn, dapat %d" % duel_turns)

	print("5. resolveTeamTurn party, switch, forced switch, dan reserve ace")
	var team_turns := 0
	var saw_final_ace := false
	var saw_forced := false
	for value in vectors.get("team", []):
		var case: Dictionary = value
		var label := str(case["name"])
		var state: Dictionary = (case["initial"] as Dictionary).duplicate(true)
		for index in (case["steps"] as Array).size():
			var step: Dictionary = case["steps"][index]
			var slot: Variant = step.get("switch_to_slot", null)
			var outcome := TeamSim.resolve_team_turn(
				state,
				str(step["action"]),
				str(step["key"]),
				str(step.get("item_id", "")),
				null if slot == null else int(slot),
				catalog
			)
			var expected_error := str(step.get("error", ""))
			if not expected_error.is_empty():
				_check_eq(
					str(outcome["error"]),
					expected_error,
					"%s turn %d harus gagal dengan kode yang sama" % [label, index]
				)
				break
			if not bool(outcome["ok"]):
				_check(false, "%s turn %d gagal tak terduga: %s" % [label, index, outcome["error"]])
				break
			_diff_check(outcome["events"], step["events"], "%s turn %d events" % [label, index])
			_diff_check(outcome["state"], step["state"], "%s turn %d state" % [label, index])
			_diff_check(
				outcome["bot_action"], step["bot_action"], "%s turn %d bot_action" % [label, index]
			)
			for event in outcome["events"]:
				if str((event as Dictionary).get("type", "")) == "final_ace":
					saw_final_ace = true
				if str((event as Dictionary).get("type", "")) == "switch" and bool(
					(event as Dictionary).get("forced", false)
				):
					saw_forced = true
			state = outcome["state"]
			team_turns += 1
	_check(team_turns >= 60, "vektor Team harus mencakup banyak turn, dapat %d" % team_turns)
	_check(saw_final_ace, "vektor Team harus melewati jalur final_ace Boss")
	_check(saw_forced, "vektor Team harus melewati jalur forced switch sesudah KO")

	print("6. state lama tanpa rules_version tetap memakai seed lamanya")
	var legacy := {"seed": "abc", "turn": 4}
	_check_eq(BattleSim.turn_seed(legacy, "k"), "abc:4:k", "state lama memakai idempotency key")
	var modern := {"seed": "abc", "turn": 4, "rules_version": BattleSim.RULES_VERSION}
	_check_eq(BattleSim.turn_seed(modern, "k"), "abc:4", "state baru mengabaikan idempotency key")

	_finish()


func _diff_check(actual: Variant, expected: Variant, label: String) -> void:
	var difference := _diff(actual, expected, label)
	_check(difference.is_empty(), difference if not difference.is_empty() else label)


func _diff(actual: Variant, expected: Variant, path: String) -> String:
	var expected_type := typeof(expected)
	var actual_type := typeof(actual)
	if expected_type == TYPE_NIL:
		return "" if actual_type == TYPE_NIL else "%s: dapat %s, mau null" % [path, str(actual)]
	if expected_type == TYPE_BOOL or actual_type == TYPE_BOOL:
		if actual_type != expected_type:
			return "%s: tipe beda, dapat %s mau %s" % [path, str(actual), str(expected)]
		return "" if actual == expected else "%s: dapat %s, mau %s" % [
			path, str(actual), str(expected)
		]
	if expected_type == TYPE_INT or expected_type == TYPE_FLOAT:
		if actual_type != TYPE_INT and actual_type != TYPE_FLOAT:
			return "%s: dapat %s, mau angka %s" % [path, str(actual), str(expected)]
		var lhs := float(actual)
		var rhs := float(expected)
		if is_nan(lhs) and is_nan(rhs):
			return ""
		if absf(lhs - rhs) <= 1e-9 * maxf(1.0, absf(rhs)):
			return ""
		return "%s: dapat %s, mau %s" % [path, str(lhs), str(rhs)]
	if expected_type == TYPE_STRING or expected_type == TYPE_STRING_NAME:
		if actual_type != TYPE_STRING and actual_type != TYPE_STRING_NAME:
			return "%s: dapat %s, mau teks \"%s\"" % [path, str(actual), str(expected)]
		return "" if str(actual) == str(expected) else "%s: dapat \"%s\", mau \"%s\"" % [
			path, str(actual), str(expected)
		]
	if expected_type == TYPE_ARRAY:
		if actual_type != TYPE_ARRAY:
			return "%s: dapat %s, mau array" % [path, str(actual)]
		var expected_array: Array = expected
		var actual_array: Array = actual
		if actual_array.size() != expected_array.size():
			return "%s: panjang %d, mau %d" % [path, actual_array.size(), expected_array.size()]
		for index in expected_array.size():
			var item_diff := _diff(
				actual_array[index], expected_array[index], "%s[%d]" % [path, index]
			)
			if not item_diff.is_empty():
				return item_diff
		return ""
	if expected_type == TYPE_DICTIONARY:
		if actual_type != TYPE_DICTIONARY:
			return "%s: dapat %s, mau dictionary" % [path, str(actual)]
		var expected_dict: Dictionary = expected
		var actual_dict: Dictionary = actual
		for key in expected_dict:
			if not actual_dict.has(key):
				return "%s.%s: kunci hilang" % [path, str(key)]
			var value_diff := _diff(
				actual_dict[key], expected_dict[key], "%s.%s" % [path, str(key)]
			)
			if not value_diff.is_empty():
				return value_diff
		for key in actual_dict:
			if not expected_dict.has(key):
				return "%s.%s: kunci tambahan yang tidak ada di server" % [path, str(key)]
		return ""
	return "" if actual == expected else "%s: beda" % path


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s: dapat %s, mau %s" % [message, str(actual), str(expected)])


func _finish() -> void:
	if _failures.is_empty():
		print("test_battle_sim_parity: OK (%d check)" % _checks)
		quit(0)
		return
	printerr("test_battle_sim_parity: GAGAL %d dari %d check" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - %s" % failure)
	quit(1)
