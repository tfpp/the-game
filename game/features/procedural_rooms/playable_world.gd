extends Node3D
## Live-game instance of the deterministic kit, without preview players or global lighting.

const Layout := preload("res://features/procedural_rooms/world_layout.gd")
const Atmosphere := preload("res://features/procedural_rooms/garage_atmosphere.gd")
const ASPHALT := preload("res://features/procedural_rooms/materials/asphalt.tres")
## Weathered live-garage surfaces replace the developer measurement grids.
const SURFACES := {
	"Floor": preload("res://features/procedural_rooms/materials/garage_floor.tres"),
	"Wall": preload("res://features/procedural_rooms/materials/garage_wall.tres"),
	"Roof": preload("res://features/procedural_rooms/materials/garage_ceiling.tres"),
	"Grey": preload("res://features/procedural_rooms/materials/garage_rail.tres"),
}
@export var layout_seed := 73021


func _ready() -> void:
	var level := Layout.build(self, layout_seed, [], true)
	for surface: String in SURFACES:
		var mesh := level.get_node_or_null("Structure/" + surface) as MeshInstance3D
		if mesh != null:
			mesh.material_override = SURFACES[surface]
	var atmosphere := Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
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
