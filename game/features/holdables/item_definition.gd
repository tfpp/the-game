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
	CLOTHING,  ## Equipped in a shirt or pants slot.
	KEY,  ## Stored in the inventory key ring; cannot be thrown, eaten or dropped.
}

@export var id := ""
@export var display_name := ""
@export var category: Category = Category.PROP
## Purely visual: instanced under the pickup and under whichever hand holds it.
@export var view_scene: PackedScene
## Height of the model origin above a floor when dropped.
@export var ground_clearance := 0.10
## Camera-relative primary grip. Long stocks need more room behind the grip.
@export var first_person_offset := Vector3(0.22, -0.23, -0.43)

## Kilograms-ish. Thrown or dropped items bounce less the heavier they are (see
## throw_math.gd's `bounce_height`); heavy weapons barely bounce at all.
@export var weight := 1.0
## WEAPON only: health removed from whoever a hitscan hit lands on.
@export var damage := 0.0
## WEAPON only: minimum seconds between shots.
@export var fire_cooldown_s := 0.25
## WEAPON only: hitscans fired per shot (a shotgun fires several at once).
@export var pellet_count := 1
## WEAPON only: random aim jitter applied to each pellet, in degrees.
@export var spread_degrees := 0.0
