class_name ChickenAvatar
extends Node3D
## Small faceted rooster, floor-centred, front -Z. Cosmetic, not killable.
## Native mesh primitives carry UV1 and use existing low-resolution materials.

const GRAIN := preload("res://assets/casino_hub/textures/prop_grain.png")
var _cream: StandardMaterial3D
var _red: StandardMaterial3D
var _gold: StandardMaterial3D
var _black: StandardMaterial3D


func _ready() -> void:
	_cream = _material(Color("dbccb0"))
	_red = _material(Color("913e34"))
	_gold = _material(Color("ad853b"))
	_black = _material(Color("29211e"))
	_ellipsoid(Vector3(0, 0.65, 0), Vector3(0.48, 0.55, 0.65), _cream)
	_ellipsoid(Vector3(0, 0.96, -0.25), Vector3(0.27, 0.45, 0.28), _cream)
	_ellipsoid(Vector3(0, 1.15, -0.35), Vector3(0.32, 0.3, 0.32), _cream)
	_ellipsoid(Vector3(-0.24, 0.69, 0.03), Vector3(0.12, 0.35, 0.4), _cream)
	_ellipsoid(Vector3(0.24, 0.69, 0.03), Vector3(0.12, 0.35, 0.4), _cream)
	for x: float in [-0.095, 0.0, 0.095]:
		_ellipsoid(Vector3(x, 1.32, -0.35), Vector3(0.1, 0.19, 0.12), _red)
	_ellipsoid(Vector3(0, 1.01, -0.48), Vector3(0.12, 0.2, 0.1), _red)
	for x: float in [-0.16, 0.16]:
		_ellipsoid(Vector3(x, 1.19, -0.41), Vector3(0.055, 0.06, 0.06), _black)
	var beak := CylinderMesh.new()
	beak.top_radius = 0
	beak.bottom_radius = 0.1
	beak.height = 0.2
	beak.radial_segments = 4
	var tip := _mesh(beak, Vector3(0, 1.12, -0.57), _gold)
	tip.rotation.x = -PI / 2.0
	for x: float in [-0.14, 0.14]:
		var leg := CylinderMesh.new()
		leg.top_radius = 0.025
		leg.bottom_radius = 0.025
		leg.height = 0.3
		leg.radial_segments = 4
		_mesh(leg, Vector3(x, 0.19, 0), _gold)
		_ellipsoid(Vector3(x, 0.04, -0.09), Vector3(0.12, 0.08, 0.27), _gold)
	for x: float in [-0.13, 0.0, 0.13]:
		var tail := _ellipsoid(Vector3(x, 0.86, 0.35), Vector3(0.12, 0.55, 0.23), _black)
		tail.rotation.x = -0.7


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = GRAIN
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = 1.0
	return material


func _ellipsoid(pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 2
	var instance := _mesh(mesh, pos, material)
	instance.scale = size
	return instance


func _mesh(mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance
