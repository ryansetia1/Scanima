class_name BattleEvent
extends RefCounted


static func normalized(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var event: Dictionary = value
	var event_type := str(event.get("type", ""))
	if event_type not in ["guard", "attack", "knockout", "timeout", "finished", "item"]:
		return {}
	if event_type in ["guard", "attack", "knockout"]:
		var actor := str(event.get("actor", ""))
		if actor != "player" and actor != "bot":
			return {}
	if event_type == "attack":
		var target := str(event.get("target", ""))
		if target != "player" and target != "bot":
			return {}
		if int(event.get("damage", -1)) < 0 or int(event.get("target_hp", -1)) < 0:
			return {}
	return event.duplicate(true)
