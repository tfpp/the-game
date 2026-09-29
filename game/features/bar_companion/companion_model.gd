class_name CompanionModel
extends PatronModel
## Vivienne: the jointed patron body restyled with a red evening dress and long hair,
## plus a seated pose for her bar stool. Faces -Z like every PatronModel.

const NAME := "Vivienne"
const DRESS := Color(0.62, 0.05, 0.1)
const SKIN := Color(0.9, 0.72, 0.6)
const HAIR_COLOR := Color(0.12, 0.06, 0.04)
## Hip height when perched on the stool (seat top plus the pelvis).
const SEATED_HIP := 0.82


func build_vivienne() -> void:
	build_evening_guest(NAME, DRESS, HAIR_COLOR)


## Shared dress and hair silhouette; existing Vivienne callers keep their appearance.
func build_evening_guest(guest_name: String, dress_color: Color, hair_color: Color) -> void:
	build(0)
	var dress := _material(dress_color)
	var skin := _material(SKIN)
	var hair := _material(hair_color)
	for part: String in ["Chest", "Pelvis", "UpperArmL", "UpperArmR", "ThighL", "ThighR"]:
		_mesh(part).material_override = dress
	for part: String in ["Face", "Neck", "Nose", "HandL", "HandR", "ForearmL", "ForearmR"]:
		_mesh(part).material_override = skin
	for part: String in ["ShinL", "ShinR"]:
		_mesh(part).material_override = skin
		_mesh(part).scale.x = 0.1
	for part: String in ["Hair", "HairBack"]:
		_mesh(part).material_override = hair
	_mesh("Tie").visible = false
	_mesh("Shirt").visible = false
	_mesh("Chest").scale.x = 0.36
	var head := find_child("Head", true, false) as Node3D
	# Wide thighs read as a knee-length skirt and bend with her when she sits.
	for part: String in ["ThighL", "ThighR"]:
		_mesh(part).scale = Vector3(0.2, 0.46, 0.2)
	_part("LongHair", head, Vector3(0, 0.02, 0.1), Vector3(0.28, 0.4, 0.08), hair)
	_part("Lips", head, Vector3(0, 0.06, -0.126), Vector3(0.07, 0.02, 0.01), _material(DRESS))
	_name_tag(guest_name)


## Poses her sitting: thighs forward along -Z, shins hanging to the stool's footrest.
func sit(idle: float) -> void:
	pose(0.0, 0.0, 0.0, 0.0, idle)
	(find_child("Hips", true, false) as Node3D).position.y = SEATED_HIP
	for side: String in ["L", "R"]:
		(find_child("Leg" + side, true, false) as Node3D).rotation.x = PI / 2
		(find_child("Knee" + side, true, false) as Node3D).rotation.x = -PI / 2


func _mesh(part: String) -> MeshInstance3D:
	return find_child(part, true, false) as MeshInstance3D
