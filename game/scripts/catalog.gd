class_name Catalog
extends RefCounted

const STACK_MAX := 999


static func is_food(row: Dictionary) -> bool:
	return str(row.get("use_type", row.get("kind", ""))) == "food"


static func is_energy(row: Dictionary) -> bool:
	return str(row.get("use_type", "")) == "energy"


static func is_battle(row: Dictionary) -> bool:
	return str(row.get("use_type", "")) == "battle"


static func quantity_of(inventory: Array, item_id: String) -> int:
	for value in inventory:
		var row: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
		if str(row.get("item_id", "")) == item_id:
			return maxi(0, int(row.get("quantity", 0)))
	return 0


static func owned_rows(catalog: Array, inventory: Array, kind: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for value in catalog:
		var item: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
		if str(item.get("use_type", "")) != kind:
			continue
		var qty := quantity_of(inventory, str(item.get("id", "")))
		if qty <= 0:
			continue
		var copy := item.duplicate(true)
		copy["quantity"] = qty
		rows.append(copy)
	return rows


static func feed_exp(hunger_before: float, restore: float) -> int:
	var after := minf(100.0, hunger_before + restore)
	return 3 if hunger_before < 40.0 and after >= 40.0 else 0
