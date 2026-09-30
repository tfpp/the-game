extends CompanionModel
## A moss green evening dress, a swept fringe and a gold brooch distinguish Celeste.

## ClothingCatalog color index of her dress (Moss).
const CELESTE_DRESS := 6


func _ready() -> void:
	build_evening_guest("Celeste", CELESTE_DRESS, 0, "swept")
	_part(
		"Brooch",
		torso_items,
		Vector3(-0.07, 0.5, CHEST_Z - 0.005),
		Vector3(0.04, 0.05, 0.02),
		_material(ClothingCatalog.COLORS[7])
	)
