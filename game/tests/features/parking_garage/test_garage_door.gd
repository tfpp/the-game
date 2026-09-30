extends GutTest
## The old garage's return door (features/parking_garage/garage_door.gd). The casino
## staff door into this mock-up was removed (issue #317); runs single-process like
## test_elevator_cab.gd, so peer 1 is the server and direct calls resolve locally.

const FeatureScene := preload("res://features/parking_garage/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _features: Node3D
var _root: Node3D
var _garage_door: GarageDoor
var _casino_arrival: Marker3D


func before_each() -> void:
	_features = Node3D.new()
	add_child_autofree(_features)
	var runs := Node3D.new()
	runs.name = "slum_runs"
	_features.add_child(runs)
	_casino_arrival = Marker3D.new()
	_casino_arrival.name = "CasinoArrival"
	_casino_arrival.position = Vector3(0, 1.2, 28)
	runs.add_child(_casino_arrival)
	_root = FeatureScene.instantiate() as Node3D
	_root.name = "parking_garage"
	_features.add_child(_root)
	_garage_door = _root.get_node("Garage/GarageDoor") as GarageDoor


func _player_at(global_pos: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = global_pos
	player.net_position = global_pos
	add_child_autofree(player)
	return player


func test_the_casino_staff_door_is_gone() -> void:
	assert_null(_root.get_node_or_null("Entrance"))
	for node: Node in get_tree().get_nodes_in_group(&"interactables"):
		var door := node as GarageDoor
		if door != null and _root.is_ancestor_of(door):
			assert_eq(door, _garage_door, "Only the return door remains")


func test_can_use_requires_being_near() -> void:
	var near := _player_at(_garage_door.global_position)
	var far := _player_at(_garage_door.global_position + Vector3(10, 0, 0))
	assert_true(_garage_door.can_use(near))
	assert_false(_garage_door.can_use(far))


func test_the_garage_door_returns_the_player_to_the_golden_crown() -> void:
	var player := _player_at(_garage_door.global_position)
	_garage_door.request_enter()
	assert_true(player.net_position.is_equal_approx(_casino_arrival.global_position))


func test_a_distant_player_cannot_trigger_the_door() -> void:
	var player := _player_at(_garage_door.global_position + Vector3(20, 0, 0))
	var start := player.net_position
	_garage_door.request_enter()
	assert_true(player.net_position.is_equal_approx(start))
