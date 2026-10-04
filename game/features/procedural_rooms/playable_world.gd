extends RenderZone
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
	render_layer = 20
	render_bounds = Atmosphere.BOUNDS
	# The sunken casino floor is at -1.5 m; its furniture origins must not
	# be mistaken for basement actors. B1's ceiling is below -2.3 m.
	render_bounds.size.y = 20.0
	var level := Layout.build(self, layout_seed, [], true)
	var lift := level.get_node("Lift") as ProceduralMovingLift
	lift.dev_only = true
	lift._update_doors()
	for node: Node in level.find_children("*", "", true, false):
		if node is GpsDestination:
			(node as GpsDestination).dev_only = true
	for surface: String in SURFACES:
		var mesh := level.get_node_or_null("Structure/" + surface) as MeshInstance3D
		if mesh != null:
			mesh.material_override = SURFACES[surface]
	# The cab and casino landing straddle the boundary and must remain visible
	# from both sides. Shared networking paths are unchanged.
	for path: String in ["Lift/Cab", "CasinoGate", "CasinoCall"]:
		level.get_node(path).add_to_group(&"render_zone_shared")
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
