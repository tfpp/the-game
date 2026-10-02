extends GutTest

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _room: Node3D


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	await wait_physics_frames(4)


func test_stairs_floor_joins_balcony_with_headroom_and_guard_collision() -> void:
	var area := _room.get_node("Casino/MariachiBalcony")
	assert_eq((area.get_node("Stairs") as GridMap).get_used_cells_by_item(15).size(), 16)
	assert_eq((area.get_node("StairRails") as GridMap).get_used_cells_by_item(16).size(), 8)
	for z: float in [-12.01, -11.99, -10.01, -9.99, -8.01, -7.99, -6.01, -5.99, -4.01, -3.99]:
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(-28.5, 7, z), Vector3(-28.5, -1, z), 1
		)
		var hit := _room.get_world_3d().direct_space_state.intersect_ray(ray)
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, clampf((z + 12) * 0.625, 0, 5), 0.01)
	var ceiling := PhysicsRayQueryParameters3D.create(Vector3(-25, 7, 0), Vector3(-25, 10, 0), 1)
	assert_almost_eq(
		(_room.get_world_3d().direct_space_state.intersect_ray(ceiling)["position"] as Vector3).y,
		8.75,
		0.01
	)
	var guard := PhysicsRayQueryParameters3D.create(Vector3(-19, 5.5, 0), Vector3(-17, 5.5, 0), 1)
	assert_false(_room.get_world_3d().direct_space_state.intersect_ray(guard).is_empty())
	assert_true(area.has_node("BarCounter"))
	assert_eq((area.get_node("BalconyBar") as GpsDestination).label, "Mariachi Balcony Bar")


func test_player_walks_stairs_up_and_down_without_jumping() -> void:
	var previous_device := Controls.device
	var was_playing := Controls.playing
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	var player := PLAYER.instantiate() as Player
	player.position = Vector3(-28.5, 0.98, -12.8)
	player.yaw = PI
	_room.add_child(player)
	await wait_physics_frames(4)
	Input.action_press("move_forward")
	for frame: int in 180:
		await wait_physics_frames(1)
		if player.position.z > -3.5:
			break
	Input.action_release("move_forward")
	await wait_physics_frames(12)
	assert_gt(player.position.z, -3.5)
	assert_true(player.is_on_floor())
	assert_almost_eq(player.position.y, 5 + player.movement.hull_height_m() / 2, 0.04)
	Input.action_press("move_back")
	for frame: int in 180:
		await wait_physics_frames(1)
		if player.position.z < -12.5:
			break
	Input.action_release("move_back")
	await wait_physics_frames(12)
	assert_lt(player.position.z, -12.5)
	assert_true(player.is_on_floor())
	assert_almost_eq(player.position.y, player.movement.hull_height_m() / 2, 0.04)
	Controls.pause()
	Controls.select_device(previous_device)
	if was_playing:
		Controls.start()
