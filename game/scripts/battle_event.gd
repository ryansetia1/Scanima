class_name BattleEvent
extends RefCounted

const EFFECT_IDS: PackedStringArray = [
	"armor_pierce", "guard_break", "drain", "barrier",
	"poison", "burn", "slow", "armor_break",
]


static func normalized(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var event: Dictionary = value
	var event_type := str(event.get("type", ""))
	if event_type not in [
		"guard", "attack", "knockout", "timeout", "finished", "item",
		"move_effect", "status_tick", "status_expired",
	]:
		return {}
	if event_type in ["guard", "attack", "knockout"]:
		var actor := str(event.get("actor", ""))
		if actor != "player" and actor != "bot" and actor != "opponent":
			return {}
	if event_type == "attack":
		var target := str(event.get("target", ""))
		if target != "player" and target != "bot" and target != "opponent":
			return {}
		if int(event.get("damage", -1)) < 0 or int(event.get("target_hp", -1)) < 0:
			return {}
	if event_type == "move_effect":
		var actor := str(event.get("actor", ""))
		var target := str(event.get("target", ""))
		if actor != "player" and actor != "bot" and actor != "opponent":
			return {}
		if target != "player" and target != "bot" and target != "opponent":
			return {}
		var effect_id := str(event.get("effect_id", ""))
		if effect_id not in EFFECT_IDS:
			return {}
		if event.has("remaining_turns") and int(event.get("remaining_turns", -1)) < 0:
			return {}
		if event.has("amount") and float(event.get("amount", -1.0)) < 0.0:
			return {}
	if event_type == "status_tick":
		var actor := str(event.get("actor", ""))
		if actor != "player" and actor != "bot" and actor != "opponent":
			return {}
		var target := str(event.get("target", ""))
		if target != actor:
			return {}
		var effect_id := str(event.get("effect_id", ""))
		if effect_id not in EFFECT_IDS:
			return {}
		if int(event.get("amount", -1)) < 0 or int(event.get("target_hp", -1)) < 0:
			return {}
		if event.has("remaining_turns") and int(event.get("remaining_turns", -1)) < 0:
			return {}
	if event_type == "status_expired":
		var actor := str(event.get("actor", ""))
		if actor != "player" and actor != "bot" and actor != "opponent":
			return {}
		var target := str(event.get("target", ""))
		if target != actor:
			return {}
		var effect_id := str(event.get("effect_id", ""))
		if effect_id not in EFFECT_IDS:
			return {}
	return event.duplicate(true)


static func plate_text(event: Dictionary) -> String:
	var event_type := str(event.get("type", ""))
	var actor := str(event.get("actor", ""))
	var target := str(event.get("target", actor))
	var effect_id := str(event.get("effect_id", ""))
	match event_type:
		"move_effect":
			var key := (
				"BATTLE_EVENT_MOVE_EFFECT_BARRIER_HIT"
				if effect_id == "barrier" and event.has("target_hp")
				else "BATTLE_EVENT_MOVE_EFFECT_%s" % effect_id.to_upper()
			)
			var copy := TranslationServer.translate(key)
			if copy == key:
				return ""
			if effect_id in ["drain", "barrier"]:
				return copy % _side_label(actor)
			return copy % [_side_label(actor), _side_label(target)]
		"status_tick":
			var key := "BATTLE_EVENT_STATUS_TICK_%s" % effect_id.to_upper()
			var copy := TranslationServer.translate(key)
			if copy == key:
				return ""
			var amount := int(event.get("amount", 0))
			return copy % [_side_label(target), str(amount)]
		"status_expired":
			var key := "BATTLE_EVENT_STATUS_EXPIRED_%s" % effect_id.to_upper()
			var copy := TranslationServer.translate(key)
			if copy == key:
				return ""
			return copy % _side_label(target)
		_:
			return ""


static func _side_label(side: String) -> String:
	if side == "player":
		return TranslationServer.translate("BATTLE_SIDE_PLAYER")
	if side in ["bot", "opponent"]:
		return TranslationServer.translate("BATTLE_SIDE_OPPONENT")
	return side
