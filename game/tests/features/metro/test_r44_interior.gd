extends GutTest
## Check real collision with the same capsule dimensions as the game player.

const TRAIN := preload("res://features/metro/r44_five_car_set.tscn")
var _train: Node3D
var _doors: AnimationPlayer


func before_each() -> void:
	_train = TRAIN.instantiate() as Node3D
	add_child_autofree(_train)
	_doors = _train.get_node("Doors") as AnimationPlayer
	await wait_physics_frames(4)


func _blocked(car: Node3D, point: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = car.to_global(point)
	query.collision_mask = 1
	return not _train.get_world_3d().direct_space_state.intersect_shape(query).is_empty()


func _pose(clip: String, time: float) -> void:
	_doors.play(clip)
	_doors.seek(time, true)
	_doors.pause()
	await wait_physics_frames(3)


func test_all_forty_entrances_block_when_closed_and_clear_when_open() -> void:
	for opening: bool in [false, true, false]:
		await _pose("open_all" if opening else "close_all", 1.2)
		for index: int in 5:
			var car := _train.get_node("Car%02d" % (index + 1)) as Node3D
			for side: float in [-1.0, 1.0]:
				for z: float in [-7.5, -2.5, 2.5, 7.5]:
					assert_eq(
						_blocked(car, Vector3(side * 1.43, 2.1244, z)),
						not opening,
						"Car %d entrance %.1f / %.1f" % [index, side, z]
					)
					if opening:
						for x: float in [0.0, 0.5, 1.0, 1.75, 2.0]:
							assert_false(_blocked(car, Vector3(side * x, 2.1244, z)))


func test_aisles_have_continuous_floor_and_seats_block_passage() -> void:
	for index: int in 5:
		var car := _train.get_node("Car%02d" % (index + 1)) as Node3D
		var grid := car.get_node("CabinStructure") as GridMap
		assert_eq(grid.get_used_cells_by_item(0).size(), 11)
		for z: float in [-10.0, -8.99, -7.0, -5.01, -5.0, -4.99, 0.0, 5.0, 9.0, 10.0]:
			assert_false(_blocked(car, Vector3(0, 2.1244, z)), "Aisle is clear")
			var ray := PhysicsRayQueryParameters3D.create(
				car.to_global(Vector3(0, 1.5, z)), car.to_global(Vector3(0, 1, z)), 1
			)
			var hit := _train.get_world_3d().direct_space_state.intersect_ray(ray)
			assert_false(hit.is_empty(), "Floor is continuous")
			if not hit.is_empty():
				assert_almost_eq((hit.position as Vector3).y, 1.2, 0.001)
		assert_true(_blocked(car, Vector3(1.0, 2.1244, 0)))
	assert_eq(_train.find_children("*", "CSGShape3D", true, false).size(), 0)


func test_side_selection_accounts_for_the_reversed_rear_car() -> void:
	await _pose("open_left", 1.2)
	for index: int in 5:
		var car := _train.get_node("Car%02d" % (index + 1)) as Node3D
		for side: float in [-1.0, 1.0]:
			var point := Vector3(side * 1.43, 2.1244, 2.5)
			assert_eq(_blocked(car, point), car.to_global(point).x > 0)
	await _pose("close_left", 1.2)
	await _pose("open_right", 1.2)
	for index: int in 5:
		var car := _train.get_node("Car%02d" % (index + 1)) as Node3D
		for side: float in [-1.0, 1.0]:
			var point := Vector3(side * 1.43, 2.1244, 2.5)
			assert_eq(_blocked(car, point), car.to_global(point).x < 0)


func test_animation_moves_eighty_physical_leaves_through_pockets() -> void:
	var leaves := _train.find_children("Door*", "AnimatableBody3D", true, false)
	assert_eq(leaves.size(), 80)
	var closed: Dictionary[Node, Vector3] = {}
	for leaf: Node3D in leaves:
		closed[leaf] = leaf.position
	await _pose("open_all", 0.6)
	for leaf: Node3D in leaves:
		assert_almost_eq(absf(leaf.position.z - closed[leaf].z), 0.37, 0.001)
		assert_eq(leaf.position.x, closed[leaf].x)
	_doors.play("open_all")
	await wait_physics_frames(85)
	assert_false(_doors.is_playing())
	for leaf: Node3D in leaves:
		assert_almost_eq(absf(leaf.position.z - closed[leaf].z), 0.74, 0.001)


func test_existing_player_can_board_after_doors_open() -> void:
	var previous_device := Controls.device
	var was_playing := Controls.playing
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	var platform := GridMap.new()
	platform.mesh_library = load("res://features/metro/cabin_tiles.tres") as MeshLibrary
	platform.cell_size = Vector3(1, 1, 1)
	platform.cell_center_x = false
	platform.cell_center_y = false
	platform.cell_center_z = false
	platform.position = Vector3(3.04, 0, 53.22)
	platform.set_cell_item(Vector3i.ZERO, 0)
	_train.add_child(platform)
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.position = Vector3(3.1, 2.13, 53.22)
	player.yaw = PI / 2
	_train.add_child(player)
	await wait_physics_frames(4)
	Input.action_press("move_forward")
	await wait_physics_frames(45)
	Input.action_release("move_forward")
	assert_gt(player.position.x, 1.8, "Closed door physically stops the existing controller")
	await _pose("open_all", 1.2)
	Input.action_press("move_forward")
	for frame: int in 50:
		await wait_physics_frames(1)
		if player.position.x < 0.3:
			break
	Input.action_release("move_forward")
	await wait_physics_frames(8)
	assert_lt(player.position.x, 0.3, "Player crosses the threshold into the vestibule")
	assert_true(player.is_on_floor())
	assert_almost_eq(player.position.y, 1.2 + player.movement.hull_height_m() / 2, 0.04)
	Controls.pause()
	Controls.select_device(previous_device)
	if was_playing:
		Controls.start()
