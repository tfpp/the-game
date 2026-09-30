class_name ItemCatalog
extends RefCounted
## Registry of every ItemDefinition, keyed by id. To add a new holdable item, drop a
## `.tres` under `items/` and add it to `DEFINITIONS` below; nothing else in this
## feature needs to change.

const DEFINITIONS: Array[ItemDefinition] = [
	preload("res://features/holdables/items/cigarette.tres"),
	preload("res://features/holdables/items/beer.tres"),
	preload("res://features/holdables/items/poke_bowl.tres"),
	preload("res://features/holdables/items/kebab.tres"),
	preload("res://features/holdables/items/upper_study_key.tres"),
	preload("res://features/holdables/items/pistol.tres"),
	preload("res://features/holdables/items/smg.tres"),
	preload("res://features/holdables/items/shotgun.tres"),
	preload("res://features/holdables/items/banana.tres"),
	preload("res://features/holdables/items/ball.tres"),
	preload("res://features/holdables/items/awp.tres"),
	preload("res://features/holdables/items/stolen_wallet.tres"),
	preload("res://features/holdables/items/watch.tres"),
	preload("res://features/holdables/items/jewelry.tres"),
	preload("res://features/holdables/items/electronics.tres"),
	preload("res://features/holdables/items/scrap.tres"),
	preload("res://features/holdables/items/cash_bundle.tres"),
]

## Remaining uses travel through the existing inventory/pickup ID transport.
const CONSUMABLE_STAGES := {
	"beer": ["beer:1", "beer:2", "beer"],
	"cigarette": ["cigarette:1", "cigarette:2", "cigarette"],
}


static func consumable_kind(id: String) -> String:
	for kind: String in CONSUMABLE_STAGES:
		if id in CONSUMABLE_STAGES[kind]:
			return kind
	return ""


static func uses_remaining(id: String) -> int:
	var kind := consumable_kind(id)
	return CONSUMABLE_STAGES[kind].find(id) + 1 if not kind.is_empty() else 0


static func after_use(id: String) -> String:
	var remaining := uses_remaining(id)
	return CONSUMABLE_STAGES[consumable_kind(id)][remaining - 2] if remaining > 1 else ""


## The definition for `id`, or null if unknown (e.g. an empty hand).
static func find(id: String) -> ItemDefinition:
	var kind := consumable_kind(id)
	if not kind.is_empty() and id != kind:
		var partial := find(kind).duplicate() as ItemDefinition
		partial.id = id
		var unit := "sips" if kind == "beer" else "puffs"
		partial.display_name += " (%d %s left)" % [uses_remaining(id), unit]
		return partial
	if not ClothingCatalog.slot(id).is_empty():
		var clothing := ItemDefinition.new()
		clothing.id = id
		clothing.display_name = ClothingCatalog.title(id)
		clothing.category = ItemDefinition.Category.CLOTHING
		clothing.ground_clearance = 0.06
		return clothing
	for item: ItemDefinition in DEFINITIONS:
		if item.id == id:
			return item
	return null


static func create_view(id: String) -> Node3D:
	if not ClothingCatalog.slot(id).is_empty():
		var clothing := ClothingModel.new()
		clothing.item_id = id
		return clothing
	var definition := find(id)
	return definition.view_scene.instantiate() as Node3D if definition != null else null
