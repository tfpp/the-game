class_name ClothingModel
extends Node3D
## Small folded clothes for world pickups and dropped inventory items.

var item_id := "shirt:2"


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = ClothingCatalog.color(item_id)
	material.roughness = 0.95
	var trim := StandardMaterial3D.new()
	trim.albedo_color = material.albedo_color.lightened(0.2)
	if ClothingCatalog.slot(item_id) == "shirt":
		_box(Vector3.ZERO, Vector3(0.48, 0.09, 0.48), material)
		_box(Vector3(-0.28, 0, -0.12), Vector3(0.14, 0.08, 0.22), material)
		_box(Vector3(0.28, 0, -0.12), Vector3(0.14, 0.08, 0.22), material)
		_box(Vector3(0, 0.05, -0.19), Vector3(0.16, 0.018, 0.09), trim)
	else:
		_box(Vector3(0, 0, -0.15), Vector3(0.43, 0.10, 0.22), material)
		for side: float in [-1.0, 1.0]:
			_box(Vector3(side * 0.115, 0, 0.10), Vector3(0.20, 0.10, 0.36), material)
		_box(Vector3(0, 0.06, -0.22), Vector3(0.44, 0.02, 0.06), trim)


func _box(at: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	add_child(mesh)
