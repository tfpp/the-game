extends GutTest
## Server-authoritative teleport for the garage's two doors
## (features/parking_garage/garage_door.gd). Runs single-process like
## test_elevator_cab.gd, so peer 1 is the server and direct calls resolve locally.

const FeatureScene := preload("res://features/parking_garage/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _root: Node3D
var _entrance_door: GarageDoor
var _garage_door: GarageDoor
var _entrance_arrival: Marker3D
var _garage_arrival: Marker3D


func before_each() -> void:
	_root = FeatureScene.instantiate() as Node3D
	add_child_autofree(_root)
	_entrance_door = _root.get_node("Entrance/Door") as GarageDoor
	_garage_door = _root.get_node("Garage/GarageDoor") as GarageDoor
	_entrance_arrival = _root.get_node("Entrance/EntranceArrival") as Marker3D
	_garage_arrival = _root.get_node("Garage/GarageArrival") as Marker3D


func _player_at(global_pos: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = global_pos
	player.net_position = global_pos
	add_child_autofree(player)
	return player


func test_can_use_requires_being_near() -> void:
	var near := _player_at(_entrance_door.global_position)
	var far := _player_at(_entrance_door.global_position + Vector3(10, 0, 0))
	assert_true(_entrance_door.can_use(near))
	assert_false(_entrance_door.can_use(far))


func test_entering_the_casino_side_door_sends_the_player_to_the_garage_arrival() -> void:
	var player := _player_at(_entrance_door.global_position)
	_entrance_door.request_enter()
	assert_true(player.net_position.is_equal_approx(_garage_arrival.global_position))


func test_entering_the_garage_side_door_sends_the_player_back_to_the_entrance() -> void:
	var player := _player_at(_garage_door.global_position)
	_garage_door.request_enter()
	assert_true(player.net_position.is_equal_approx(_entrance_arrival.global_position))


func test_a_distant_player_cannot_trigger_the_door() -> void:
	var player := _player_at(_entrance_door.global_position + Vector3(20, 0, 0))
	var start := player.net_position
	_entrance_door.request_enter()
	assert_true(player.net_position.is_equal_approx(start))
