extends Node3D
## One diner booth: a walnut table between two facing upholstered benches.
## Static scenery built from shared meshes; collision is mapped by the radar.

const WOOD := preload("res://features/casino_hub/materials/wood.tres")
const VELVET := preload("res://features/casino_hub/materials/velvet.tres")
const CREAM := preload("res://features/casino_hub/materials/cream.tres")

const TABLE_TOP := 0.77
const SEAT_TOP := 0.45
## Hips sit this far below a player's origin (BlockPlayerModel leg pivots).
const HIP_OFFSET := 0.17
## Standing up moves the player this far along x from the booth centre.
const STEP_OUT := 1.45
## Seat cushions, two per bench, in booth-local space (on the cushion surface).
const SEATS: Array[Vector3] = [
	Vector3(-0.4, SEAT_TOP, 0.8),
	Vector3(0.4, SEAT_TOP, 0.8),
	Vector3(-0.4, SEAT_TOP, -0.8),
	Vector3(0.4, SEAT_TOP, -0.8),
]
## name -> [centre, size, material, solid]
const PARTS := {
	"Table": [Vector3(0, TABLE_TOP - 0.03, 0), Vector3(1.6, 0.06, 0.8), 0, true],
	"Pedestal": [Vector3(0, 0.36, 0), Vector3(0.14, 0.72, 0.14), 0, false],
	"Foot": [Vector3(0, 0.02, 0), Vector3(0.6, 0.04, 0.5), 0, false],
	"Napkins": [Vector3(0.55, TABLE_TOP + 0.05, 0), Vector3(0.12, 0.1, 0.1), 2, false],
}


func _ready() -> void:
	for part: String in PARTS:
		var spec: Array = PARTS[part]
		_add(part, spec[0], spec[1], _material(spec[2]), spec[3])
	for side: float in [-1.0, 1.0]:
		var label := "North" if side < 0 else "South"
		_add(label + "Base", Vector3(0, 0.2, side * 0.8), Vector3(1.6, 0.4, 0.5), WOOD, true)
		_add(label + "Cushion", Vector3(0, 0.425, side * 0.8), Vector3(1.56, 0.05, 0.48), VELVET)
		_add(label + "Back", Vector3(0, 0.62, side * 1.11), Vector3(1.6, 1.24, 0.12), WOOD, true)
		_add(label + "Pad", Vector3(0, 0.82, side * 1.04), Vector3(1.5, 0.7, 0.04), VELVET)


func _material(index: int) -> Material:
	return [WOOD, VELVET, CREAM][index]


func _add(part: String, at: Vector3, size: Vector3, material: Material, solid := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var view := MeshInstance3D.new()
	view.name = part
	view.mesh = mesh
	view.material_override = material
	view.position = at
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	if not solid:
		return
	var body := StaticBody3D.new()
	body.name = part + "Body"
	body.add_to_group(&"radar_geometry")
	var box := BoxShape3D.new()
	box.size = size
	body.position = at
	if part == "Table":
		# The tabletop's collider reaches the floor so nobody walks under it.
		var top := at.y + size.y * 0.5
		box.size.y = top
		body.position.y = top * 0.5
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	add_child(body)
