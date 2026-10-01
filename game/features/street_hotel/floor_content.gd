extends Node3D
## Only this floor's static geometry/furniture and cheap exterior view are loaded.

const SPEC := preload("res://features/street_hotel/spec.gd")
const PROXY := preload("res://assets/street_hotel/street_lod.scn")
const FLOORS: Array[String] = [
	"res://assets/street_hotel/floors/floor_01.scn",
	"res://assets/street_hotel/floors/floor_02.scn",
	"res://assets/street_hotel/floors/floor_03.scn",
	"res://assets/street_hotel/floors/floor_04.scn",
	"res://assets/street_hotel/floors/floor_05.scn",
	"res://assets/street_hotel/floors/floor_06.scn",
	"res://assets/street_hotel/floors/floor_07.scn",
	"res://assets/street_hotel/floors/floor_08.scn",
	"res://assets/street_hotel/floors/floor_09.scn",
	"res://assets/street_hotel/floors/floor_10.scn",
]


func _ready() -> void:
	var index: int = get_parent().get_meta("floor_index", 0)
	var scene := load(FLOORS[index]) as PackedScene
	add_child(scene.instantiate())
	var view := PROXY.instantiate() as Node3D
	view.position.y = -index * SPEC.STOREY
	add_child(view)
