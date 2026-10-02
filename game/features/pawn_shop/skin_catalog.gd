class_name PrawnSkinCatalog
extends RefCounted
## Cosmetic IDs are separate from ItemCatalog: no weapon definitions/stats change.

const TIERS: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const COLORS: Array[Color] = [
	Color("a5aaa6"), Color("82ad75"), Color("759cce"), Color("b482c2"), Color("d4b060")
]
const DEFAULT_ODDS: Array[int] = [6000, 2500, 1000, 400, 100]
const CRATES := {
	"harbour":
	{
		"name": "Harbour Prawn Pot",
		"price": 500,
		"skins": ["brine", "kelp", "reef", "bisque", "crown"]
	},
	"night":
	{"name": "Midnight Trawler", "price": 1000, "skins": ["silt", "net", "tide", "pearl", "king"]},
}
# name, compatible classic weapon, tier, paint, shell accent
const SKINS := {
	"brine": ["Brine Line", "pistol", 0, Color("777e78"), Color("c3ae8a")],
	"kelp": ["Kelp Cocktail", "smg", 1, Color("384e3b"), Color("90a269")],
	"reef": ["Reef Runner", "shotgun", 2, Color("354f61"), Color("82b1b2")],
	"bisque": ["Bisque Business", "awp", 3, Color("733e38"), Color("d4a183")],
	"crown": ["Crown Prawn", "pistol", 4, Color("56412b"), Color("d3b56e")],
	"silt": ["Silt & Pepper", "shotgun", 0, Color("57554d"), Color("afa89a")],
	"net": ["Net Profit", "pistol", 1, Color("374d47"), Color("9ca578")],
	"tide": ["Tide Rider", "awp", 2, Color("354760"), Color("809bb9")],
	"pearl": ["Pearl Diver", "smg", 3, Color("57516c"), Color("b7a5b7")],
	"king": ["King of the Trawler", "awp", 4, Color("5b3632"), Color("cfad65")],
}


static func valid_odds(odds: Array[int]) -> bool:
	if odds.size() != 5:
		return false
	var total := 0
	for value: int in odds:
		if value < 0 or value > 10000:
			return false
		total += value
	return total == 10000


static func valid_refunds(refunds: Array[int]) -> bool:
	if refunds.size() != 5:
		return false
	for value: int in refunds:
		if value <= 0 or value > 10000000:
			return false
	return true


static func roll(crate: String, odds: Array[int], ticket: int) -> String:
	if not CRATES.has(crate) or not valid_odds(odds) or ticket < 0 or ticket >= 10000:
		return ""
	var cumulative := 0
	for tier: int in odds.size():
		cumulative += odds[tier]
		if ticket < cumulative:
			return CRATES[crate]["skins"][tier]
	return ""


static func empty_document() -> Dictionary:
	return {"crates": {}, "skins": {}, "equipped": {}}


static func clean(document: Dictionary) -> Dictionary:
	var result := empty_document()
	for field: String in ["crates", "skins"]:
		var values: Variant = document.get(field, {})
		if not values is Dictionary:
			continue
		var catalog: Dictionary = CRATES if field == "crates" else SKINS
		for id: String in catalog:
			var count: Variant = values.get(id, 0)
			if (count is int or count is float) and count >= 1 and count <= 999999:
				result[field][id] = int(count)
	var equipped: Variant = document.get("equipped", {})
	if equipped is Dictionary:
		for weapon: String in ItemCatalog.AMMO_PACKS:
			var id: String = str(equipped.get(weapon, ""))
			if SKINS.has(id) and SKINS[id][1] == weapon and result["skins"].get(id, 0) > 0:
				result["equipped"][weapon] = id
	return result


## Pure validated mutation, used online and offline before the atomic commit.
static func change(
	document: Dictionary,
	action: String,
	id: String,
	odds: Array[int],
	refunds: Array[int],
	ticket: int = 0
) -> Dictionary:
	var next := clean(document)
	var delta := 0
	var reward := ""
	match action:
		"buy":
			if not CRATES.has(id) or next["crates"].get(id, 0) >= 999999:
				return {}
			next["crates"][id] = int(next["crates"].get(id, 0)) + 1
			delta = -int(CRATES[id]["price"])
		"open":
			if next["crates"].get(id, 0) <= 0:
				return {}
			reward = roll(id, odds, ticket)
			if reward.is_empty() or next["skins"].get(reward, 0) >= 999999:
				return {}
			next["crates"][id] -= 1
			next["skins"][reward] = int(next["skins"].get(reward, 0)) + 1
		"equip":
			if not SKINS.has(id) or next["skins"].get(id, 0) < 1:
				return {}
			next["equipped"][SKINS[id][1]] = id
		"unequip":
			if not ItemCatalog.AMMO_PACKS.has(id):
				return {}
			next["equipped"].erase(id)
		"exchange":
			if not SKINS.has(id) or next["skins"].get(id, 0) < 2 or refunds.size() != 5:
				return {}
			delta = refunds[SKINS[id][2]]
			if delta <= 0 or delta > 10000000:
				return {}
			next["skins"][id] -= 1
		_:
			return {}
	return {"document": next, "delta": delta, "reward": reward}
