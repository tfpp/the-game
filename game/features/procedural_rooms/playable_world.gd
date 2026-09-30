extends Node3D
## Live-game instance of the deterministic kit, without preview players or global lighting.

const Layout := preload("res://features/procedural_rooms/world_layout.gd")
const CONCRETE := preload("res://features/procedural_rooms/materials/concrete.tres")
const ASPHALT := preload("res://features/procedural_rooms/materials/asphalt.tres")
@export var layout_seed := 73021


func _ready() -> void:
	var level := Layout.build(self, layout_seed)
	(level.get_node("Structure/Floor") as MeshInstance3D).material_override = CONCRETE
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(220, 220)
	ground.mesh = plane
	ground.material_override = ASPHALT
	ground.position = Vector3(0, -.12, 21)
	add_child(ground)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = plane.create_trimesh_shape()
	body.add_child(shape)
	ground.add_child(body)
