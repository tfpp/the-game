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
	assert_eq(visibility._room_at(Vector3(0, 1, -600))["path"], room.get_path())
	assert_eq(visibility._room_at(Vector3(0, 1, 600))["path"], area.get_path())
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


func test_far_plane_covers_the_selected_room_corners() -> void:
	var bounds := AABB(Vector3(-10, -1, -10), Vector3(20, 6, 20))
	var far := RoomVisibility.far_for_bounds(bounds, Vector3(0, 1, 0), 0.05)
	assert_almost_eq(far, Vector3(10, 4, 10).length() + 0.05, 0.001)
	var asymmetric := AABB(Vector3(-6, -2, 3), Vector3(10, 7, 12))
	var outside := RoomVisibility.far_for_bounds(asymmetric, Vector3(8, 1, -4), 0.05)
	assert_almost_eq(outside, Vector3(-14, 4, 19).length() + 0.05, 0.001)


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
