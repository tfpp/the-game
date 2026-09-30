extends SalonGuestModel
## Rusty Hogg, the pawnbroker: bald, with a big rust-red beard, a brown work shirt
## and a leather apron. Stands behind the pawn counter on the salon guests' idle pose.

const NAME := "Rusty Hogg"
const RUST_HAIR := 3
const LOOK := {
	"skin": 0, "hair": "bald", "hair_color": RUST_HAIR, "shirt": 4, "pants": 9, "tie": -1
}


func _ready() -> void:
	dress_up(LOOK)
	var beard := _material(PlayerAppearance.HAIR_COLORS[RUST_HAIR])
	_part("Beard", head_items, Vector3(0, 0.08, FACE_Z + 0.03), Vector3(0.17, 0.12, 0.08), beard)
	_part(
		"Moustache", head_items, Vector3(0, 0.155, FACE_Z + 0.005), Vector3(0.1, 0.02, 0.015), beard
	)
	var leather := _material(Color(0.28, 0.17, 0.1))
	_part(
		"Apron", torso_items, Vector3(0, 0.3, CHEST_Z - 0.005), Vector3(0.26, 0.4, 0.012), leather
	)
	_name_tag(NAME)
	_update(UPDATE_S)
