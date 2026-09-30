class_name CompanionModel
extends PatronModel
## Vivienne: the patron avatar in a red evening dress with long hair, plus a seated
## pose for her bar stool. Faces -Z like every PatronModel.

const NAME := "Vivienne"
## ClothingCatalog color index of her dress (Red).
const DRESS := 11
## Hip joint height when perched on the stool (0.74 m seat top plus the thigh).
const SEATED_HIP := 0.81


func build_vivienne() -> void:
	build_evening_guest(NAME, DRESS, 0, "long")


## Shared dress and hair silhouette: the girl body wearing one ClothingCatalog color
## top and bottom, with `hair` / `hair_color` from PlayerAppearance.
func build_evening_guest(guest_name: String, dress: int, hair_color: int, hair: String) -> void:
	dress_up(
		{
			"skin": 1,
			"hair": hair,
			"hair_color": hair_color,
			"shirt": dress,
			"pants": dress,
			"tie": -1,
			"girl": true,
		}
	)
	_name_tag(guest_name)
