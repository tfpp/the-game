extends GutTest
## Two tracks share an island; riders keep their own direction through transfers.

const METRO := preload("res://features/metro/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var metro: MetroService


func before_each() -> void:
	metro = METRO.instantiate() as MetroService
	add_child_autofree(metro)
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	await wait_physics_frames(3)


func rider(at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.position = at
	player.net_position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_both_directions_serve_every_stop_and_open_only_onto_island() -> void:
	assert_eq(metro.rides.size(), 8)
	for track_index: int in 2:
		for cycle: int in 8:
			var stops: Array[int] = []
			for service_id: int in range(track_index * 4, track_index * 4 + 4):
				stops.append(MetroRules.station(service_id, cycle))
			stops.sort()
			assert_eq(stops, [0, 1, 2, 3])
	assert_eq(MetroRules.station(0, 1), 1)
	assert_eq(MetroRules.station(4, 1), 3)
	metro.net_time = 5
	metro._update_collision()
	var reverse := metro._collision[4]
	var right := reverse.get_node("Car01/DoorR1A") as Node3D
	var left := reverse.get_node("Car01/DoorL1A") as Node3D
	assert_almost_eq(left.position.z, -8.596, 0.001)
	assert_almost_eq(right.position.z, -7.856, 0.001)
	metro.stations[0].load_room(10000)
	metro.net_time = MetroRules.DEPART + 4
	metro.stations[0].update_view()
	assert_lt(metro.stations[0].train.position.z, 0.0)
	assert_gt(metro.stations[0].reverse_train.position.z, 0.0)


func test_reverse_boarding_arrival_and_threshold_recovery_stay_on_correct_side() -> void:
	var origin := metro.train_origin(4, 0)
	var offset := Vector3(0, 2.1244, 2.5)
	var player := rider(origin + offset)
	metro.net_time = MetroRules.OPEN + MetroRules.DWELL
	metro._begin_boarding_transfer()
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"])
	metro.transfers._physics_process(1.3)
	assert_eq(metro.net_passengers, {1: 4})
	assert_lt(player.net_position.distance_to(metro.rides[4].position + offset), 0.01)
	metro.net_time = MetroRules.PERIOD - 3
	metro._begin_arrival_transfer()
	metro.net_time = 0
	metro.net_cycle = 1
	metro._update_collision()
	await wait_physics_frames(8)
	metro.transfers._physics_process(3.1)
	assert_lt(player.net_position.distance_to(metro.train_origin(4, 1) + offset), 0.01)
	assert_true(metro.net_passengers.is_empty())
	player.server_teleport.rpc_id(1, metro.train_origin(4, 1) + Vector3(-1.6, 2.1244, 2.5))
	metro._clear_unboarded()
	assert_almost_eq(player.net_position.x - metro.stations[3].position.x, 12.7, 0.002)


func test_boarding_accepts_crouching_jumping_and_beside_seat_positions() -> void:
	for pose: Vector3 in [Vector3(0, 1.7, 2.5), Vector3(0, 3.35, 2.5), Vector3(1.08, 2.3, 2.5)]:
		var player := rider(metro.stations[0].position + pose)
		metro._begin_boarding_transfer()
		assert_true(metro.transfers.pending.has(1), str(pose))
		await wait_physics_frames(8)
		assert_true(metro.transfers.pending[1]["ready"])
		metro.transfers._physics_process(1.3)
		assert_lt(player.net_position.distance_to(metro.rides[0].position + pose), 0.01)
		metro.remove_passenger(1)
		player.free()


func test_pending_departure_keeps_floor_until_ready_or_timeout() -> void:
	var player := rider(metro.stations[0].position + Vector3(0, 2.1244, 2.5))
	metro._begin_boarding_transfer()
	metro.net_time = MetroRules.DEPART + 0.5
	metro._update_collision()
	assert_eq(metro._collision[0].position.y, 0.0, "Pending rider retains the floor")
	assert_eq(metro._collision[1].position.y, -200.0, "Empty station does not retain a train")
	metro.transfers._physics_process(4)
	metro._update_collision()
	assert_eq(metro._collision[0].position.y, -200.0)
	assert_almost_eq(player.net_position.x, 3.3, 0.002)
	await wait_physics_frames(4)


func test_completed_boarder_with_stale_server_position_is_not_ejected() -> void:
	var origin := metro.stations[0].position + Vector3(0, 2.1244, 2.5)
	var player := rider(origin)
	metro.add_passenger(1, 0)
	metro._clear_unboarded()
	assert_eq(player.net_position, origin, "No second teleport while owner update is in flight")
	assert_eq(metro.net_passengers, {1: 0})


func test_island_has_floor_between_tracks_and_station_shaft_meets_ceiling() -> void:
	var access := MetroAccess.new()
	access.zone_id = "island_test"
	access.label = "Test"
	add_child_autofree(access)
	metro.register_access(access)
	await wait_physics_frames(4)
	var space := metro.get_world_3d().direct_space_state
	for x: float in [3, 5, 11, 13]:
		var at := metro.stations[0].position + Vector3(x, 2, 55)
		var ray := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 3, 1)
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty())
		assert_almost_eq((hit["position"] as Vector3).y, 1.2, 0.002)
	for x: float in [0, 16]:
		var at := metro.stations[0].position + Vector3(x, 0.8, 55)
		var ray := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 2, 1)
		var hit := space.intersect_ray(ray)
		assert_almost_eq((hit["position"] as Vector3).y, 0.0, 0.002)
	var shaft := access.destination.get_node("CeilingShaft/Shaft") as GridMap
	var mesh := shaft.mesh_library.get_item_mesh(0)
	var pose := shaft.global_transform * shaft.mesh_library.get_item_mesh_transform(0)
	var bounds := pose * mesh.get_aabb()
	assert_almost_eq(bounds.position.y, 3.7, 0.002)
	assert_gte(bounds.end.y, 5.475)
	assert_true(access.source.has_node("GreenEntrancePosts"))
	assert_true(access.destination.has_node("GreenEntrancePosts"))


func test_reverse_seats_use_the_reverse_cabin_coordinate_frame() -> void:
	var court := metro.stations[0].reverse_seating
	var player := rider(court.stand_position(0) + Vector3.UP * 0.94)
	metro.net_time = 5
	assert_true(court._may_sit(1, {"seat": 0}))
	assert_false(metro.stations[0].seating._may_sit(1, {"seat": 0}))
	assert_almost_eq(player.net_position.x, MetroRules.TRACK_SPACING, 0.001)


func test_reverse_windows_align_with_their_platform_and_scrolling_materials() -> void:
	var zone := metro.rides[4]
	zone.load_room(10000)
	metro.net_time = MetroRules.DEPART + 4
	zone.update_view()
	assert_almost_eq(zone.scenery.position.z, -MetroRules.distance(4), 0.001)
	for material: ShaderMaterial in zone._scrolling:
		assert_almost_eq(
			float(material.get_shader_parameter("scroll")), zone.scenery.position.z, 0.001
		)
	metro.net_time = MetroRules.PERIOD
	zone.update_view()
	var arrival := zone.scenery.get_node("Arrival") as Node3D
	assert_almost_eq(zone.to_local(arrival.global_position).z, 0.0, 0.001)
	assert_eq(arrival.position.x, -MetroRules.TRACK_SPACING)
	assert_true((arrival.get_node("Identity/Station3") as Node3D).visible)
	assert_false((arrival.get_node("Identity/Station1") as Node3D).visible)


func test_station_and_both_ride_scenes_share_the_baked_train_meshes() -> void:
	var shared: Mesh
	for scene: String in [
		"res://features/metro/rooms/station.tscn",
		"res://features/metro/rooms/transit.tscn",
		"res://features/metro/rooms/transit_reverse.tscn"
	]:
		var content := autofree((load(scene) as PackedScene).instantiate()) as Node3D
		var train := content.get_node("Train") as Node3D
		assert_eq(train.scene_file_path, "res://features/metro/train_visual.tscn")
		var surfaces := train.find_children("Static*", "MeshInstance3D", true, false)
		assert_eq(surfaces.size(), 30)
		var mesh := (surfaces[0] as MeshInstance3D).mesh
		if shared == null:
			shared = mesh
		else:
			assert_eq(mesh, shared, "Room loading reuses the same train geometry")


func test_batched_door_visuals_follow_both_sides_without_sharing_animation_state() -> void:
	var zone := metro.stations[0]
	zone.load_room(10000)
	assert_eq(zone._door_batches.size(), 10, "One batch per car on both tracks")
	if DisplayServer.get_name() != "headless":
		# Let the renderer allocate the freshly loaded instance buffers.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	for time: float in [0.0, 0.6, 5.0, MetroRules.OPEN + MetroRules.DWELL + 0.6, MetroRules.DEPART]:
		metro.net_time = time
		zone.update_view()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		for node: MultiMeshInstance3D in zone._door_batches:
			var batch := node as MetroDoorBatch
			assert_eq(batch.multimesh.instance_count, 16)
			assert_eq(batch._doors.size(), 16)
			# Dummy rendering does not retain GPU instance transforms. Native GUT
			# runs additionally verify the rendered leaves against both animations.
			if DisplayServer.get_name() == "headless":
				continue
			for index: int in batch.door_paths.size():
				var door := batch.get_node(batch.door_paths[index]) as Node3D
				var expected := door.transform * batch.visual_transforms[index]
				assert_true(batch.multimesh.get_instance_transform(index).is_equal_approx(expected))
	assert_ne(zone._door_batches[0].multimesh, zone._door_batches[5].multimesh)
