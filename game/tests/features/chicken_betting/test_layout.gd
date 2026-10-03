extends GutTest

const SCENE := preload("res://features/chicken_betting/feature.tscn")
var feature: Node3D
var room: StreamedRoom


func before_each() -> void:
	feature = SCENE.instantiate() as Node3D
	add_child_autofree(feature)
	room = feature.get_node("Room") as StreamedRoom
	room.set_physics_process(false)
	room.load_room()
	var book := room.get_node("Book") as ChickenBettingBook
	book.set_process(false)
	await wait_physics_frames(3)


func test_saved_gridmap_floor_and_ceiling_cover_arrival_book_arena_and_exit() -> void:
	for point: Vector3 in [
		Vector3(0, 0, 3),
		Vector3(-3, 0, 3),
		Vector3(-1.5, 0, -1),
		Vector3(1.5, 0, -1),
		Vector3(0, 0, 4)
	]:
		var origin := room.to_global(point + Vector3(0, 2, 0))
		var floor_hit := _ray(origin, origin - Vector3(0, 4, 0))
		assert_false(floor_hit.is_empty())
		if not floor_hit.is_empty():
			assert_almost_eq((floor_hit["position"] as Vector3).y, 0.0, 0.02)
		var ceiling_hit := _ray(origin, origin + Vector3(0, 5, 0))
		assert_false(ceiling_hit.is_empty())


func test_doors_destinations_gps_and_clear_spectator_route() -> void:
	var entrance := feature.get_node("Entrance") as RoomDoor
	assert_eq(entrance.global_position, Vector3(-20, 1.25, -19.65))
	assert_eq(entrance.destination_room(), room)
	var exit := room.get_node("Exit") as RoomDoor
	assert_eq(exit.get_node(exit.destination), feature.get_node("CasinoArrival"))
	var marker := room.get_node("Destination") as GpsDestination
	assert_true(room.contains(marker.global_position))
	var gps := preload("res://features/gps/feature.tscn").instantiate() as Gps
	add_child_autofree(gps)
	var hop := GpsRoute.next_hop(
		gps.regions(), gps.links(), Vector3(-20, 1, -17.8), marker.global_position
	)
	assert_eq(hop["door"], "Unmarked service door")
	assert_true(_ray(room.to_global(Vector3(0, 1, 3)), room.to_global(Vector3(0, 1, 0))).is_empty())
	assert_true(
		_ray(room.to_global(Vector3(0, 1, 3)), room.to_global(Vector3(-3, 1, 3))).is_empty()
	)


func test_live_casino_entrance_has_floor_and_a_clear_approach() -> void:
	var casino := preload("res://features/casino_hub/casino_gridmap.tscn").instantiate() as Node3D
	add_child_autofree(casino)
	await wait_physics_frames(3)
	var floor_hit := _ray(Vector3(-20, 1, -17.8), Vector3(-20, -2, -17.8))
	assert_false(floor_hit.is_empty())
	assert_almost_eq((floor_hit["position"] as Vector3).y, 0.0, 0.01)
	assert_true(_ray(Vector3(-20, 1, -16), Vector3(-20, 1, -19.3)).is_empty())


func test_terminal_sits_on_crate_and_views_face_each_other() -> void:
	var book := room.get_node("Book") as ChickenBettingBook
	var terminal := book.get_node("Terminal") as Node3D
	assert_almost_eq(terminal.position.y, 0.7975, 0.0001)
	var presentation := book.get_node("Presentation") as Node3D
	assert_eq(presentation.global_position, room.global_position)
	# Avatar front is -Z; left bird yaw -pi/2 points +X, right points -X.
	for side: float in [-1.0, 1.0]:
		var front := Basis(Vector3.UP, side * PI / 2.0) * Vector3.FORWARD
		assert_almost_eq(front.x, -side, 0.001)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return room.get_world_3d().direct_space_state.intersect_ray(query)
