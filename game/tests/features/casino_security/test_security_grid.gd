extends GutTest
## The guards' walkable grid, probed from real collision: floors and steps, blocked
## furniture, routes around obstacles and onto lower floors, and players ignored.

var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_box(Vector3(0, -0.125, 0), Vector3(20, 0.25, 20))
	# A wall across the middle with a gap at the east end.
	_box(Vector3(-2, 1.25, 0), Vector3(16, 2.5, 0.3))
	# A table: solid, 0.8 m high.
	_box(Vector3(-5, 0.4, 5), Vector3(1.6, 0.8, 1.0))
	await wait_physics_frames(2)


func _box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_root.add_child(body)
	return body


func _grid() -> SecurityGrid:
	var grid := SecurityGrid.new(AABB(Vector3(-10, -1, -10), Vector3(20, 4, 20)))
	grid.build_all(_root.get_world_3d().direct_space_state)
	return grid


func test_floor_furniture_and_walls_are_probed_from_collision() -> void:
	var grid := _grid()
	assert_true(grid.is_ready())
	assert_eq(grid.cell_count(), 40 * 40)
	assert_true(grid.is_walkable(Vector3(3, 0, 3)))
	assert_almost_eq(grid.floor_at(Vector3(3, 0, 3), NAN), 0.0, 0.01)
	assert_false(grid.is_walkable(Vector3(0, 0, 0)), "wall")
	assert_almost_eq(grid.floor_at(Vector3(-5, 0, 5), NAN), 0.8, 0.01, "table top is found")
	assert_eq(grid.floor_at(Vector3(0, 0, 0), -7.0), -7.0, "fallback off the walkable grid")
	assert_eq(grid.index_at(Vector3(50, 0, 0)), -1)


func test_build_steps_spread_the_work_over_frames() -> void:
	var grid := SecurityGrid.new(AABB(Vector3(-10, -1, -10), Vector3(20, 4, 20)))
	var space := _root.get_world_3d().direct_space_state
	var steps := 0
	while not grid.is_ready():
		grid.build_step(space, 200, [])
		steps += 1
	assert_eq(steps, 16, "1600 probes then 1600 links, 200 per step")
	assert_true(grid.is_walkable(Vector3(3, 0, 3)))


func test_route_walks_around_the_wall_through_the_gap() -> void:
	var grid := _grid()
	var route := grid.route(Vector3(-6, 0, -4), Vector3(-6, 0, 4), 0.5)
	assert_false(route.is_empty())
	var furthest_east := -INF
	var previous := Vector3(-6, 0, -4)
	for point: Vector3 in route:
		furthest_east = maxf(furthest_east, point.x)
		assert_true(grid.is_walkable(point))
		previous = point
	assert_gt(furthest_east, 6.0, "detours through the gap at the east end")
	assert_lt(Vector2(previous.x + 6, previous.z - 4).length(), 0.75, "ends near the target")


func test_route_ends_beside_furniture_someone_stands_on() -> void:
	var grid := _grid()
	var on_table := Vector3(-5, 0.8, 5)
	var route := grid.route(Vector3(-5, 0, 8), on_table, SecurityRules.GRAB_RANGE - 0.1, 1.6)
	assert_false(route.is_empty())
	var last := route[route.size() - 1]
	assert_almost_eq(last.y, 0.0, 0.01, "stays on the floor")
	assert_true(SecurityRules.can_grab(last, on_table), "close enough to lift them off")


func test_no_route_into_a_sealed_box() -> void:
	_box(Vector3(6, 1.25, -6), Vector3(4, 2.5, 0.3))
	_box(Vector3(6, 1.25, -2), Vector3(4, 2.5, 0.3))
	_box(Vector3(4, 1.25, -4), Vector3(0.3, 2.5, 4))
	_box(Vector3(8, 1.25, -4), Vector3(0.3, 2.5, 4))
	await wait_physics_frames(2)
	var grid := _grid()
	assert_true(grid.is_walkable(Vector3(6, 0, -4)), "floor inside is fine")
	assert_true(grid.route(Vector3(-6, 0, -4), Vector3(6, 0, -4), 0.5).is_empty())


func test_players_standing_around_do_not_block_the_grid() -> void:
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.position = Vector3(3, 0.95, 3)
	add_child_autofree(player)
	player.set_physics_process(false)
	await wait_physics_frames(2)
	var grid := SecurityGrid.new(AABB(Vector3(-10, -1, -10), Vector3(20, 4, 20)))
	grid.build_all(_root.get_world_3d().direct_space_state, [player.get_rid()])
	assert_true(grid.is_walkable(Vector3(3, 0, 3)))
