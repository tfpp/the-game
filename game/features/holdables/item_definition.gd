class_name ItemDefinition
extends Resource
## Data describing one kind of holdable item: a weapon, food, or throwable prop.
## New items are added by dropping a `.tres` in `items/` and listing it in
## `ItemCatalog`, no script or code changes needed.

## What happens when the primary action is used while this item is held.
enum Category {
	WEAPON,  ## Fires; stays in hand.
	FOOD,  ## Eaten once; removed from hand.
	PROP,  ## Thrown; removed from hand and becomes a world pickup where it lands.
}

@export var id := ""
@export var display_name := ""
@export var category: Category = Category.PROP
## Purely visual: instanced under the pickup and under whichever hand holds it.
@export var view_scene: PackedScene
