class_name HumanoidTargetModel
extends Node3D
## Boxy shooting-gallery dummy assembled once per peer from a single shared unit
## cube, the same per-part scale trick features/frogs/frog_model.gd uses with a
## shared sphere. Every MeshInstance3D this builds becomes a separate gib when
## features/animal_effects/mesh_explosion.gd walks this node's children, so more
## parts means more debris flying apart on a kill.

var _cube := BoxMesh.new()


func build(jumpsuit_color: Color) -> void:
	var skin := _material(Color(0.85, 0.68, 0.54))
	var jumpsuit := _material(jumpsuit_color)
	var jumpsuit_dark := _material(jumpsuit_color.darkened(0.3))
	var shoe := _material(Color(0.08, 0.08, 0.08))
	var bullseye_white := _material(Color(0.92, 0.92, 0.88))
	var bullseye_red := _material(Color(0.75, 0.08, 0.08))
	_part("Head", Vector3(0, 1.64, 0), Vector3(0.26, 0.28, 0.26), skin)
	_part("Torso", Vector3(0, 1.24, 0), Vector3(0.42, 0.5, 0.24), jumpsuit)
	_part("BullseyeOuter", Vector3(0, 1.28, -0.125), Vector3(0.22, 0.22, 0.02), bullseye_white)
	_part("BullseyeInner", Vector3(0, 1.28, -0.135), Vector3(0.11, 0.11, 0.02), bullseye_red)
	_part("Pelvis", Vector3(0, 0.92, 0), Vector3(0.34, 0.22, 0.22), jumpsuit_dark)
	for side: float in [-1.0, 1.0]:
		_part("UpperArm", Vector3(side * 0.31, 1.34, 0), Vector3(0.14, 0.34, 0.14), jumpsuit)
		_part("LowerArm", Vector3(side * 0.31, 1.01, 0), Vector3(0.12, 0.32, 0.12), skin)
		_part("Hand", Vector3(side * 0.31, 0.81, 0), Vector3(0.11, 0.14, 0.11), skin)
		_part("UpperLeg", Vector3(side * 0.11, 0.62, 0), Vector3(0.17, 0.44, 0.17), jumpsuit_dark)
		_part("LowerLeg", Vector3(side * 0.11, 0.22, 0), Vector3(0.14, 0.4, 0.14), jumpsuit_dark)
		_part("Foot", Vector3(side * 0.11, 0.02, 0.05), Vector3(0.14, 0.08, 0.26), shoe)


func _part(label: String, at: Vector3, dimensions: Vector3, material: StandardMaterial3D) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = _cube
	part.material_override = material
	part.position = at
	part.scale = dimensions
	add_child(part)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
