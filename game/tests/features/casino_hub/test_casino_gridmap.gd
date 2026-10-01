extends GutTest
## Validate the saved prototype's GridMap collision, tile alignment and ramp joins.

const SCENE := preload("res://features/casino_hub/casino_gridmap.tscn")
const LIBRARY := preload("res://features/casino_hub/gridmap/casino_tiles.tres")
const Layout := preload("res://features/casino_hub/gridmap/layout.gd")
var _level: Node3D


func before_each() -> void:
	_level = SCENE.instantiate() as Node3D
	add_child_autofree(_level)
	await wait_physics_frames(4)


func test_library_contains_primitives_and_shared_authored_wood() -> void:
	assert_eq(LIBRARY.get_item_list().size(), 9)
	assert_true(LIBRARY.get_item_mesh(Layout.FLOOR) is BoxMesh)
	assert_true(LIBRARY.get_item_mesh(Layout.WALL) is BoxMesh)
	assert_true(LIBRARY.get_item_mesh(Layout.RAMP) is PrismMesh)
	assert_eq(LIBRARY.get_item_name(Layout.WOOD_WALL), "WoodWall")
	var wood := LIBRARY.get_item_mesh(Layout.WOOD_WALL)
	assert_eq(wood.get_faces().size() / 3, 104)
	assert_eq(wood.get_surface_count(), 1)
	assert_same(LIBRARY.get_item_mesh(Layout.PIT_WALL), wood)
	for id: int in LIBRARY.get_item_list():
		assert_eq(
			LIBRARY.get_item_shapes(id).size(),
			0 if id == 8 else 2,
			"Ceiling uses room slab collision"
		)


func test_saved_gridmaps_are_populated_and_use_one_library() -> void:
	for name: String in [
		"Floors", "WallsNorthSouth", "WallsEastWest", "ShopWallsNorthSouth", "ShopWallsEastWest"
	]:
		var grid := _level.get_node(name) as GridMap
		assert_same(grid.mesh_library, LIBRARY)
		assert_eq(grid.cell_size, Vector3(1, 0.25, 1))
		assert_false(grid.cell_center_y)
		assert_gt(grid.get_used_cells().size(), 0)
		assert_null(grid.get_script(), "Editor edits must persist without a runtime rebuild")
	assert_eq(_level.find_children("*", "CSGShape3D", true, false).size(), 0)


func test_pit_and_continuous_surrounding_floor_have_correct_elevations() -> void:
	for x: float in [-14.5, 0.5, 14.5]:
		for z: float in [-5.5, 0.5, 5.5]:
			_assert_floor(Vector3(x, 3, z), -1.5)
	for x: float in [-22.5, -16.5, 0.5, 16.5, 22.5]:
		for z: float in [-18.5, -13.5, 13.5, 18.5]:
			_assert_floor(Vector3(x, 3, z), 0.0)
	for x: float in [-16.5, 16.5]:
		_assert_floor(Vector3(x, 3, 0.5), 0.0)


func test_both_ramps_join_every_tile_without_vertical_steps() -> void:
	for direction: float in [-1.0, 1.0]:
		for x: float in [-2.5, 0.5, 2.5]:
			for distance: float in [5.99, 6.01, 6.5, 6.99, 7.01, 8.99, 9.01, 11.99, 12.01]:
				var expected := clampf((distance - 12.0) / 4.0, -1.5, 0.0)
				_assert_floor(Vector3(x, 3, direction * distance), expected)


func test_wall_faces_point_inward_and_collisions_close_all_corners() -> void:
	var walls := _level.get_node("WallsNorthSouth") as GridMap
	var sides := _level.get_node("WallsEastWest") as GridMap
	assert_eq(walls.get_used_cells_by_item(Layout.WALL).size(), 0)
	assert_eq(sides.get_used_cells_by_item(Layout.WALL).size(), 0)
	for grid: GridMap in [walls, sides]:
		for cell: Vector3i in grid.get_used_cells_by_item(Layout.WOOD_WALL):
			var facing := grid.get_cell_item_basis(cell) * Vector3.BACK
			var center := grid.map_to_local(cell)
			assert_lt(facing.dot(Vector3(center.x, 0, center.z)), 0.0)
	for x: float in [-23.5, 4.5, 23.5]:
		for direction: float in [-1.0, 1.0]:
			assert_false(
				_ray(Vector3(x, 1, direction * 18), Vector3(x, 1, direction * 21)).is_empty()
			)
	for z: float in [-19.5, 0.5, 19.5]:
		for direction: float in [-1.0, 1.0]:
			assert_false(
				_ray(Vector3(direction * 22, 1, z), Vector3(direction * 25, 1, z)).is_empty()
			)


func test_standing_player_clearance_on_ramps_and_promenade() -> void:
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	for direction: float in [-1.0, 1.0]:
		for distance: float in [5.5, 6.5, 7.5, 8.5, 9.5, 10.5, 11.5, 12.5, 14.5]:
			var floor_y := clampf((distance - 12.0) / 4.0, -1.5, 0.0)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = hull
			# Slight clearance accounts for a capsule touching the uphill side of a slope.
			query.transform.origin = Vector3(0.5, floor_y + 1.03, direction * distance)
			var hits := _level.get_world_3d().direct_space_state.intersect_shape(query)
			assert_true(hits.is_empty(), "Standing hull fits at %s" % query.transform.origin)


func test_existing_player_walks_both_ramps_in_both_directions() -> void:
	var previous_device := Controls.device
	var was_playing := Controls.playing
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	var player_scene := load("res://core/player/player.tscn") as PackedScene
	for direction: float in [-1.0, 1.0]:
		var player := player_scene.instantiate() as Player
		player.position = Vector3(0.5, -1.5 + 0.97, direction * 5.5)
		player.yaw = 0.0 if direction < 0 else PI
		_level.add_child(player)
		await wait_physics_frames(4)
		Input.action_press("move_forward")
		for frame: int in range(120):
			await wait_physics_frames(1)
			if absf(player.position.z) > 13.5:
				break
		Input.action_release("move_forward")
		await wait_physics_frames(12)
		assert_gt(absf(player.position.z), 13.5, "Player reaches the level-zero promenade")
		assert_true(player.is_on_floor(), "Player stays grounded after ascending")
		assert_almost_eq(player.position.y, player.movement.hull_height_m() / 2.0, 0.04)
		Input.action_press("move_back")
		for frame: int in range(140):
			await wait_physics_frames(1)
			if absf(player.position.z) < 5.0:
				break
		Input.action_release("move_back")
		await wait_physics_frames(12)
		assert_lt(absf(player.position.z), 5.0, "Player returns to the gaming pit")
		assert_true(player.is_on_floor(), "Player stays grounded after descending")
		assert_almost_eq(player.position.y, -1.5 + player.movement.hull_height_m() / 2.0, 0.04)
		player.free()
	Controls.pause()
	Controls.select_device(previous_device)
	if was_playing:
		Controls.start()


func _assert_floor(from: Vector3, expected_y: float) -> void:
	var hit := _ray(from, from - Vector3(0, 8, 0))
	assert_false(hit.is_empty(), "Floor exists at %s" % from)
	if not hit.is_empty():
		var point: Vector3 = hit["position"]
		assert_almost_eq(point.y, expected_y, 0.01, "Floor height at %s" % from)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _level.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to)
	)
