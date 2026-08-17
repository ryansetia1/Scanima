class_name BattleSim
extends RefCounted

## Port 1:1 resolver Duel dari
## `backend/supabase/functions/_shared/battle.mjs`. Server tetap otoritas: ia
## menghitung ulang turn yang sama dari state miliknya dan hasilnya yang menang.
## Simulasi ini ada supaya animasi mulai pada frame yang sama dengan tap, dan
## supaya sesi yang sudah dimulai tetap bisa dimainkan tanpa koneksi.
##
## Paritas dijaga `tests/test_battle_sim_parity.gd` memakai vektor emas yang
## digenerasi dari `.mjs` aslinya lewat `backend/tools/emit_sim_vectors.mjs`.
## Konstanta di bawah dipindai skenario 32 `npm run selftest`; jangan ubah
## nilainya di satu sisi saja.

const ACTIONS: PackedStringArray = ["strike", "surge", "guard", "item"]
const RULES_VERSION := 2
const MOMENTUM_MAX := 3
const MOMENTUM_START := 3
const SURGE_COST := 1
const BATTLE_MAX_TURNS := 30
const LEVEL_CAP := 40
const HUNGRY_NEED := 40.0
const DIRTY_NEED := 50.0
const HUNGRY_COMBAT_FLOOR := 0.6
const DIRTY_COMBAT_FLOOR := 0.7
const CARE_COMBAT_FLOOR := 0.5
const STRIKE_POWER := 50
const SURGE_POWER := 75
const CRIT_MULTIPLIER := 1.8
const GUARD_MULTIPLIER := 0.5
const VARIANCE_MIN := 0.92
const VARIANCE_SPAN := 0.16
const SHIELD_MULTIPLIER := 0.2
const STAT_KEYS: PackedStringArray = ["hp", "atk", "def", "spd", "special"]


# --- Aritmetika yang meniru JavaScript -------------------------------------
#
# `Number(null)` adalah 0 sementara `Number(undefined)` adalah NaN, dan
# `clampInt` memakai fallback hanya untuk yang tidak finite. Bedanya nyata:
# hunger null berarti kelaparan (multiplier 0.6), hunger yang tidak ada berarti
# netral (multiplier 1.0). Pembacaan dictionary karena itu memakai NAN sebagai
# penanda "tidak ada", bukan null.


static func js_number(value: Variant) -> float:
	match typeof(value):
		TYPE_NIL:
			return 0.0
		TYPE_BOOL:
			return 1.0 if value else 0.0
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value).strip_edges()
			if text.is_empty():
				return 0.0
			return float(text) if text.is_valid_float() else NAN
		_:
			return NAN


## Padanan `Number(value) || 0`: NaN dan 0 sama-sama menjadi 0.
static func js_number_or_zero(value: Variant) -> float:
	var number := js_number(value)
	return 0.0 if not is_finite(number) else number


static func clamp_int(value: Variant, min_value: int, max_value: int, fallback: float) -> int:
	var number := js_number(value)
	var picked := number if is_finite(number) else fallback
	return int(clampf(picked, float(min_value), float(max_value)))


static func _field(source: Dictionary, key: String) -> Variant:
	return source[key] if source.has(key) else NAN


# --- Level, stat, dan care --------------------------------------------------


static func growth_multiplier(level: Variant) -> float:
	return CareRules.growth_multiplier(clamp_int(level, 1, LEVEL_CAP, 1))


static func normalize_base_stats(base_stats: Variant) -> Dictionary:
	var source: Dictionary = base_stats if typeof(base_stats) == TYPE_DICTIONARY else {}
	var normalized := {}
	for key in STAT_KEYS:
		normalized[key] = clamp_int(_field(source, key), 10, 95, 50)
	return normalized


static func to_battle_stats(base_stats: Variant, level: Variant = 1) -> Dictionary:
	# ponytail: stage multiplier tidur sampai art evolusi ada, persis seperti
	# catatan di battle.mjs. Level adalah satu-satunya jalur pertumbuhan live.
	var base := normalize_base_stats(base_stats)
	var g := growth_multiplier(level)
	return {
		"max_hp": int(float(base["hp"]) * 4.0 * g) + 20,
		"atk": int(float(base["atk"]) * g),
		"def": int(float(base["def"]) * g),
		"spd": int(float(base["spd"]) * g),
		"special": int(float(base["special"]) * g),
	}


static func _meter_combat_multiplier(value: Variant, need: float, floor_value: float) -> float:
	var n := js_number(value)
	if not is_finite(n) or n >= need:
		return 1.0
	return floor_value + (1.0 - floor_value) * maxf(0.0, n) / need


static func hunger_combat_multiplier(hunger: Variant) -> float:
	return _meter_combat_multiplier(hunger, HUNGRY_NEED, HUNGRY_COMBAT_FLOOR)


static func hygiene_combat_multiplier(hygiene: Variant) -> float:
	return _meter_combat_multiplier(hygiene, DIRTY_NEED, DIRTY_COMBAT_FLOOR)


static func care_combat_multiplier(hunger: Variant, hygiene: Variant) -> float:
	return maxf(
		CARE_COMBAT_FLOOR,
		hunger_combat_multiplier(hunger) * hygiene_combat_multiplier(hygiene)
	)


static func _scale_combat_stats(stats: Dictionary, mult: float) -> Dictionary:
	if mult >= 1.0:
		return stats
	return {
		"max_hp": maxi(1, int(float(stats["max_hp"]) * mult)),
		"atk": maxi(1, int(float(stats["atk"]) * mult)),
		"def": maxi(1, int(float(stats["def"]) * mult)),
		"spd": maxi(1, int(float(stats["spd"]) * mult)),
		"special": maxi(1, int(float(stats["special"]) * mult)),
	}


## `input?.hunger ?? input?.care?.hunger`. NAN berarti tidak ada di kedua tempat.
static func _care_meter(input: Dictionary, key: String) -> Variant:
	if input.has(key) and input[key] != null:
		return input[key]
	var care: Variant = input.get("care", null)
	if typeof(care) == TYPE_DICTIONARY:
		var care_dict: Dictionary = care
		if care_dict.has(key):
			return care_dict[key]
	return NAN


static func create_fighter(input: Variant) -> Dictionary:
	var source: Dictionary = input if typeof(input) == TYPE_DICTIONARY else {}
	var grown := to_battle_stats(source.get("base_stats", null), _field(source, "level"))
	var stats := _scale_combat_stats(
		grown, care_combat_multiplier(_care_meter(source, "hunger"), _care_meter(source, "hygiene"))
	)
	var secondary_raw: Variant = source.get("secondary_element", null)
	var has_secondary := secondary_raw != null and not str(secondary_raw).is_empty()
	return {
		"max_hp": stats["max_hp"],
		"atk": stats["atk"],
		"def": stats["def"],
		"spd": stats["spd"],
		"special": stats["special"],
		"hp": stats["max_hp"],
		"momentum": MOMENTUM_START,
		"momentum_max": MOMENTUM_MAX,
		"guarding": false,
		"atk_mult": 1,
		"special_mult": 1,
		"incoming_mult": 1,
		"shield_charges": 0,
		"item_used": false,
		"item_id": "",
		"element": ElementRules.normalize(source.get("element", null)),
		"secondary_element": ElementRules.normalize(secondary_raw, "") if has_secondary else "",
		"species_key": str(source.get("species_key", "")),
		"color_bucket": str(source.get("color_bucket", "")),
		"stage": clamp_int(_field(source, "stage"), 1, 3, 1),
		"level": clamp_int(_field(source, "level"), 1, LEVEL_CAP, 1),
		"evolution_branch": str(source.get("evolution_branch", "")),
	}


# --- Damage -----------------------------------------------------------------


static func crit_chance(speed: Variant) -> float:
	return clampf(js_number(speed) / 400.0, 0.02, 0.25)


static func compute_damage(
	attack: float,
	defense: float,
	power: int,
	element: float = 1.0,
	crit: bool = false,
	variance: float = 1.0,
	guarding: bool = false
) -> int:
	var mitigation := 100.0 / (100.0 + maxf(0.0, js_number_or_zero(defense)))
	var critical := CRIT_MULTIPLIER if crit else 1.0
	var guard := GUARD_MULTIPLIER if guarding else 1.0
	var raw := (
		maxf(0.0, js_number_or_zero(attack))
		* (maxf(0.0, float(power)) / 50.0)
		* mitigation
		* maxf(0.0, js_number_or_zero(element))
		* critical
		* clampf(js_number_or_zero(variance), VARIANCE_MIN, VARIANCE_MIN + VARIANCE_SPAN)
		* guard
	)
	return maxi(1, int(raw))


static func apply_incoming_modifiers(target: Dictionary, damage: int) -> int:
	var incoming := js_number_or_zero(target.get("incoming_mult", 1))
	if incoming == 0.0:
		incoming = 1.0
	var next := maxi(1, int(float(damage) * incoming))
	if int(target.get("shield_charges", 0)) > 0:
		next = maxi(1, int(float(next) * SHIELD_MULTIPLIER))
		target["shield_charges"] = int(target["shield_charges"]) - 1
	return next


# --- Intent -----------------------------------------------------------------


static func index_catalog(rows: Variant) -> Dictionary:
	var index := {}
	if typeof(rows) != TYPE_ARRAY:
		return index
	for value in rows:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = value
		var id := str(row.get("id", row.get("item_id", "")))
		if not id.is_empty():
			index[id] = row
	return index


static func is_battle_item(item_id: String, catalog: Dictionary) -> bool:
	var row: Variant = catalog.get(item_id, null)
	return typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("use_type", "")) == "battle"


static func apply_intent(
	fighter: Dictionary, action: String, item_id: String = "", catalog: Dictionary = {}
) -> void:
	if action == "surge":
		fighter["momentum"] = int(fighter["momentum"]) - SURGE_COST
	if action == "guard":
		var cap := int(fighter.get("momentum_max", MOMENTUM_MAX))
		if cap <= 0:
			cap = MOMENTUM_MAX
		fighter["momentum"] = mini(cap, int(fighter["momentum"]) + 1)
		fighter["guarding"] = true
	if action == "item":
		_apply_battle_item(fighter, item_id, catalog)


static func _apply_battle_item(fighter: Dictionary, item_id: String, catalog: Dictionary) -> void:
	var item: Dictionary = catalog.get(item_id, {})
	fighter["item_used"] = true
	fighter["item_id"] = str(item.get("id", item_id))
	var value := js_number_or_zero(item.get("effect_value", 0))
	var effect := str(item.get("effect", ""))
	match effect:
		"heal_hp_pct":
			fighter["hp"] = mini(
				int(fighter["max_hp"]),
				int(fighter["hp"]) + int(float(fighter["max_hp"]) * (value / 100.0))
			)
		"buff_atk":
			fighter["atk_mult"] = 1.0 + value / 100.0
		"buff_special":
			fighter["special_mult"] = 1.0 + value / 100.0
		"buff_guard":
			fighter["incoming_mult"] = 1.0 - value / 100.0
		"buff_spd":
			fighter["spd"] = maxi(1, int(float(fighter["spd"]) * (1.0 + value / 100.0)))
		"pp_boost":
			var cap := int(fighter.get("momentum_max", MOMENTUM_MAX))
			fighter["momentum_max"] = mini(5, (cap if cap > 0 else MOMENTUM_MAX) + int(value))
			fighter["momentum"] = mini(
				int(fighter["momentum_max"]), int(fighter["momentum"]) + int(value)
			)
		"phase_shield":
			fighter["shield_charges"] = 1


static func choose_bot_action(fighter: Dictionary, rng: DeterministicRng) -> String:
	var roll := rng.next_float()
	var hp_ratio := float(fighter["hp"]) / float(maxi(1, int(fighter["max_hp"])))
	if hp_ratio <= 0.4 and roll < 0.45:
		return "guard"
	if int(fighter["momentum"]) >= SURGE_COST and roll < 0.68:
		return "surge"
	return "strike"


static func turn_order(player: Dictionary, bot: Dictionary, rng: DeterministicRng) -> Array:
	var player_spd := int(player["spd"])
	var bot_spd := int(bot["spd"])
	if player_spd > bot_spd:
		return ["player", "bot"]
	if bot_spd > player_spd:
		return ["bot", "player"]
	return ["player", "bot"] if rng.next_float() < 0.5 else ["bot", "player"]


static func guard_event(actor: String, fighter: Dictionary) -> Dictionary:
	return {"type": "guard", "actor": actor, "momentum": int(fighter["momentum"])}


static func item_event(actor: String, fighter: Dictionary, item_id: String, catalog: Dictionary) -> Dictionary:
	var item: Dictionary = catalog.get(item_id, {})
	return {
		"type": "item",
		"actor": actor,
		"item_id": item_id,
		"effect": str(item.get("effect", "")),
		"effect_value": item.get("effect_value", 0),
		"hp": int(fighter["hp"]),
		"momentum": int(fighter["momentum"]),
		"momentum_max": int(fighter["momentum_max"]),
	}


# --- Seed dan resolusi turn -------------------------------------------------


## Sampai rules_version 1, idempotency_key ikut ke dalam seed. Key itu dipilih
## client, jadi state lama tetap memakai formula lamanya agar replay-nya cocok.
static func turn_seed(state: Dictionary, idempotency_key: String = "") -> String:
	var version := int(js_number_or_zero(state.get("rules_version", 0)))
	if version < 1:
		version = 1
	var base := "%s:%d" % [str(state.get("seed", "")), int(state.get("turn", 0))]
	return base if version >= 2 else "%s:%s" % [base, idempotency_key]


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code, "state": {}, "events": [], "bot_action": ""}


static func resolve_turn(
	previous_state: Dictionary,
	player_action: String,
	idempotency_key: String = "",
	item_id: String = "",
	catalog: Dictionary = {}
) -> Dictionary:
	if str(previous_state.get("status", "")) != "active":
		return _error("BATTLE_FINISHED")
	if not player_action in ACTIONS:
		return _error("INVALID_ACTION")
	var player_before: Dictionary = previous_state.get("player", {})
	if player_action == "item":
		if bool(player_before.get("item_used", false)):
			return _error("ITEM_ALREADY_USED")
		if not is_battle_item(item_id, catalog):
			return _error("INVALID_ITEM")
	if player_action == "surge" and int(player_before.get("momentum", 0)) < SURGE_COST:
		return _error("NO_MOMENTUM")

	var state := previous_state.duplicate(true)
	var rng := DeterministicRng.new(turn_seed(state, idempotency_key))
	var player: Dictionary = state["player"]
	var bot: Dictionary = state["bot"]
	var bot_action := choose_bot_action(bot, rng)

	var actions := {"player": player_action, "bot": bot_action}
	var events: Array = []
	apply_intent(player, player_action, item_id, catalog)
	apply_intent(bot, bot_action)
	if player_action == "guard":
		events.append(guard_event("player", player))
	if player_action == "item":
		events.append(item_event("player", player, item_id, catalog))
	if bot_action == "guard":
		events.append(guard_event("bot", bot))

	for actor_name in turn_order(player, bot, rng):
		var target_name := "bot" if actor_name == "player" else "player"
		var actor: Dictionary = state[actor_name]
		var target: Dictionary = state[target_name]
		var action := str(actions[actor_name])
		if int(actor["hp"]) <= 0 or int(target["hp"]) <= 0 or action == "guard" or action == "item":
			continue

		var crit := rng.next_float() < crit_chance(actor["spd"])
		var secondary := str(actor["secondary_element"])
		var attack_element := (
			(secondary if not secondary.is_empty() else str(actor["element"]))
			if action == "surge"
			else str(actor["element"])
		)
		var target_defenses := ElementRules.defense_elements(
			target["element"], target["secondary_element"]
		)
		var elem := ElementRules.dual_defender_multiplier(
			attack_element, target["element"], target["secondary_element"]
		)
		var attack := (
			float(actor["special"]) * js_number_or_zero(actor.get("special_mult", 1))
			if action == "surge"
			else float(actor["atk"]) * js_number_or_zero(actor.get("atk_mult", 1))
		)
		var defense := (
			float(int(float(target["def"]) * 0.5)) if action == "surge" else float(target["def"])
		)
		var damage := compute_damage(
			attack,
			defense,
			SURGE_POWER if action == "surge" else STRIKE_POWER,
			elem,
			crit,
			VARIANCE_MIN + rng.next_float() * VARIANCE_SPAN,
			bool(target["guarding"])
		)
		damage = apply_incoming_modifiers(target, damage)
		target["hp"] = maxi(0, int(target["hp"]) - damage)
		events.append({
			"type": "attack",
			"actor": actor_name,
			"target": target_name,
			"action": action,
			"damage": damage,
			"crit": crit,
			"attack_element": attack_element,
			"defense_elements": target_defenses,
			"element_multiplier": elem,
			"target_hp": int(target["hp"]),
		})
		if int(target["hp"]) == 0:
			events.append({"type": "knockout", "actor": target_name})

	player["guarding"] = false
	bot["guarding"] = false
	if int(bot["hp"]) == 0:
		state["status"] = "won"
	elif int(player["hp"]) == 0:
		state["status"] = "lost"

	# PP sengaja tidak pulih per turn; satu-satunya pemulihan adalah Guard.
	state["turn"] = int(state["turn"]) + 1

	if str(state["status"]) == "active" and int(state["turn"]) > BATTLE_MAX_TURNS:
		var player_ratio := float(player["hp"]) / float(player["max_hp"])
		var bot_ratio := float(bot["hp"]) / float(bot["max_hp"])
		state["status"] = "won" if player_ratio > bot_ratio else "lost"
		events.append({
			"type": "timeout",
			"winner": "player" if str(state["status"]) == "won" else "bot",
		})

	if str(state["status"]) != "active":
		events.append({"type": "finished", "result": str(state["status"])})

	return {"ok": true, "error": "", "state": state, "events": events, "bot_action": bot_action}


# --- Reward ------------------------------------------------------------------
#
# Tier dan Bits sengaja tidak ada di sini. Keduanya server-authoritative, hasil
# mensimulasikan matchup 64 kali di `_shared/battle.mjs`, dan client tidak pernah
# menampilkan hadiah sebelum server menjawab — jadi port-nya cuma permukaan yang
# bisa menyimpang tanpa satu pun pemanggil.


static func battle_exp_yield(
	recipient_level: int, opponent_level: int, difficulty: String = "even"
) -> int:
	var recipient := clampi(recipient_level, 1, LEVEL_CAP)
	var opponent := clampi(opponent_level, 1, LEVEL_CAP)
	var base := 1 + ceili(float(opponent) / 10.0)
	var underdog := mini(2, floori(float(maxi(0, opponent - recipient)) / 5.0))
	var tier := 1 if difficulty in ["tough", "formidable", "elite", "boss"] else 0
	return clampi(base + underdog + tier, 1, 8)
