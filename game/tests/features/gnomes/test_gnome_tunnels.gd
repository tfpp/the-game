extends GutTest

const Feature := preload("res://features/gnomes/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
var _feature: Node3D


func before_each() -> void:
	_feature = Feature.instantiate()
	add_child_autofree(_feature)


func _player(pos: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.position = pos
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_all_sixteen_holes_link_both_ways_and_preload_floor() -> void:
	var player := _player(Vector3.ZERO)
	var index := 0
	for side: String in ["North", "South", "East", "West"]:
		for number in 4:
			var hole := _feature.get_node("Train%s/Hole%d" % [side, number]) as Node3D
			var entry := hole.get_node("Enter") as RoomDoor
			player.global_position = entry.global_position
			player.net_position = player.global_position
			entry.use()
			assert_true(_feature.tunnel.is_loaded())
			assert_not_null(_feature.tunnel.get_node("Content/Floor"))
			var arrival := _feature.tunnel.get_node("Arrival%d" % index) as Marker3D
			assert_eq(player.net_position, arrival.global_position)
			var exit := _feature.tunnel.get_node("Exit%d" % index) as RoomDoor
			player.global_position = exit.global_position
			player.net_position = player.global_position
			exit.request_enter()
			assert_eq(
				player.net_position, (hole.get_node("SurfaceArrival") as Marker3D).global_position
			)
			index += 1
	assert_eq(index, 16)


func test_distant_requests_and_unknown_players_cannot_enter() -> void:
	var entry := _feature.get_node("TrainNorth/Hole0/Enter") as RoomDoor
	entry.request_enter()
	assert_false(_feature.tunnel.is_loaded())
	var player := _player(Vector3(0, 10, 0))
	entry.request_enter()
	assert_eq(player.net_position, Vector3(0, 10, 0))


func test_speed_is_local_fourfold_and_restored_after_exit_and_removal() -> void:
	var player := _player(Vector3(0, 1.1, -1000))
	var original := player.movement.max_speed
	player.movement = player.movement.duplicate() as MovementConfig
	player.movement.jump_speed = 400
	_feature._physics_process(0.0)
	assert_eq(player.movement.max_speed, original * 4)
	_feature._physics_process(0.0)
	assert_eq(player.movement.max_speed, original * 4, "does not stack")
	assert_eq(player.movement.jump_speed, 400.0)
	player.global_position = Vector3.ZERO
	_feature._physics_process(0.0)
	assert_eq(player.movement.max_speed, original)
	player.global_position = Vector3(0, 1.1, -1000)
	_feature._physics_process(0.0)
	remove_child(_feature)
	assert_eq(player.movement.max_speed, original)
	_feature.free()


func test_tunnel_stays_unloaded_without_local_player() -> void:
	await wait_physics_frames(2)
	assert_false(_feature.tunnel.is_loaded())
