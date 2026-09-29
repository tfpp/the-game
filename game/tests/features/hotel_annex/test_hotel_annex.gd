extends GutTest

const HotelGeometry := preload("res://features/hotel_annex/hotel.scn")
const Feature := preload("res://features/hotel_annex/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const Layout := preload("res://features/world_builder/layout.gd")

var _feature: Node3D
var _hotel: StreamedRoom


func before_each() -> void:
	_feature = Feature.instantiate() as Node3D
	add_child_autofree(_feature)
	_hotel = _feature.get_node("Hotel") as StreamedRoom


func _player(at: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = at
	player.net_position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_dedicated_server_does_not_load_hotel_but_keeps_rpc_endpoints() -> void:
	await wait_physics_frames(2)
	assert_false(_hotel.is_loaded())
	assert_not_null(_feature.get_node("Entrance"))
	assert_not_null(_hotel.get_node("Return"))


func test_round_trip_preloads_room_and_preserves_links_after_unload() -> void:
	var casino := _feature.get_node("CasinoArrival") as Marker3D
	var arrival := _hotel.get_node("Arrival") as Marker3D
	var entrance := _feature.get_node("Entrance") as RoomDoor
	var exit := _hotel.get_node("Return") as RoomDoor
	var player := _player(casino.global_position)
	assert_true(entrance.can_use(player))
	entrance.use()
	assert_true(_hotel.is_loaded())
	assert_eq(player.net_position, arrival.global_position)
	assert_almost_eq(absf(player.net_yaw), PI, 0.001)
	assert_true(exit.can_use(player))
	exit.use()
	assert_eq(player.net_position, casino.global_position)
	assert_almost_eq(player.net_yaw, 0.0, 0.001)
	_hotel._hold_until_msec = 0
	await wait_physics_frames(2)
	assert_false(_hotel.is_loaded())
	assert_eq(exit.destination_room(), null)
	entrance.use()
	assert_true(_hotel.is_loaded())
	assert_eq(player.net_position, arrival.global_position)


func test_server_rejects_remote_use_from_casino_spawn() -> void:
	var player := _player(Vector3(2, 1, 5))
	(_feature.get_node("Entrance") as RoomDoor).request_enter()
	(_hotel.get_node("Return") as RoomDoor).request_enter()
	assert_eq(player.net_position, Vector3(2, 1, 5))
	assert_false(_hotel.is_loaded())


func test_restored_player_inside_hotel_loads_it_without_using_door() -> void:
	var arrival := _hotel.get_node("Arrival") as Marker3D
	var player := _player(arrival.global_position)
	await wait_physics_frames(2)
	assert_true(_hotel.is_loaded())
	player.global_position = Vector3(5, 1, 27)
	await wait_physics_frames(2)
	assert_false(_hotel.is_loaded())


func test_arrival_has_floor_and_clear_player_hull() -> void:
	_hotel.load_room(3000)
	var marker := _hotel.get_node("Arrival") as Marker3D
	var player := _player(marker.global_position)
	await wait_physics_frames(3)
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		marker.global_position, marker.global_position + Vector3.DOWN * 2
	)
	ray.exclude = [player.get_rid()]
	var hit := space.intersect_ray(ray)
	assert_false(hit.is_empty(), "Hotel floor under arrival")
	if not hit.is_empty():
		assert_almost_eq((hit.position as Vector3).y, 0.0, 0.02)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (player.get_node("Collider") as CollisionShape3D).shape
	query.transform = player.global_transform
	query.exclude = [player.get_rid()]
	assert_eq(space.intersect_shape(query).size(), 0, "Arrival clears walls, pillars and door")


func test_expanded_wing_has_eight_rooms_and_clear_connecting_hallways() -> void:
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://features/hotel_annex/hotel.json")
	)
	var layout: Dictionary = Layout.compile(spec)
	assert_eq(layout["errors"], [])
	assert_eq(layout["rooms"].size(), 8)
	assert_eq(layout["paths"].size(), 7)
	_hotel.load_room(3000)
	for door: SwingDoor in _hotel.get_node("RoomDoors").get_children():
		door.net_state = SwingDoor.State.OPEN_IN
	await wait_seconds(0.5)
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	query.shape = capsule
	var space := _hotel.get_world_3d().direct_space_state
	for path: Array in layout["paths"]:
		for index: int in 2:
			var a: Vector2i = path[index]
			var b: Vector2i = path[index + 1]
			if a == b:
				continue
			var steps := ceili(Vector2(b - a).length() * 4)
			for step: int in steps:
				var from := _route_position(layout, a, b, float(step) / steps)
				var to := _route_position(layout, a, b, float(step + 1) / steps)
				query.transform = Transform3D(Basis.IDENTITY, _hotel.to_global(from))
				query.motion = to - from
				assert_true(space.intersect_shape(query).is_empty(), "Clear hallway entrance")
				assert_almost_eq(
					space.cast_motion(query)[0], 1.0, 0.001, "Walkable connection %s" % str(path)
				)
	assert_eq(layout["flights"].size(), 3)
	assert_almost_eq(_hotel.get_node("Content/Architecture/Rooms/EastSalon").position.y, 1.0, 0.001)
	assert_almost_eq(
		_hotel.get_node("Content/Architecture/Rooms/Conservatory").position.y, 2.5, 0.001
	)


func _route_position(layout: Dictionary, a: Vector2i, b: Vector2i, fraction: float) -> Vector3:
	var point := Vector2(a).lerp(Vector2(b), fraction) + Vector2.ONE * 0.5
	var cell := Vector2i(floori(point.x), floori(point.y))
	var y := preload("res://features/world_builder/elevation.gd").floor_at(layout, cell, point)
	return Vector3(point.x, y + 1.05, point.y)


func test_saved_wing_uses_live_lamps_without_baked_lighting() -> void:
	var scene := HotelGeometry.instantiate() as Node3D
	assert_false(scene.has_meta("baked_lighting"))
	assert_null(scene.get_node_or_null("LightmapGI"))
	assert_gt(scene.find_children("*", "OmniLight3D", true, false).size(), 0)
	scene.free()


func test_service_shaft_and_ladder_route_have_clear_player_hulls() -> void:
	_hotel.load_room(3000)
	var ladder := _hotel.get_node("SewerLadder") as ClimbableLadder
	var door := _hotel.get_node("SewerDoor") as SwingDoor
	door.net_state = SwingDoor.State.OPEN_IN
	await wait_seconds(0.5)
	var space := _hotel.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	query.shape = capsule
	var points: Array[Vector3] = [
		ladder.top_landing, Vector3(0, 1, 0), Vector3(0, -5, 0), ladder.bottom_landing
	]
	for index: int in points.size() - 1:
		query.transform = Transform3D(Basis.IDENTITY, ladder.to_global(points[index]))
		query.motion = points[index + 1] - points[index]
		assert_true(space.intersect_shape(query).is_empty(), "Ladder endpoint clears hull")
		assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Clear ladder travel")
	for point: Vector3 in [ladder.top_landing, ladder.bottom_landing]:
		var ray := PhysicsRayQueryParameters3D.create(
			ladder.to_global(point), ladder.to_global(point + Vector3.DOWN * 1.2)
		)
		assert_false(space.intersect_ray(ray).is_empty(), "Solid landing")
		assert_true(_hotel.contains(ladder.to_global(point)), "Sewer remains streamed in")
	var shaft := PhysicsRayQueryParameters3D.create(
		ladder.to_global(Vector3(0, 1, 0)), ladder.to_global(Vector3(0, -5, 0))
	)
	assert_true(space.intersect_ray(shaft).is_empty(), "Floor and roof have matching holes")
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://features/hotel_annex/hotel.json")
	)
	var layout := Layout.compile(spec)
	assert_eq(layout["floor_finishes"][Vector2i(-18, -7)], "hole")
	assert_eq(layout["floor_finishes"][Vector2i(-14, -2)], "concrete")
	_hotel.unload_room()
	assert_same(_hotel.get_node("SewerLadder"), ladder)
	assert_same(_hotel.get_node("SewerDoor"), door)
	await wait_physics_frames(2)


func test_window_backdrops_are_opaque_and_ceiling_lights_are_spaced() -> void:
	var scene := HotelGeometry.instantiate() as Node3D
	var windows := scene.find_children("SkyBackdrop", "MeshInstance3D", true, false)
	assert_gt(windows.size(), 0)
	for window: MeshInstance3D in windows:
		var material := window.get_active_material(0) as ShaderMaterial
		assert_not_null(material)
		assert_false(material.shader.code.contains("ALPHA"), "Sky occludes outside geometry")
		assert_almost_eq(window.position.z, 0.12, 0.001)
	var lights := scene.find_children("PendantLight*", "OmniLight3D", true, false)
	for a: int in lights.size():
		for b: int in range(a + 1, lights.size()):
			var first: Vector3 = lights[a].position
			var second: Vector3 = lights[b].position
			assert_gte(Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z)), 3.0)
	scene.free()


func test_locked_study_is_two_stair_flights_up_and_doors_survive_streaming() -> void:
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://features/hotel_annex/hotel.json")
	)
	var layout := Layout.compile(spec)
	var stairs := 0
	for flight: Dictionary in layout["flights"]:
		if flight["kind"] == "stairs":
			stairs += 1
			assert_gte(flight["slope_degrees"], 30.0)
			assert_lte(flight["slope_degrees"], 37.0)
	assert_eq(stairs, 2)
	assert_eq(layout["room_elevations"]["UpperStudy"], 4.0)
	assert_eq(layout["doors"].size(), 7)
	var locked := 0
	for door: SwingDoor in _hotel.get_node("RoomDoors").get_children():
		if door.net_state == SwingDoor.State.LOCKED:
			locked += 1
	assert_eq(locked, 1)
	var door := _hotel.get_node("RoomDoors/UpperStudyDoor") as SwingDoor
	assert_eq(door.key_id, "upper_study_key")
	var key := _hotel.get_node("StudyKey") as ItemPickup
	assert_eq(key.item_id, door.key_id)
	assert_true(
		(layout["rooms"]["ReadingRoom"] as Rect2i).has_point(
			Vector2i(key.position.x, key.position.z)
		)
	)
	door.net_state = SwingDoor.State.OPEN_IN
	_hotel.load_room(3000)
	_hotel.unload_room()
	await wait_physics_frames(2)
	assert_false(_hotel.is_loaded())
	assert_eq(door.net_state, SwingDoor.State.OPEN_IN)
	_hotel.load_room(3000)
	assert_same(_hotel.get_node("RoomDoors/UpperStudyDoor"), door)
	assert_eq(door.net_state, SwingDoor.State.OPEN_IN)
