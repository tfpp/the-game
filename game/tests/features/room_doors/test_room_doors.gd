extends GutTest
## Doors between streamed rooms (features/room_doors/). Runs single-process like
## test_garage_door.gd, so peer 1 is the server and direct calls resolve locally.

const FeatureScene := preload("res://features/room_doors/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _root: Node3D
var _lounge: StreamedRoom
var _cellar: StreamedRoom


func before_each() -> void:
	_root = FeatureScene.instantiate() as Node3D
	add_child_autofree(_root)
	_lounge = _root.get_node("Lounge") as StreamedRoom
	_cellar = _root.get_node("Cellar") as StreamedRoom


func _player_at(global_pos: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = global_pos
	player.net_position = global_pos
	add_child_autofree(player)
	return player


func _door(path: String) -> RoomDoor:
	return _root.get_node(path) as RoomDoor


func _marker(path: String) -> Vector3:
	return (_root.get_node(path) as Marker3D).global_position


func test_rooms_stay_unloaded_without_a_local_player() -> void:
	# A dedicated server has no local player, so it never builds room contents.
	await wait_physics_frames(2)
	assert_false(_lounge.is_loaded())
	assert_false(_cellar.is_loaded())


func test_room_loads_only_while_the_local_player_is_inside() -> void:
	var player := _player_at(_marker("Lounge/FromLobby"))
	await wait_physics_frames(2)
	assert_true(_lounge.is_loaded())
	assert_not_null(_lounge.get_node_or_null("Content/Floor"))
	assert_false(_cellar.is_loaded())
	player.global_position = _marker("Lobby/LobbyArrival")
	await wait_physics_frames(2)
	assert_false(_lounge.is_loaded())
	assert_null(_lounge.get_node_or_null("Content"))


func test_loaded_room_keeps_its_contents_near_the_edge() -> void:
	_player_at(_lounge.to_global(Vector3(0, 1, 0)))
	await wait_physics_frames(2)
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.global_position = _lounge.to_global(Vector3(0, 1, 5.5))
	await wait_physics_frames(2)
	assert_true(_lounge.is_loaded(), "within the unload margin")
	player.global_position = _lounge.to_global(Vector3(0, 1, 8))
	await wait_physics_frames(2)
	assert_false(_lounge.is_loaded())


func test_every_door_arrival_is_inside_its_room() -> void:
	assert_true(_lounge.contains(_marker("Lounge/FromLobby")))
	assert_true(_lounge.contains(_marker("Lounge/FromCellar")))
	assert_true(_cellar.contains(_marker("Cellar/FromLounge")))
	assert_false(_lounge.contains(_marker("Cellar/FromLounge"), _lounge.unload_margin))


func test_room_scenes_load_on_their_own() -> void:
	for room: StreamedRoom in [_lounge, _cellar]:
		assert_true(ResourceLoader.exists(room.room_scene), room.room_scene)
		assert_not_null(load(room.room_scene) as PackedScene)


func test_using_a_door_builds_the_destination_before_the_teleport() -> void:
	var player := _player_at(_marker("Lobby/LobbyArrival"))
	var door := _door("Lobby/Door")
	assert_true(door.can_use(player))
	assert_eq(door.destination_room(), _lounge)
	door.use()
	assert_true(_lounge.is_loaded(), "built on use, before the server answers")
	assert_true(player.net_position.is_equal_approx(_marker("Lounge/FromLobby")))
	await wait_physics_frames(2)
	assert_true(_lounge.is_loaded())


func test_destination_stays_built_while_the_teleport_is_in_flight() -> void:
	_player_at(_marker("Lobby/LobbyArrival"))
	_lounge.load_room(RoomDoor.ARRIVAL_HOLD_MSEC)
	await wait_physics_frames(2)
	assert_true(_lounge.is_loaded())


func test_doors_link_the_lobby_lounge_and_cellar_both_ways() -> void:
	var player := _player_at(_marker("Lobby/LobbyArrival"))
	var hops: Array[Array] = [
		["Lobby/Door", "Lounge/FromLobby"],
		["Lounge/CellarDoor", "Cellar/FromLounge"],
		["Cellar/LoungeDoor", "Lounge/FromCellar"],
		["Lounge/LobbyDoor", "Lobby/LobbyArrival"],
	]
	for hop: Array in hops:
		var door := _door(hop[0])
		player.global_position = door.global_position
		player.net_position = door.global_position
		door.request_enter()
		assert_true(player.net_position.is_equal_approx(_marker(hop[1])), hop[0])


func test_a_distant_player_cannot_use_a_door() -> void:
	var start := _marker("Lobby/LobbyArrival") + Vector3(20, 0, 0)
	var player := _player_at(start)
	_door("Lobby/Door").request_enter()
	assert_true(player.net_position.is_equal_approx(start))


func test_casino_side_door_is_not_streamed() -> void:
	assert_null(_door("Lounge/LobbyDoor").destination_room())
