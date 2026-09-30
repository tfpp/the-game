extends CompanionModel
## A dark green evening dress, opera gloves and a swept fringe distinguish Celeste.


func _ready() -> void:
	build_evening_guest("Celeste", Color(0.08, 0.23, 0.19), Color(0.04, 0.035, 0.05))
	var gloves := _material(Color(0.055, 0.05, 0.065))
	for part: String in ["ForearmL", "ForearmR", "HandL", "HandR"]:
		_mesh(part).material_override = gloves
	var head := find_child("Head", true, false) as Node3D
	_part(
		"Fringe",
		head,
		Vector3(-0.06, 0.22, -0.13),
		Vector3(0.17, 0.17, 0.045),
		_mesh("Hair").material_override
	)
	var torso := find_child("Torso", true, false) as Node3D
	_part(
		"Brooch",
		torso,
		Vector3(-0.1, 0.42, -0.13),
		Vector3(0.05, 0.06, 0.025),
		_material(Color(0.65, 0.5, 0.23))
	)
