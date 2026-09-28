class_name LootTable
extends Resource
## Data-driven loot roll: an empty chance, a min/max item count and weighted item
## ids from `ItemCatalog`. Save one as a `.tres` per kind of container.

## Chance (0-1) that a search turns up nothing at all.
@export_range(0.0, 1.0) var empty_chance := 0.25
@export var min_items := 1
@export var max_items := 2
## `ItemCatalog` ids, paired index-by-index with `weights`.
@export var item_ids := PackedStringArray()
@export var weights := PackedFloat32Array()


## Rolls a fresh list of item ids. Each item is drawn independently by weight.
func roll(rng: RandomNumberGenerator) -> PackedStringArray:
	var result := PackedStringArray()
	var total := _total_weight()
	if total <= 0.0 or rng.randf() < empty_chance:
		return result
	var count := rng.randi_range(maxi(min_items, 0), maxi(max_items, min_items))
	for _i in count:
		result.append(_pick(rng.randf() * total))
	return result


func _total_weight() -> float:
	var total := 0.0
	for i in mini(item_ids.size(), weights.size()):
		total += maxf(weights[i], 0.0)
	return total


func _pick(value: float) -> String:
	var last := ""
	for i in mini(item_ids.size(), weights.size()):
		if weights[i] <= 0.0:
			continue
		last = item_ids[i]
		value -= weights[i]
		if value < 0.0:
			return last
	return last
