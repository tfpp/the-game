class_name ItemCatalog
extends RefCounted
## Registry of every ItemDefinition, keyed by id. To add a new holdable item, drop a
## `.tres` under `items/` and add it to `DEFINITIONS` below; nothing else in this
## feature needs to change.

const DEFINITIONS: Array[ItemDefinition] = [
	preload("res://features/holdables/items/pistol.tres"),
	preload("res://features/holdables/items/smg.tres"),
	preload("res://features/holdables/items/shotgun.tres"),
	preload("res://features/holdables/items/banana.tres"),
	preload("res://features/holdables/items/ball.tres"),
]


## The definition for `id`, or null if unknown (e.g. an empty hand).
static func find(id: String) -> ItemDefinition:
	for item: ItemDefinition in DEFINITIONS:
		if item.id == id:
			return item
	return null
