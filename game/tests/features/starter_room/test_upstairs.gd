extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _feature: Node3D
var _room: StreamedRoom


func before_each() -> void:
	_feature = FEATURE.instantiate()
	add_child_autofree(_feature)
	_room = _feature.get_node("Room")
	_room.load_room(60000)
	await wait_physics_frames(3)


func test_stair_seams_and_computer_approach_have_floor_and_standing_clearance() -> void:
	var space := _room.get_world_3d().direct_space_state
	for z: float in [.01, -.01, -1.99, -2.01, -3.99, -4.01]:
		var point := _room.to_global(Vector3(-6, 4.5, z))
		var ray := PhysicsRayQueryParameters3D.create(point, point - Vector3.UP * 5, 1)
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, clampf(-z * .625, 0, 2.5), .01)
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	for point: Vector3 in [Vector3(-6, 3.45, -5), Vector3(-4, 3.45, -6.6)]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = _room.to_global(point)
		assert_true(space.intersect_shape(query).is_empty(), "standing approach " + str(point))
		var ray := PhysicsRayQueryParameters3D.create(
			query.transform.origin, query.transform.origin - Vector3.UP * 2, 1
		)
		assert_almost_eq((space.intersect_ray(ray)["position"] as Vector3).y, 2.5, .01)
	var guard := PhysicsRayQueryParameters3D.create(
		_room.to_global(Vector3(-2.8, 3, -6)), _room.to_global(Vector3(-1.5, 3, -6)), 1
	)
	assert_false(space.intersect_ray(guard).is_empty())
	var terminal := _room.get_node("JobTerminal") as GarageJobTerminal
	assert_almost_eq(terminal.position.y, 3.5, .001)
	assert_true(_room.contains(_room.to_global(Vector3(-4, 4.4, -6.6))))
	assert_eq((_room.get_node("JobsDestination") as GpsDestination).position.y, 2.5)


func test_player_walks_upstairs_and_back_down_without_jumping() -> void:
	var previous_device := Controls.device
	var was_playing := Controls.playing
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	var player := PLAYER.instantiate() as Player
	player.position = _room.to_global(Vector3(-6, .98, .8))
	add_child_autofree(player)
	await wait_physics_frames(4)
	Input.action_press("move_forward")
	for frame: int in 180:
		await wait_physics_frames(1)
		if _room.to_local(player.global_position).z < -4.6:
			break
	Input.action_release("move_forward")
	await wait_physics_frames(12)
	assert_lt(_room.to_local(player.global_position).z, -4.6)
	assert_true(player.is_on_floor())
	assert_almost_eq(player.global_position.y, 2.5 + player.movement.hull_height_m() / 2, .04)
	Input.action_press("move_back")
	for frame: int in 180:
		await wait_physics_frames(1)
		if _room.to_local(player.global_position).z > .5:
			break
	Input.action_release("move_back")
	await wait_physics_frames(12)
	assert_gt(_room.to_local(player.global_position).z, .5)
	assert_true(player.is_on_floor())
	assert_almost_eq(player.global_position.y, player.movement.hull_height_m() / 2, .04)
	Controls.pause()
	Controls.select_device(previous_device)
	if was_playing:
		Controls.start()
