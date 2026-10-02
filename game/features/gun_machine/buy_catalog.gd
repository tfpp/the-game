class_name GunBuyCatalog
extends RefCounted
## Server-owned stock IDs; clients never submit stats or prices.

const CATEGORIES: Array[String] = [
	"Classic weapons",
	"Buckshot",
	"Rifles",
	"Low-caliber",
	"Rockets",
	"Grenades",
	"Plasma",
	"Ray Gun",
	"Classic ammunition"
]
const FIXED_PRICES := {"pistol": 3000, "smg": 7500, "shotgun": 9000, "awp": 15000}


static func entries(category: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if category == 0:
		for id: String in FIXED_PRICES:
			result.append(
				{"id": id, "name": ItemCatalog.find(id).display_name, "price": FIXED_PRICES[id]}
			)
	elif category >= 1 and category <= 6:
		var ammo := category - 1 as GunGenerator.AmmoType
		var profile := GunGenerator.profile(ammo)
		var max_barrels := mini(GunGenerator.MAX_BARRELS, int(profile["magazine_size"][1]))
		for barrels: int in range(1, max_barrels + 1):
			for automatic: int in 2:
				result.append(
					{
						"id": "generated:%d:%d:%d" % [ammo, barrels, automatic],
						"name": GunGenerator.display_name(ammo, barrels, automatic == 1),
						"price": GunMachine.PRICE_CENTS,
						"ammo": ammo,
						"barrels": barrels,
						"automatic": automatic
					}
				)
	elif category == 7:
		result.append(
			{
				"id": "ray",
				"name": GunGenerator.RAY_GUN_NAME,
				"price": GunMachine.PRICE_CENTS,
				"ammo": GunGenerator.AmmoType.RAY,
				"barrels": 1,
				"automatic": 0
			}
		)
	elif category == 8:
		for weapon: String in ItemCatalog.AMMO_PACKS:
			var pack: Dictionary = ItemCatalog.AMMO_PACKS[weapon]
			var id := ItemCatalog.ammo_id(weapon, pack["rounds"])
			result.append(
				{"id": id, "name": ItemCatalog.find(id).display_name, "price": pack["price"]}
			)
	return result


static func find(id: String) -> Dictionary:
	for category: int in CATEGORIES.size():
		for entry: Dictionary in entries(category):
			if entry["id"] == id:
				return entry
	return {}


static func stats(entry: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return GunGenerator.generate_selected(rng, entry["ammo"], entry["barrels"], entry["automatic"])
