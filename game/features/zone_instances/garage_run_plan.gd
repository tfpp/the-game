class_name GarageRunPlan
extends RefCounted
## The server rolls this plan once and sends it as immutable instance spawn data.
## Point indices reference authored Marker3Ds in encounter_points.tscn.

const FLOOR_TIERS: Array[Array] = [
	[0, 0], [0, 0, 0], [0, 0, 2, 2], [0, 2, 2, 1], [2, 1, 1, 1, 1, 1]
]
const VALUABLES: Array[String] = ["scrap", "stolen_wallet", "electronics", "watch", "jewelry"]
const FLOOR_WEIGHTS: Array[Array] = [
	[12, 8, 2, .5, .1], [8, 7, 4, 1, .5], [5, 5, 6, 3, 1], [2, 3, 6, 6, 4], [1, 1, 3, 6, 10]
]


static func enemies(seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array[Dictionary] = []
	for depth: int in 5:
		# The top arrival lane stays empty: beginners meet only two distant brawlers.
		var pool: Array[int] = []
		pool.assign([2, 3, 4, 5] if depth == 0 else [0, 1, 2, 3, 4, 5])
		for tier: int in FLOOR_TIERS[depth]:
			var index := rng.randi_range(0, pool.size() - 1)
			result.append({"depth": depth, "point": pool[index], "tier": tier})
			pool.remove_at(index)
	return result


static func loot_table(depth: int) -> LootTable:
	var floor_index := clampi(depth, 0, 4)
	var table := LootTable.new()
	table.empty_chance = .35 - floor_index * .05
	table.min_items = 1 if floor_index < 3 else 2
	table.max_items = 2 if floor_index < 3 else 3
	table.item_ids = PackedStringArray(VALUABLES)
	table.weights = PackedFloat32Array(FLOOR_WEIGHTS[floor_index])
	return table
