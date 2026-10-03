class_name VipRules
extends RefCounted
## Pure rules for the Mirror Club. Currency uses the existing wallet's cents.

const ENTRY_CENTS := 200_000
const LUCK_S := 300
const BOOST_S := 600
const COOLDOWN_S := 1800
const DAY_S := 86400
const WAGERS: Array[int] = [10_000, 25_000, 50_000]
const COLLECTION: Array[String] = [
	"Amber coupe", "Velvet martini", "Midnight tumbler", "Golden Crown goblet"
]
const DRINKS := {"luck": "Luck Cocktail", "golden": "Golden Hour", "velvet": "Velvet Reserve"}
const DRINK_ITEMS := {"luck": "luck_cocktail", "golden": "golden_hour", "velvet": "velvet_reserve"}


static func empty_record() -> Dictionary:
	return {
		"discovered": false,
		"visits": 0,
		"luck": 0,
		"golden": 0,
		"velvet": 0,
		"luck_ready": 0,
		"golden_ready": 0,
		"velvet_ready": 0,
		"gift_ready": 0,
		"xp": 0,
		"hosts": [],
		"symbol": false,
		"played": false,
		"mission": false,
		"collection": [],
		"wardrobe": [],
		"transaction": {}
	}


static func next_day(now: int) -> int:
	return (now / DAY_S + 1) * DAY_S


static func mission_ready(row: Dictionary) -> bool:
	return row["hosts"].size() == 3 and row["symbol"] and row["played"] and not row["mission"]


## Thirty of 125 equiprobable tickets win with the cocktail; five without it.
## This is exactly 6x the base 4% chance, and still allows losses.
static func reels(ticket: int, lucky: bool) -> Array[int]:
	var bounded := clampi(ticket, 0, 124)
	if bounded < (30 if lucky else 5):
		var symbol := bounded % 5
		return [symbol, symbol, symbol]
	return SlotSpinCycle.result_for_ticket(bounded, 0)


static func seconds(row: Dictionary, field: String, now: int) -> int:
	return maxi(0, int(row.get(field, 0)) - now)


static func rare_chance(row: Dictionary, now: int) -> float:
	var chance := 0.20 if seconds(row, "velvet", now) > 0 else 0.05
	return minf(1.0, chance * (6.0 if seconds(row, "luck", now) > 0 else 1.0))


static func progress(row: Dictionary, amount: int, now: int) -> void:
	row["xp"] = int(row["xp"]) + amount * (2 if seconds(row, "golden", now) > 0 else 1)


static func title_for(row: Dictionary) -> String:
	return "House Favorite" if row["mission"] else "Behind the Mirror"
