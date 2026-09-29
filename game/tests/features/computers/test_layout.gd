extends GutTest


func test_computers_fit_arcade_floor_and_leave_arrival_and_cabinets_clear() -> void:
	var feature := preload("res://features/computers/feature.tscn").instantiate() as Node3D
	add_child_autofree(feature)
	var existing := preload("res://features/scumm_arcade/feature.tscn").instantiate()
	add_child_autofree(existing)
	var room := preload("res://features/scumm_arcade/room_interior.tscn").instantiate() as Node3D
	room.position = ScummArcadeRoom.ORIGIN
	add_child_autofree(room)
	await wait_physics_frames(3)
	for child: Node in feature.get_children():
		var computer := child as ArcadeComputer
		assert_true(ScummArcadeRoom.contains(computer.global_position))
		assert_almost_eq(computer.global_position.y, 0.0, 0.001)
		assert_gt(computer.global_position.distance_to(ScummArcadeRoom.ARRIVAL), 4.0)
		assert_almost_eq(computer.global_basis.z.dot(Vector3.FORWARD), 1.0, 0.001)
		var approach := computer.to_global(Vector3(0, 0.9, 2.0))
		var query := PhysicsRayQueryParameters3D.create(approach, approach - Vector3.UP * 2)
		var hit := computer.get_world_3d().direct_space_state.intersect_ray(query)
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq((hit.position as Vector3).y, 0.0, 0.02)
		for node: Node in existing.get_children():
			if node is ScummArcadeCabinet:
				assert_gt(computer.global_position.distance_to(node.global_position), 6.0)
	var query := PhysicsRayQueryParameters3D.create(Vector3(-80, 1, 4.7), Vector3(-80, 1, -2))
	assert_true(feature.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
