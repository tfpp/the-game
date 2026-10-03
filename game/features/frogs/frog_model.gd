class_name FrogModel
extends Node3D
## Low-poly frog with one torso draw, one batched detail draw, and one draw per
## animated hind leg. Part colors live in mesh vertices so each frog can keep
## its own palette without submitting dozens of individual sphere meshes.

const VISIBILITY_RANGE_M := 35.0
const SPHERE_SOURCE := preload("res://assets/frogs/models/sphere_source.tres")

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
	var details: Array[Dictionary] = []
	_queue_part(details, Vector3(0, 0.15, -0.05), Vector3(0.46, 0.18, 0.51), belly)
	_queue_part(details, Vector3(0, 0.3, -0.22), Vector3(0.61, 0.28, 0.38), skin)
	_queue_part(details, Vector3(0, 0.235, -0.384), Vector3(0.42, 0.025, 0.032), dark)
	for side: float in [-1.0, 1.0]:
		_queue_part(details, Vector3(side * 0.2, 0.43, -0.24), Vector3(0.22, 0.24, 0.23), skin)
		_queue_part(details, Vector3(side * 0.2, 0.455, -0.337), Vector3(0.15, 0.145, 0.07), gold)
		_queue_part(details, Vector3(side * 0.2, 0.455, -0.371), Vector3(0.12, 0.045, 0.02), pupil)
		_queue_part(details, Vector3(side * 0.2 - 0.023, 0.485, -0.38), Vector3.ONE * 0.025, shine)
		_queue_part(details, Vector3(side * 0.085, 0.34, -0.398), Vector3.ONE * 0.026, dark)
		var leg := Node3D.new()
		leg.name = "HindLeg"
		leg.position = Vector3(side * 0.27, 0.16, 0.22)
		add_child(leg)
		_hind_legs.append(leg)
		var leg_parts: Array[Dictionary] = []
		_queue_part(leg_parts, Vector3.ZERO, Vector3(0.3, 0.28, 0.36), skin)
		_queue_part(leg_parts, Vector3(side * 0.04, -0.07, 0.08), Vector3(0.17, 0.13, 0.34), dark)
		_foot(leg_parts, Vector3(side * 0.065, -0.115, -0.075), skin)
		_batched_part(leg, "Visual", leg_parts)
		_queue_part(details, Vector3(side * 0.25, 0.13, -0.23), Vector3(0.1, 0.21, 0.12), skin)
		_foot(details, Vector3(side * 0.27, 0.035, -0.3), skin)
		for spot: int in 3:
			_queue_part(
				details,
				Vector3(side * 0.13, 0.42 - spot * 0.017, 0.01 + spot * 0.09),
				Vector3(0.075, 0.022, 0.09),
				dark
			)
	_batched_part(self, "Details", details)


func animate(phase: float, delta: float) -> void:
	_clock += delta
	var stretch := sin(clampf(phase, 0.0, 1.0) * PI) if phase >= 0.0 else 0.0
	var breath := sin(_clock * 3.0) * 0.015 if phase < 0.0 else 0.0
	var target := Vector3(1.0 - stretch * 0.08, 1.0 + stretch * 0.13 + breath, 1.0 + stretch * 0.08)
	scale = scale.lerp(target * _size, 1.0 - exp(-20.0 * delta))
	rotation.x = lerp_angle(rotation.x, -stretch * 0.12, 1.0 - exp(-18.0 * delta))
	for leg: Node3D in _hind_legs:
		leg.rotation.x = stretch * 0.65


func _foot(parts: Array[Dictionary], at: Vector3, material: StandardMaterial3D) -> void:
	_queue_part(parts, at, Vector3(0.18, 0.055, 0.21), material)
	for toe: int in 3:
		_queue_part(
			parts, at + Vector3((toe - 1) * 0.065, 0, -0.095), Vector3(0.055, 0.04, 0.1), material
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
	part.visibility_range_end = VISIBILITY_RANGE_M
	parent.add_child(part)


func _queue_part(
	parts: Array[Dictionary], at: Vector3, dimensions: Vector3, material: StandardMaterial3D
) -> void:
	parts.append({"at": at, "size": dimensions, "color": material.albedo_color})


func _batched_part(parent: Node3D, label: String, parts: Array[Dictionary]) -> void:
	var source: Array = SPHERE_SOURCE.arrays
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Dictionary in parts:
		var at: Vector3 = part["at"]
		var dimensions: Vector3 = part["size"]
		var color: Color = part["color"]
		for index: int in indices:
			surface.set_color(color)
			surface.set_normal((normals[index] / dimensions).normalized())
			surface.add_vertex(at + vertices[index] * dimensions)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.8
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = surface.commit()
	visual.material_override = material
	visual.visibility_range_end = VISIBILITY_RANGE_M
	parent.add_child(visual)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
