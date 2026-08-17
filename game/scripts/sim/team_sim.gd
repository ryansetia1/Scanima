class_name TeamSim
extends RefCounted

## Port 1:1 resolver party dari
## `backend/supabase/functions/_shared/team_combat.mjs`. Dipakai Team Battle dan
## combat Expedition. Formula stat, damage, elemen, dan PP datang dari
## `BattleSim`; di sini hanya lapisan roster, switch, forced switch, party wipe,
## dan reserve ace milik Boss.

const MoveEffects = preload("res://scripts/sim/move_effects.gd")

const ACTIONS: PackedStringArray = ["strike", "surge", "guard", "item", "switch"]
const TEAM_MAX_TURNS := 60
const ACE_PASSIVE_TYPES: PackedStringArray = ["bonus_pp", "stat_boost", "one_hit_shield"]
const ACE_STAT_TYPES: PackedStringArray = ["atk", "def", "spd", "special"]
const ACE_NAME_MAX := 48
const ACE_COPY_MAX := 160
const ROSTER_MIN := 1
const ROSTER_MAX := 4
const SWITCH_HP_THRESHOLD := 0.3
const SWITCH_CHANCE := 0.35


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code, "state": {}, "events": [], "bot_action": null}


static func create_team_state(
	player: Array,
	opponent: Array,
	seed_text: String,
	encounter_kind: String = "",
	ace_passive: Variant = null
) -> Dictionary:
	var reserve_ace := encounter_kind == "boss"
	var player_party := create_team_party(player, true, false, null, BattleSim.RULES_VERSION)
	if player_party.is_empty():
		return _error("INVALID_TEAM_ROSTER")
	var opponent_party := create_team_party(
		opponent, false, reserve_ace, normalize_ace_passive(ace_passive) if reserve_ace else null,
		BattleSim.RULES_VERSION
	)
	if opponent_party.is_empty():
		return _error("INVALID_TEAM_ROSTER")
	return {
		"ok": true,
		"error": "",
		"state": {
			"status": "active",
			"turn": 1,
			"seed": seed_text,
			"rules_version": BattleSim.RULES_VERSION,
			"player": player_party,
			"opponent": opponent_party,
		},
	}


## Mengembalikan Dictionary kosong bila roster tidak sah, sepadan dengan
## INVALID_TEAM_ROSTER di server.
static func create_team_party(
	roster: Array,
	player: bool = false,
	reserve_ace_option: bool = false,
	ace_passive: Variant = null,
	rules_version: int = BattleSim.RULES_VERSION
) -> Dictionary:
	if roster.size() < ROSTER_MIN or roster.size() > ROSTER_MAX:
		return {}
	var fighters: Array = []
	for slot in roster.size():
		var member: Dictionary = roster[slot] if typeof(roster[slot]) == TYPE_DICTIONARY else {}
		var fighter := BattleSim.create_fighter(member, rules_version)
		var saved_source: Variant = member["current_hp"] if (
			member.has("current_hp") and member["current_hp"] != null
		) else (member["hp"] if member.has("hp") else NAN)
		var saved_hp := BattleSim.js_number(saved_source)
		if is_finite(saved_hp):
			var previous_max := BattleSim.js_number(
				member["max_hp"] if member.has("max_hp") else NAN
			)
			var hp := int(saved_hp)
			if hp > 0 and is_finite(previous_max) and previous_max > 0.0 and (
				float(fighter["max_hp"]) > previous_max
			):
				hp += int(fighter["max_hp"]) - int(previous_max)
			fighter["hp"] = maxi(0, mini(int(fighter["max_hp"]), hp))
		fighter["anima_id"] = str(member.get("anima_id", ""))
		fighter["name"] = str(member.get("name", ""))
		fighter["strike_name"] = str(member.get("strike_name", ""))
		fighter["surge_name"] = str(member.get("surge_name", ""))
		var height := BattleSim.js_number_or_zero(member.get("body_height_cm", 0))
		fighter["body_height_cm"] = mini(2000, maxi(20, int(height if height != 0.0 else 120.0)))
		fighter["is_ace"] = member.get("special", null) == true
		fighter["ace_passive_applied"] = false
		fighter["slot"] = slot
		fighter["participated"] = false
		fighters.append(fighter)

	var reserve_ace := not player and reserve_ace_option
	var active_slot := -1
	if reserve_ace:
		for i in fighters.size():
			if int(fighters[i]["hp"]) > 0 and not bool(fighters[i]["is_ace"]):
				active_slot = i
				break
	if active_slot < 0:
		for i in fighters.size():
			if int(fighters[i]["hp"]) > 0:
				active_slot = i
				break
	if active_slot < 0:
		return {}
	if player:
		fighters[active_slot]["participated"] = true
	return {
		"active_slot": active_slot,
		"forced_switch": false,
		"item_used": false,
		"reserve_ace": reserve_ace,
		"final_ace_announced": false,
		"ace_passive": normalize_ace_passive(ace_passive) if reserve_ace else null,
		"roster": fighters,
	}


static func resolve_team_turn(
	previous_state: Dictionary,
	player_action: String,
	idempotency_key: String = "",
	item_id: String = "",
	switch_to_slot: Variant = null,
	catalog: Dictionary = {}
) -> Dictionary:
	if str(previous_state.get("status", "")) != "active":
		return _error("TEAM_BATTLE_FINISHED")
	if not player_action in ACTIONS:
		return _error("INVALID_ACTION")

	var state := previous_state.duplicate(true)
	var rng := DeterministicRng.new(BattleSim.turn_seed(state, idempotency_key))
	var events: Array = []
	var player: Dictionary = state["player"]
	var opponent: Dictionary = state["opponent"]
	var rules_version := int(BattleSim.js_number_or_zero(state.get("rules_version", BattleSim.RULES_VERSION)))

	if bool(player.get("forced_switch", false)):
		if player_action != "switch":
			return _error("FORCED_SWITCH_REQUIRED")
		var forced_error := _switch_party(player, switch_to_slot, "player", events, true)
		if not forced_error.is_empty():
			return _error(forced_error)
		_finish_turn(state, events, rules_version)
		return {"ok": true, "error": "", "state": state, "events": events, "bot_action": null}

	var intent_error := _validate_player_intent(player, player_action, item_id, switch_to_slot)
	if not intent_error.is_empty():
		return _error(intent_error)
	if player_action == "item" and not BattleSim.is_battle_item(item_id, catalog):
		return _error("INVALID_ITEM")

	var bot_intent := _choose_opponent_intent(opponent, player, rng, rules_version)
	if player_action == "surge" and int(_active(player)["momentum"]) < BattleSim.SURGE_COST:
		return _error("NO_MOMENTUM")
	if str(bot_intent["action"]) == "surge" and int(_active(opponent)["momentum"]) < BattleSim.SURGE_COST:
		return _error("NO_MOMENTUM")

	if player_action == "switch":
		var switch_error := _switch_party(player, switch_to_slot, "player", events, false)
		if not switch_error.is_empty():
			return _error(switch_error)
	else:
		BattleSim.apply_intent(_active(player), player_action, item_id, catalog)
		if player_action == "item":
			player["item_used"] = true

	if str(bot_intent["action"]) == "switch":
		var bot_switch_error := _switch_party(
			opponent, bot_intent["switch_to_slot"], "opponent", events, false
		)
		if not bot_switch_error.is_empty():
			return _error(bot_switch_error)
	else:
		BattleSim.apply_intent(_active(opponent), str(bot_intent["action"]))

	var player_active := _active(player)
	var opponent_active := _active(opponent)
	if player_action == "guard":
		var guard_event := BattleSim.guard_event("player", player_active)
		guard_event["actor_slot"] = int(player["active_slot"])
		events.append(guard_event)
	if player_action == "item":
		var used_event := BattleSim.item_event("player", player_active, item_id, catalog)
		used_event["actor_slot"] = int(player["active_slot"])
		events.append(used_event)
	if str(bot_intent["action"]) == "guard":
		var bot_guard := BattleSim.guard_event("opponent", opponent_active)
		bot_guard["actor_slot"] = int(opponent["active_slot"])
		events.append(bot_guard)

	var actions := {"player": player_action, "opponent": str(bot_intent["action"])}
	var acted_sides := {}
	var order: Array = []
	for side in BattleSim.turn_order(player_active, opponent_active, rng, rules_version):
		order.append("opponent" if side == "bot" else side)

	for side in order:
		var target_side := "opponent" if side == "player" else "player"
		var party: Dictionary = state[side]
		var target_party: Dictionary = state[target_side]
		var actor := _active(party)
		var target := _active(target_party)
		var action := str(actions[side])
		if (
			int(actor["hp"]) <= 0
			or int(target["hp"]) <= 0
			or action == "guard"
			or action == "item"
			or action == "switch"
		):
			continue

		BattleSim.resolve_combat_attack(
			actor,
			target,
			action,
			rng,
			rules_version,
			side,
			target_side,
			events,
			int(party["active_slot"]),
			int(target_party["active_slot"])
		)
		acted_sides["%s:%d" % [side, int(party["active_slot"])]] = true
		MoveEffects.tick_barrier_owner_turn(
			actor, rules_version, events, side, int(party["active_slot"])
		)
		if int(target["hp"]) == 0:
			_handle_target_knockout(state, target_side, target_party, events)
			break

	_finish_turn(state, events, rules_version, acted_sides)
	return {"ok": true, "error": "", "state": state, "events": events, "bot_action": bot_intent}


static func _validate_player_intent(
	party: Dictionary, action: String, item_id: String, switch_to_slot: Variant
) -> String:
	if action == "item":
		if bool(party.get("item_used", false)):
			return "ITEM_ALREADY_USED"
		if item_id.is_empty():
			return "INVALID_ITEM"
	elif not item_id.is_empty():
		return "INVALID_ITEM"
	if action == "switch":
		return _validate_switch_slot(party, switch_to_slot)
	return ""


static func _choose_opponent_intent(
	party: Dictionary, player_party: Dictionary, rng: DeterministicRng, rules_version: int = BattleSim.RULES_VERSION
) -> Dictionary:
	var fighter := _active(party)
	var foe := _active(player_party)
	var bench := _living_opponent_bench_slots(party)
	if (
		bench.size() > 0
		and float(fighter["hp"]) / float(maxi(1, int(fighter["max_hp"]))) <= SWITCH_HP_THRESHOLD
		and rng.next_float() < SWITCH_CHANCE
	):
		return {
			"action": "switch",
			"switch_to_slot": bench[int(rng.next_float() * float(bench.size()))],
		}
	return {
		"action": BattleSim.choose_bot_action(fighter, rng, foe, rules_version),
		"switch_to_slot": null,
	}


static func _handle_target_knockout(
	state: Dictionary,
	target_side: String,
	target_party: Dictionary,
	events: Array,
	ko_slot: Variant = null
) -> void:
	var slot := int(ko_slot if ko_slot != null else target_party["active_slot"])
	events.append({"type": "knockout", "actor": target_side, "actor_slot": slot})
	if not _has_living_member(target_party):
		state["status"] = "won" if target_side == "opponent" else "lost"
		return
	if target_side == "opponent":
		var replacement: Variant = _first_living_opponent_bench_slot(target_party)
		_switch_party(target_party, replacement, "opponent", events, true)
	else:
		target_party["forced_switch"] = true


static func _switch_party(
	party: Dictionary, slot: Variant, side: String, events: Array, forced: bool
) -> String:
	var slot_error := _validate_switch_slot(party, slot)
	if not slot_error.is_empty():
		return slot_error
	var target_slot := int(slot)
	var previous := int(party["active_slot"])
	var incoming: Dictionary = party["roster"][target_slot]
	var final_ace := (
		side == "opponent"
		and bool(party.get("reserve_ace", false))
		and bool(incoming.get("is_ace", false))
		and not bool(party.get("final_ace_announced", false))
	)
	if final_ace:
		party["final_ace_announced"] = true
		events.append({
			"type": "final_ace",
			"actor": side,
			"to_slot": target_slot,
			"anima_id": str(incoming.get("anima_id", "")),
			"name": str(incoming.get("name", "")),
		})
	party["active_slot"] = target_slot
	party["forced_switch"] = false
	_active(party)["participated"] = true
	events.append({
		"type": "switch",
		"actor": side,
		"from_slot": previous,
		"to_slot": target_slot,
		"forced": forced,
	})
	if final_ace:
		_apply_ace_passive(party, incoming, events)
	return ""


## anima_id yang masuk pada setiap event `switch` di log. Pemanggil memakainya
## untuk memastikan sheet penggantinya sudah ada sebelum menganimasikan turn dari
## simulasi lokal; slot yang tidak masuk akal mengembalikan "" supaya gagal cek.
static func switch_targets(events: Array, state: Dictionary) -> PackedStringArray:
	var targets := PackedStringArray()
	for value in events:
		var event: Dictionary = value if value is Dictionary else {}
		if str(event.get("type", "")) != "switch":
			continue
		var party: Variant = state.get(str(event.get("actor", "")))
		var roster: Array = (party as Dictionary).get("roster", []) if party is Dictionary else []
		var slot := int(event.get("to_slot", -1))
		var member: Variant = roster[slot] if slot >= 0 and slot < roster.size() else null
		targets.append(str((member as Dictionary).get("anima_id", "")) if member is Dictionary else "")
	return targets


static func _validate_switch_slot(party: Dictionary, slot: Variant) -> String:
	var roster: Array = party.get("roster", [])
	if typeof(slot) != TYPE_INT or int(slot) < 0 or int(slot) >= roster.size():
		return "INVALID_SWITCH_SLOT"
	var target_slot := int(slot)
	if target_slot == int(party["active_slot"]) or int(roster[target_slot]["hp"]) <= 0:
		return "INVALID_SWITCH_SLOT"
	if (
		bool(party.get("reserve_ace", false))
		and bool(roster[target_slot].get("is_ace", false))
		and _has_living_regular(party)
	):
		return "INVALID_SWITCH_SLOT"
	return ""


static func _finish_turn(
	state: Dictionary,
	events: Array,
	rules_version: int = BattleSim.RULES_VERSION,
	acted_sides: Dictionary = {}
) -> void:
	for party_key in ["player", "opponent"]:
		for fighter in state[party_key]["roster"]:
			fighter["guarding"] = false
	var effect_ko: Dictionary = BattleSim.finish_effect_turn(
		state, events, rules_version, acted_sides, true
	)
	var kos: Array = effect_ko.get("kos", []).duplicate(true)
	kos.reverse()
	for ko_value in kos:
		var ko: Dictionary = ko_value
		var ko_side := str(ko.get("side", ""))
		var ko_party: Dictionary = state[ko_side]
		var ko_slot: Variant = ko.get("slot", int(ko_party.get("active_slot", 0)))
		_handle_target_knockout(state, ko_side, ko_party, events, ko_slot)
	state["turn"] = int(state["turn"]) + 1

	if str(state["status"]) == "active" and int(state["turn"]) > TEAM_MAX_TURNS:
		var player_ratio := _remaining_hp_ratio(state["player"])
		var opponent_ratio := _remaining_hp_ratio(state["opponent"])
		if absf(player_ratio - opponent_ratio) <= 1e-9:
			state["status"] = "draw"
		else:
			state["status"] = "won" if player_ratio > opponent_ratio else "lost"
		var winner: Variant = null
		if str(state["status"]) != "draw":
			winner = "player" if str(state["status"]) == "won" else "opponent"
		events.append({"type": "timeout", "winner": winner})
	if str(state["status"]) != "active":
		events.append({"type": "finished", "result": str(state["status"])})


static func _remaining_hp_ratio(party: Dictionary) -> float:
	var current := 0.0
	var maximum := 0.0
	for fighter in party["roster"]:
		current += float(maxi(0, int(fighter["hp"])))
		maximum += float(maxi(1, int(fighter["max_hp"])))
	return current / maxf(1.0, maximum)


static func _active(party: Dictionary) -> Dictionary:
	return party["roster"][int(party["active_slot"])]


static func _living_bench_slots(party: Dictionary) -> Array:
	var slots: Array = []
	for fighter in party["roster"]:
		if int(fighter["slot"]) != int(party["active_slot"]) and int(fighter["hp"]) > 0:
			slots.append(int(fighter["slot"]))
	return slots


## Reserve ace boss disembunyikan selama masih ada anggota reguler yang hidup.
static func _living_opponent_bench_slots(party: Dictionary) -> Array:
	var bench := _living_bench_slots(party)
	if not bool(party.get("reserve_ace", false)):
		return bench
	if not _has_living_regular(party):
		return bench
	var regular: Array = []
	for slot in bench:
		if not bool(party["roster"][slot].get("is_ace", false)):
			regular.append(slot)
	return regular


static func _first_living_opponent_bench_slot(party: Dictionary) -> Variant:
	var bench := _living_opponent_bench_slots(party)
	return bench[0] if bench.size() > 0 else -1


static func _has_living_regular(party: Dictionary) -> bool:
	for fighter in party["roster"]:
		if int(fighter["hp"]) > 0 and not bool(fighter.get("is_ace", false)):
			return true
	return false


static func _has_living_member(party: Dictionary) -> bool:
	for fighter in party["roster"]:
		if int(fighter["hp"]) > 0:
			return true
	return false


static func normalize_ace_passive(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var source: Dictionary = value
	var type_name := str(source.get("type", ""))
	if not type_name in ACE_PASSIVE_TYPES:
		return null
	var passive := {
		"type": type_name,
		"name": str(source.get("name", "")).substr(0, ACE_NAME_MAX),
		"copy": str(source.get("copy", "")).substr(0, ACE_COPY_MAX),
	}
	if type_name == "bonus_pp":
		var bonus := BattleSim.js_number_or_zero(source.get("value", 0))
		passive["value"] = mini(2, maxi(1, int(bonus if bonus != 0.0 else 1.0)))
	elif type_name == "stat_boost":
		var stat := str(source.get("stat", ""))
		if not stat in ACE_STAT_TYPES:
			return null
		passive["stat"] = stat
		var boost := BattleSim.js_number_or_zero(source.get("value", 0))
		passive["value"] = mini(25, maxi(1, int(boost if boost != 0.0 else 10.0)))
	return passive


static func _apply_ace_passive(party: Dictionary, fighter: Dictionary, events: Array) -> void:
	var normalized: Variant = normalize_ace_passive(party.get("ace_passive", null))
	if normalized == null or bool(fighter.get("ace_passive_applied", false)):
		return
	var passive: Dictionary = normalized
	fighter["ace_passive_applied"] = true
	var passive_type := str(passive["type"])
	if passive_type == "bonus_pp":
		fighter["momentum_max"] = mini(5, int(fighter["momentum_max"]) + int(passive["value"]))
		fighter["momentum"] = mini(
			int(fighter["momentum_max"]), int(fighter["momentum"]) + int(passive["value"])
		)
	elif passive_type == "stat_boost":
		var stat := str(passive["stat"])
		fighter[stat] = maxi(
			1, int(float(fighter[stat]) * (1.0 + float(passive["value"]) / 100.0))
		)
	elif passive_type == "one_hit_shield":
		fighter["shield_charges"] = maxi(1, int(fighter["shield_charges"]))
	events.append({
		"type": "ace_passive",
		"actor": "opponent",
		"actor_slot": int(party["active_slot"]),
		"passive_type": passive_type,
		"passive_name": str(passive["name"]),
		"copy": str(passive["copy"]),
		"value": passive.get("value", 1),
		"stat": passive.get("stat", ""),
		"momentum": int(fighter["momentum"]),
		"momentum_max": int(fighter["momentum_max"]),
		"shield_charges": int(fighter["shield_charges"]),
	})
