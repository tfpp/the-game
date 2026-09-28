class_name FrogModel
extends Node3D
## Lightweight low-poly frog assembled once per peer from shared primitive meshes.
## Materials belong to this frog, so recoloring one never recolors its neighbours.

var _size := 1.0
var _clock := 0.0
var _hind_legs: Array[Node3D] = []
var _sphere := SphereMesh.new()


func build(color: Color, size_factor: float) -> void:
	_size = size_factor
	scale = Vector3.ONE * _size
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	var skin := _material(color)
	var dark := _material(color.darkened(0.35))
	var belly := _material(color.lightened(0.65))
	var gold := _material(Color(0.9, 0.72, 0.23))
	var pupil := _material(Color(0.025, 0.035, 0.02))
	var shine := _material(Color(0.97, 0.98, 0.86))
	_part(self, "Torso", Vector3(0, 0.25, 0.06), Vector3(0.55, 0.36, 0.65), skin)
	_part(self, "Belly", Vector3(0, 0.15, -0.05), Vector3(0.46, 0.18, 0.51), belly)
	_part(self, "Head", Vector3(0, 0.3, -0.22), Vector3(0.61, 0.28, 0.38), skin)
	_part(self, "Mouth", Vector3(0, 0.235, -0.384), Vector3(0.42, 0.025, 0.032), dark)
	for side: float in [-1.0, 1.0]:
		_part(self, "EyeSocket", Vector3(side * 0.2, 0.43, -0.24), Vector3(0.22, 0.24, 0.23), skin)
		_part(self, "Iris", Vector3(side * 0.2, 0.455, -0.337), Vector3(0.15, 0.145, 0.07), gold)
		_part(self, "Pupil", Vector3(side * 0.2, 0.455, -0.371), Vector3(0.12, 0.045, 0.02), pupil)
		_part(self, "Glint", Vector3(side * 0.2 - 0.023, 0.485, -0.38), Vector3.ONE * 0.025, shine)
		_part(self, "Nostril", Vector3(side * 0.085, 0.34, -0.398), Vector3.ONE * 0.026, dark)
		var leg := Node3D.new()
		leg.name = "HindLeg"
		leg.position = Vector3(side * 0.27, 0.16, 0.22)
		add_child(leg)
		_hind_legs.append(leg)
		_part(leg, "Haunch", Vector3.ZERO, Vector3(0.3, 0.28, 0.36), skin)
		_part(leg, "Shin", Vector3(side * 0.04, -0.07, 0.08), Vector3(0.17, 0.13, 0.34), dark)
		_foot(leg, Vector3(side * 0.065, -0.115, -0.075), skin)
		_part(self, "Foreleg", Vector3(side * 0.25, 0.13, -0.23), Vector3(0.1, 0.21, 0.12), skin)
		_foot(self, Vector3(side * 0.27, 0.035, -0.3), skin)
		for spot: int in 3:
			_part(
				self,
				"Spot",
				Vector3(side * 0.13, 0.42 - spot * 0.017, 0.01 + spot * 0.09),
				Vector3(0.075, 0.022, 0.09),
				dark
			)


func animate(phase: float, delta: float) -> void:
	_clock += delta
	var stretch := sin(clampf(phase, 0.0, 1.0) * PI) if phase >= 0.0 else 0.0
	var breath := sin(_clock * 3.0) * 0.015 if phase < 0.0 else 0.0
	var target := Vector3(1.0 - stretch * 0.08, 1.0 + stretch * 0.13 + breath, 1.0 + stretch * 0.08)
	scale = scale.lerp(target * _size, 1.0 - exp(-20.0 * delta))
	rotation.x = lerp_angle(rotation.x, -stretch * 0.12, 1.0 - exp(-18.0 * delta))
	for leg: Node3D in _hind_legs:
		leg.rotation.x = stretch * 0.65


func _foot(parent: Node3D, at: Vector3, material: StandardMaterial3D) -> void:
	_part(parent, "WebbedFoot", at, Vector3(0.18, 0.055, 0.21), material)
	for toe: int in 3:
		_part(
			parent,
			"Toe",
			at + Vector3((toe - 1) * 0.065, 0, -0.095),
			Vector3(0.055, 0.04, 0.1),
			material
		)


func _part(
	parent: Node3D, label: String, at: Vector3, dimensions: Vector3, material: StandardMaterial3D
) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = _sphere
	part.material_override = material
	part.position = at
	part.scale = dimensions
	parent.add_child(part)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
