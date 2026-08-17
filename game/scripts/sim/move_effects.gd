class_name MoveEffects
extends RefCounted

## Port 1:1 dari `backend/supabase/functions/_shared/move_effects.mjs`.

const EVOLUTION_EFFECT_IDS: PackedStringArray = [
	"armor_pierce", "guard_break", "drain", "barrier", "poison", "burn", "slow", "armor_break",
]
const STRIKE_EFFECT_IDS: PackedStringArray = [
	"armor_pierce", "guard_break", "drain", "poison", "burn", "slow", "armor_break",
]
const SURGE_EFFECT_IDS: PackedStringArray = [
	"barrier", "guard_break", "drain", "burn", "slow", "armor_break",
]
const ADULT_FORM_MULT := 1.06
const EVOLVED_FORM_MULT := 1.18
const ADULT_EFFECT_POWER_BONUS := 0.04
const EVOLVED_EFFECT_POWER_BONUS := 0.06

# ponytail: salinan kecil js_number_or_zero supaya tidak circular-import BattleSim.
static func _js_number(value: Variant) -> float:
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


static func _js_number_or_zero(value: Variant) -> float:
	var number := _js_number(value)
	return 0.0 if not is_finite(number) else number


static func normalize_effect_id(value: Variant) -> String:
	var id := str(value).strip_edges()
	return id if id in EVOLUTION_EFFECT_IDS else ""


static func uses_evolution_combat(rules_version: Variant, evolution_version: Variant) -> bool:
	return int(_js_number_or_zero(rules_version)) >= 3 \
		and int(_js_number_or_zero(evolution_version)) >= 1


static func form_multiplier(stage: Variant) -> float:
	var s := int(_js_number_or_zero(stage))
	if s >= 3:
		return EVOLVED_FORM_MULT
	if s >= 2:
		return ADULT_FORM_MULT
	return 1.0


static func effect_strength(stage: Variant) -> float:
	return 0.30 if int(_js_number_or_zero(stage)) >= 3 else 0.20


static func effect_id_for_action(fighter: Dictionary, action: String) -> String:
	if action == "strike":
		return normalize_effect_id(fighter.get("strike_effect_id", ""))
	if action == "surge":
		return normalize_effect_id(fighter.get("surge_effect_id", ""))
	return ""


static func should_apply_effects(rules_version: Variant, fighter: Dictionary) -> bool:
	return uses_evolution_combat(rules_version, fighter.get("evolution_version", 0))


static func has_evolution_effects(rules_version: Variant, fighter: Dictionary) -> bool:
	return should_apply_effects(rules_version, fighter) and (
		not effect_id_for_action(fighter, "strike").is_empty()
		or not effect_id_for_action(fighter, "surge").is_empty()
	)


static func effects_combat_active(rules_version: Variant) -> bool:
	return int(_js_number_or_zero(rules_version)) >= 3


static func effect_power_bonus(fighter: Dictionary, rules_version: int = 3) -> float:
	if not should_apply_effects(rules_version, fighter):
		return 0.0
	var stage := int(_js_number_or_zero(fighter.get("stage", 1)))
	var rate := EVOLVED_EFFECT_POWER_BONUS if stage >= 3 else ADULT_EFFECT_POWER_BONUS
	var count := 0
	if not effect_id_for_action(fighter, "strike").is_empty():
		count += 1
	if not effect_id_for_action(fighter, "surge").is_empty():
		count += 1
	return float(count) * rate


static func attach_effect_fields(fighter: Dictionary, input: Dictionary, rules_version: int = 3) -> Dictionary:
	fighter["strike_effect_id"] = normalize_effect_id(input.get("strike_effect_id", ""))
	fighter["surge_effect_id"] = normalize_effect_id(input.get("surge_effect_id", ""))
	fighter["evolution_version"] = maxi(0, int(_js_number_or_zero(input.get("evolution_version", 0))))
	if typeof(fighter.get("statuses", null)) != TYPE_DICTIONARY:
		fighter["statuses"] = {}
	if not fighter.has("barrier"):
		fighter["barrier"] = null
	if not should_apply_effects(rules_version, fighter):
		fighter["statuses"] = {}
		fighter["barrier"] = null
	return fighter


static func effective_spd(fighter: Dictionary) -> int:
	var base := maxi(1, int(fighter.get("spd", 1)))
	var statuses: Dictionary = fighter.get("statuses", {})
	var slow: Variant = statuses.get("slow", null)
	if typeof(slow) != TYPE_DICTIONARY:
		return base
	var strength := _js_number_or_zero((slow as Dictionary).get("strength", 0))
	return maxi(1, int(float(base) * (1.0 - strength)))


static func effective_def(fighter: Dictionary) -> int:
	var base := maxi(0, int(fighter.get("def", 0)))
	var statuses: Dictionary = fighter.get("statuses", {})
	var break_status: Variant = statuses.get("armor_break", null)
	if typeof(break_status) != TYPE_DICTIONARY:
		return base
	var strength := _js_number_or_zero((break_status as Dictionary).get("strength", 0))
	return maxi(0, int(float(base) * (1.0 - strength)))


static func _status_turns(effect_id: String, stage: Variant) -> int:
	match effect_id:
		"burn":
			return 3 if int(_js_number_or_zero(stage)) >= 3 else 2
		"poison", "slow", "armor_break":
			return 3
		_:
			return 0


static func _barrier_owner_turns(stage: Variant) -> int:
	return 3 if int(_js_number_or_zero(stage)) >= 3 else 2


static func _refresh_status(fighter: Dictionary, effect_id: String, stage: Variant) -> void:
	var turns := _status_turns(effect_id, stage)
	if turns <= 0:
		return
	var statuses: Dictionary = fighter.get("statuses", {})
	statuses[effect_id] = {"remaining_turns": turns, "strength": effect_strength(stage)}
	fighter["statuses"] = statuses


static func _move_effect_event(
	side: String, target_side: String, effect_id: String, extra: Dictionary = {}
) -> Dictionary:
	var event := {
		"type": "move_effect",
		"actor": side,
		"target": target_side,
		"effect_id": effect_id,
	}
	for key in extra.keys():
		event[key] = extra[key]
	return event


static func pre_damage_modifiers(
	actor: Dictionary,
	target: Dictionary,
	action: String,
	rules_version: int,
	effect_events: Array,
	actor_side: String,
	target_side: String,
	actor_slot: Variant = null,
	target_slot: Variant = null
) -> Dictionary:
	var defense := (
		int(float(effective_def(target)) * 0.5) if action == "surge" else effective_def(target)
	)
	var guarding := bool(target.get("guarding", false))
	if not should_apply_effects(rules_version, actor):
		return {"defense": defense, "guarding": guarding}

	var effect_id := effect_id_for_action(actor, action)
	if effect_id.is_empty():
		return {"defense": defense, "guarding": guarding}

	var stage := int(_js_number_or_zero(actor.get("stage", 1)))
	var strength := effect_strength(stage)
	var extra := {}
	if actor_slot != null:
		extra["actor_slot"] = actor_slot
	if target_slot != null:
		extra["target_slot"] = target_slot

	if effect_id == "armor_pierce":
		defense = maxi(0, int(float(defense) * (1.0 - strength)))
		var pierce_extra := extra.duplicate()
		pierce_extra["amount"] = strength
		effect_events.append(_move_effect_event(actor_side, target_side, effect_id, pierce_extra))

	if effect_id == "guard_break" and guarding:
		guarding = false
		target["guarding"] = false
		var break_extra := extra.duplicate()
		break_extra["amount"] = strength
		effect_events.append(_move_effect_event(actor_side, target_side, effect_id, break_extra))

	return {"defense": defense, "guarding": guarding}


static func apply_barrier_to_damage(
	target: Dictionary,
	damage: int,
	rules_version: int,
	effect_events: Array,
	target_side: String,
	target_slot: Variant = null
) -> int:
	if not should_apply_effects(rules_version, target):
		return damage
	var barrier: Variant = target.get("barrier", null)
	if typeof(barrier) != TYPE_DICTIONARY:
		return damage
	var barrier_dict: Dictionary = barrier
	if int(barrier_dict.get("uses_remaining", 0)) <= 0:
		return damage
	var reduction := _js_number_or_zero(barrier_dict.get("reduction", 0))
	var next := maxi(1, int(float(damage) * (1.0 - reduction)))
	var extra := {
		"amount": reduction,
		"target_hp": maxi(0, int(target.get("hp", 0)) - next),
	}
	if target_slot != null:
		extra["actor_slot"] = target_slot
		extra["target_slot"] = target_slot
	effect_events.append(_move_effect_event(target_side, target_side, "barrier", extra))
	target["barrier"] = null
	return next


static func apply_post_move_effects(
	actor: Dictionary,
	target: Dictionary,
	action: String,
	damage: int,
	rules_version: int,
	effect_events: Array,
	actor_side: String,
	target_side: String,
	actor_slot: Variant = null,
	target_slot: Variant = null
) -> void:
	if not should_apply_effects(rules_version, actor):
		return
	var effect_id := effect_id_for_action(actor, action)
	if effect_id.is_empty():
		return
	var stage := int(_js_number_or_zero(actor.get("stage", 1)))
	var strength := effect_strength(stage)
	var extra := {}
	if actor_slot != null:
		extra["actor_slot"] = actor_slot
	if target_slot != null:
		extra["target_slot"] = target_slot

	if effect_id == "drain" and damage > 0:
		var heal := maxi(1, int(float(damage) * strength))
		actor["hp"] = mini(int(actor.get("max_hp", 0)), int(actor.get("hp", 0)) + heal)
		var drain_extra := extra.duplicate()
		drain_extra["amount"] = heal
		drain_extra["target_hp"] = int(actor["hp"])
		effect_events.append(_move_effect_event(actor_side, actor_side, effect_id, drain_extra))

	if effect_id == "barrier":
		var turns := _barrier_owner_turns(stage)
		actor["barrier"] = {
			"reduction": strength,
			"uses_remaining": 1,
			"owner_turns_remaining": turns,
			"just_applied": true,
		}
		var barrier_extra := extra.duplicate()
		barrier_extra["amount"] = strength
		barrier_extra["remaining_turns"] = turns
		effect_events.append(_move_effect_event(actor_side, actor_side, effect_id, barrier_extra))

	if effect_id in ["poison", "burn", "slow", "armor_break"] and int(target.get("hp", 0)) > 0:
		_refresh_status(target, effect_id, stage)
		var status_extra := extra.duplicate()
		status_extra["amount"] = strength
		status_extra["remaining_turns"] = _status_turns(effect_id, stage)
		effect_events.append(_move_effect_event(actor_side, target_side, effect_id, status_extra))


static func tick_barrier_owner_turn(
	fighter: Dictionary,
	rules_version: int,
	events: Array,
	side: String,
	slot: Variant = null
) -> void:
	if not should_apply_effects(rules_version, fighter):
		return
	var barrier: Variant = fighter.get("barrier", null)
	if typeof(barrier) != TYPE_DICTIONARY:
		return
	var barrier_dict: Dictionary = barrier
	if bool(barrier_dict.get("just_applied", false)):
		barrier_dict["just_applied"] = false
		fighter["barrier"] = barrier_dict
		return
	var remaining := int(_js_number_or_zero(barrier_dict.get("owner_turns_remaining", 0)))
	if remaining <= 0:
		fighter["barrier"] = null
		return
	barrier_dict["owner_turns_remaining"] = remaining - 1
	if int(barrier_dict["owner_turns_remaining"]) <= 0:
		fighter["barrier"] = null
		var event := {"type": "status_expired", "actor": side, "target": side, "effect_id": "barrier"}
		if slot != null:
			event["actor_slot"] = slot
		events.append(event)
	else:
		fighter["barrier"] = barrier_dict


static func tick_fighter_statuses(
	fighter: Dictionary,
	rules_version: int,
	events: Array,
	side: String,
	slot: Variant = null
) -> bool:
	if not effects_combat_active(rules_version):
		fighter["statuses"] = {}
		return false
	if int(fighter.get("hp", 0)) <= 0:
		return false
	var ko_from_tick := false
	var statuses: Dictionary = fighter.get("statuses", {})
	for effect_id in statuses.keys():
		var status: Dictionary = statuses[effect_id]
		if effect_id in ["poison", "burn"]:
			var pct := _js_number_or_zero(status.get("strength", 0))
			var tick := maxi(1, int(float(fighter.get("max_hp", 1)) * pct))
			var hp_before := int(fighter.get("hp", 0))
			fighter["hp"] = maxi(0, hp_before - tick)
			if hp_before > 0 and int(fighter["hp"]) == 0:
				ko_from_tick = true
			var tick_event := {
				"type": "status_tick",
				"actor": side,
				"target": side,
				"effect_id": effect_id,
				"amount": tick,
				"remaining_turns": int(status.get("remaining_turns", 0)),
				"target_hp": int(fighter["hp"]),
			}
			if slot != null:
				tick_event["actor_slot"] = slot
			events.append(tick_event)
		status["remaining_turns"] = int(status.get("remaining_turns", 0)) - 1
		if int(status["remaining_turns"]) <= 0:
			statuses.erase(effect_id)
			var expired := {
				"type": "status_expired",
				"actor": side,
				"target": side,
				"effect_id": effect_id,
			}
			if slot != null:
				expired["actor_slot"] = slot
			events.append(expired)
	fighter["statuses"] = statuses
	return ko_from_tick
