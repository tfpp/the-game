class_name ScummArcadeRoom
extends Node3D
## Uses shared streamed rooms and doors; cabinet RPC paths remain always present.

const ORIGIN := Vector3(-80, 0, 0)
const BOUNDS := AABB(Vector3(-87.5, -0.5, -6), Vector3(15, 5, 12))
const ENTRANCE := Vector3(-8.6, -1.5, 8.5)
const ARRIVAL := Vector3(-80, 0.95, 3.5)


static func contains(point: Vector3) -> bool:
	return BOUNDS.has_point(point)


func _ready() -> void:
	var interior := StreamedRoom.new()
	interior.name = "Interior"
	interior.position = ORIGIN
	interior.bounds = AABB(BOUNDS.position - ORIGIN, BOUNDS.size)
	interior.unload_margin = 0
	interior.room_scene = "res://features/scumm_arcade/room_interior.tscn"
	add_child(interior)
	var arrival := Marker3D.new()
	arrival.name = "Arrival"
	arrival.position = ARRIVAL - ORIGIN
	interior.add_child(arrival)
	var casino := Marker3D.new()
	casino.name = "CasinoArrival"
	casino.position = ENTRANCE + Vector3(0, 0.95, 2)
	add_child(casino)
	_door(
		"Entrance",
		ENTRANCE,
		^"../Interior/Arrival",
		"Enter the adventure arcade",
		"ADVENTURE ARCADE"
	)
	_door("Exit", ORIGIN + Vector3(0, 0, 5), ^"../CasinoArrival", "Return to the casino", "CASINO")


func _door(title: String, at: Vector3, destination: NodePath, prompt: String, text: String) -> void:
	var door := RoomDoor.new()
	door.name = title
	door.position = at + Vector3(0, 1.1, 0)
	door.size = Vector3(1.5, 2.2, 0.15)
	door.use_collision = true
	door.material = preload("res://features/casino_hub/materials/wood.tres")
	door.destination = destination
	door.door_label = prompt
	add_child(door)
	var sign := Label3D.new()
	sign.text = text
	sign.position = Vector3(0, 1.45, 0)
	sign.font_size = 28
	sign.pixel_size = 0.006
	sign.modulate = Color("f3d394")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	door.add_child(sign)
