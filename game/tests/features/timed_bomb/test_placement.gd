extends GutTest

const ROOM := preload("res://world/room.tscn")
const BOMB := preload("res://features/timed_bomb/feature.tscn")


func test_bomb_sits_on_actual_floor_outside_spawn_and_leaves_aisle_clear() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var room := ROOM.instantiate()
	world.add_child(room)
	var bomb := BOMB.instantiate()
	world.add_child(bomb)
	bomb.set_process(false)
	var spawn: Marker3D = room.get_node("Spawn")
	var floor_box: CSGBox3D = room.get_node("CasinoInterior/SunkenGamingFloor")
	assert_almost_eq(
		bomb.global_position.y, floor_box.global_position.y + floor_box.size.y / 2, 0.001
	)
	assert_eq(bomb.global_position, Vector3(-2.3, -1.5, 4.5))
	assert_lt(bomb.global_position.distance_to(spawn.global_position), 5.0)
	await wait_physics_frames(4)
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	for x: int in range(-3, 4):
		for z: int in range(-3, 4):
			var query := PhysicsShapeQueryParameters3D.new()
			query.collision_mask = 1
			query.shape = hull
			query.transform.origin = spawn.global_position + Vector3(x, 0, z)
			assert_true(world.get_world_3d().direct_space_state.intersect_shape(query).is_empty())
	for endpoints: Array in [
		[Vector3(0, -0.55, -5.9), Vector3(0, -0.55, 5.9)],
		[Vector3(0, -0.55, 5.9), Vector3(-10.5, -0.55, 5.9)],
		[Vector3(0, -0.55, 4.5), Vector3(-1.2, -0.55, 4.5)]
	]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.collision_mask = 1
		query.shape = hull
		query.transform.origin = endpoints[0]
		query.motion = endpoints[1] - endpoints[0]
		var result := world.get_world_3d().direct_space_state.cast_motion(query)
		assert_almost_eq(result[0], 1.0, 0.001)
