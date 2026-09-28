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
	preload("res://features/holdables/items/awp.tres"),
]


## The definition for `id`, or null if unknown (e.g. an empty hand).
static func find(id: String) -> ItemDefinition:
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
