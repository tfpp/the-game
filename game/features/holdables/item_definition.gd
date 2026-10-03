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

## NONE is for equipment and monetary loot, not a valuable tier.
enum Rarity { NONE, COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["", "Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS: Array[Color] = [
	Color.WHITE, Color("c5c7c9"), Color("88c999"), Color("8ebcf0"), Color("c7a0e8"), Color("e5bf72")
]

@export var rarity: Rarity = Rarity.NONE
@export var id := ""
@export var display_name := ""
@export var category: Category = Category.PROP
## Purely visual: instanced under the pickup and under whichever hand holds it.
@export var view_scene: PackedScene
## Direction from model centre toward the orthographic inventory thumbnail camera.
@export var icon_view_direction := Vector3(1, .9, 1)
## Height of the model origin above a floor when dropped.
@export var ground_clearance := 0.10
## Camera-relative primary grip. Long stocks need more room behind the grip.
@export var first_person_offset := Vector3(0.22, -0.23, -0.43)

## Kilograms-ish. Thrown or dropped items bounce less the heavier they are (see
## throw_math.gd's `bounce_height`); heavy weapons barely bounce at all.
@export var weight := 1.0
## Cash paid by the Golden Crown's fence for valuables brought back from a slum.
## Zero keeps ordinary equipment, clothing and keys out of the sale inventory.
@export var sale_value_cents := 0
## WEAPON only: health removed from whoever a hitscan hit lands on.
@export var damage := 0.0
## WEAPON only: minimum seconds between shots.
@export var fire_cooldown_s := 0.25
## WEAPON only: hitscans fired per shot (a shotgun fires several at once).
@export var pellet_count := 1
## WEAPON only: random aim jitter applied to each pellet, in degrees.
@export var spread_degrees := 0.0
## FOOD only: health restored when eaten, capped at features/combat's maximum.
@export var heal_amount := 0.0


func rarity_name() -> String:
	return RARITY_NAMES[rarity]


func rarity_color() -> Color:
	return RARITY_COLORS[rarity]


## Prices come from the same integer cents used by the pawn sale.
func loot_details() -> String:
	if sale_value_cents <= 0:
		return ""
	var tier := rarity_name() if rarity != Rarity.NONE else "Cash"
	return "%s · $%d.%02d" % [tier, sale_value_cents / 100, sale_value_cents % 100]
