extends GutTest


func _fixture() -> Dictionary:
	var game := Node3D.new()
	game.name = "Game"
	add_child_autofree(game)
	var world := Node3D.new()
	world.name = "Room"
	game.add_child(world)
	var wall := MeshInstance3D.new()
	wall.mesh = BoxMesh.new()
	(wall.mesh as BoxMesh).size = Vector3(40, 8, 40)
	world.add_child(wall)
	var features := Node3D.new()
	features.name = "Features"
	game.add_child(features)
	var room := StreamedRoom.new()
	room.name = "Hotel"
	room.position = Vector3(0, 0, -600)
	room.bounds = AABB(Vector3(-10, -1, -10), Vector3(20, 6, 20))
	room.room_scene = "res://features/room_doors/rooms/lounge.tscn"
	features.add_child(room)
	var area := GpsDestination.new()
	area.name = "Garage"
	area.area = AABB(Vector3(-20, -1, 580), Vector3(40, 12, 40))
	features.add_child(area)
	var visibility := RoomVisibility.new()
	features.add_child(visibility)
	return {"room": room, "area": area, "visibility": visibility}


func test_server_selects_streamed_and_area_rooms_from_authored_bounds() -> void:
	var fixture := _fixture()
	var room := fixture["room"] as StreamedRoom
	var area := fixture["area"] as GpsDestination
	var visibility := fixture["visibility"] as RoomVisibility
	assert_eq(visibility._room_at(Vector3(0, 1, -600))["path"], visibility.get_path_to(room))
	assert_eq(visibility._room_at(Vector3(0, 1, 600))["path"], visibility.get_path_to(area))
	assert_eq(visibility._room_at(Vector3.ZERO)["path"], NodePath(""))
	assert_eq(visibility._casino_bounds.size, Vector3(40, 8, 40))


func test_assignment_loads_only_the_selected_room() -> void:
	var fixture := _fixture()
	var room := fixture["room"] as StreamedRoom
	var visibility := fixture["visibility"] as RoomVisibility
	visibility.assign_room(room.get_path(), room.global_bounds())
	assert_true(room.is_loaded())
	visibility.assign_room(NodePath(""), visibility._casino_bounds)
	assert_false(room.is_loaded())


func test_preload_selects_streamed_floor_over_overlapping_gps_landmark() -> void:
	var fixture := _fixture()
	var room := fixture["room"] as StreamedRoom
	var area := fixture["area"] as GpsDestination
	var visibility := fixture["visibility"] as RoomVisibility
	area.area = AABB(Vector3(-1, 0, -601), Vector3(2, 3, 2))
	assert_eq(visibility._room_at(Vector3(0, 1, -600))["path"], visibility.get_path_to(room))
	visibility.preload_at(Vector3(0, 1, -600))
	assert_true(room.is_loaded())
	assert_true(room.arrival_held())


func test_confirmed_arrival_releases_preload_hold_for_next_departure() -> void:
	var fixture := _fixture()
	var room := fixture["room"] as StreamedRoom
	var visibility := fixture["visibility"] as RoomVisibility
	visibility.preload_at(Vector3(0, 1, -600))
	assert_true(room.arrival_held())
	visibility.assign_room(visibility.get_path_to(room), room.global_bounds())
	assert_false(room.arrival_held())
	visibility.assign_room(NodePath(""), visibility._casino_bounds)
	assert_false(room.is_loaded())


func test_far_plane_covers_the_selected_room_corners() -> void:
	var bounds := AABB(Vector3(-10, -1, -10), Vector3(20, 6, 20))
	var far := RoomVisibility.far_for_bounds(bounds, Vector3(0, 1, 0), 0.05)
	assert_almost_eq(far, Vector3(10, 4, 10).length() + 0.05, 0.001)
	var asymmetric := AABB(Vector3(-6, -2, 3), Vector3(10, 7, 12))
	var outside := RoomVisibility.far_for_bounds(asymmetric, Vector3(8, 1, -4), 0.05)
	assert_almost_eq(outside, Vector3(-14, 4, 19).length() + 0.05, 0.001)


func test_gridmap_tiles_contribute_transformed_bounds_and_camera_distance() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var grid := GridMap.new()
	grid.position = Vector3(10, 0, -5)
	grid.cell_size = Vector3.ONE
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	var library := MeshLibrary.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 5, 0.2)
	library.create_item(0)
	library.set_item_mesh(0, mesh)
	library.set_item_mesh_transform(0, Transform3D(Basis.IDENTITY, Vector3(0, 2.5, 0)))
	grid.mesh_library = library
	root.add_child(grid)
	var turn := grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
	grid.set_cell_item(Vector3i(-24, 0, 0), 0, turn)
	grid.set_cell_item(Vector3i(24, 0, 0), 0, turn)
	var visibility := RoomVisibility.new()
	var bounds := visibility._world_bounds(root)
	visibility.free()
	assert_almost_eq(bounds.position, Vector3(-14.1, 0, -6), Vector3.ONE * 0.001)
	assert_almost_eq(bounds.size, Vector3(48.2, 5, 2), Vector3.ONE * 0.001)
	assert_gt(RoomVisibility.far_for_bounds(bounds, Vector3.ZERO, 0.05), 34.1)
	grid.visible = false
	var hidden_check := RoomVisibility.new()
	assert_eq(hidden_check._world_bounds(root), AABB(), "Hidden grids do not extend the room")
	hidden_check.free()


func test_pending_arrival_survives_a_stale_room_assignment_then_expires() -> void:
	var fixture := _fixture()
	var room := fixture["room"] as StreamedRoom
	var visibility := fixture["visibility"] as RoomVisibility
	room.load_room(3000)
	visibility.assign_room(NodePath(""), visibility._casino_bounds)
	assert_true(room.is_loaded(), "Old assignment must not remove a preloaded arrival floor")
	room.set("_hold_until_msec", Time.get_ticks_msec() - 1)
	visibility._process(0)
	assert_false(room.is_loaded(), "Unused denied/cancelled preload is eventually freed")
