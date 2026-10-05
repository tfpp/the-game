class_name WorkbenchRecipes
extends RefCounted
## Recipes mutate a detached inventory snapshot, never live items before a save.

const MATERIALS := ["scrap", "scrap", "electronics"]


static func candidate(snapshot: Dictionary, slot: int, expected: String) -> Dictionary:
	if slot < -1 or slot >= PlayerInventory.CAPACITY or not ItemCatalog.AMMO_PACKS.has(expected):
		return {}
	var next := snapshot.duplicate(true)
	var bag: Array = next.get("backpack", [])
	if bag.size() != PlayerInventory.CAPACITY:
		return {}
	var current: String = str(next.get("hand", "")) if slot == -1 else str(bag[slot])
	if current != expected:
		return {}
	for material: String in MATERIALS:
		var index := bag.find(material)
		if index < 0:
			return {}
		bag[index] = ""
	if slot == -1:
		next["hand"] = "tuned:" + expected
	else:
		bag[slot] = "tuned:" + expected
	return next
