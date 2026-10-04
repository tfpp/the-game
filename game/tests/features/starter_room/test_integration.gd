extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const GARAGE := preload("res://features/procedural_rooms/prototype.tscn")
const STREET := preload("res://features/street_district/feature.tscn")
const CASINO := preload("res://features/casino_hub/gridmap/playable.tscn")
const RUNS := preload("res://features/slum_runs/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")


func test_all_routes_use_existing_arrivals_and_street_floor_preloads_before_travel() -> void:
	preload("res://tests/features/dev_access/cheats_fixture.gd").enable(self)
	var features := Node3D.new()
	add_child_autofree(features)
	var garage := GARAGE.instantiate() as Node3D
	garage.name = "procedural_rooms"
	features.add_child(garage)
	var street := STREET.instantiate() as Node3D
	street.name = "street_district"
	features.add_child(street)
	var starter := FEATURE.instantiate() as Node3D
	starter.name = "starter_room"
	features.add_child(starter)
	var shop := preload("res://features/pawn_shop/feature.tscn").instantiate() as Node3D
	shop.name = "pawn_shop"
	features.add_child(shop)
	var mall := preload("res://features/strip_mall/feature.tscn").instantiate() as Node3D
	mall.name = "strip_mall"
	features.add_child(mall)
	var van := starter.get_node("Room/Van") as OperationsVan
	van.set_physics_process(false)
	assert_eq(van.arrival(1), garage.get_node("Garage/Arrival"))
	assert_eq(van.arrival(2), street.get_node("Room/Arrival"))
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	var runs := RUNS.instantiate() as SlumRuns
	features.add_child(runs)
	var slum := SlumArrivalPoint.new()
	features.add_child(slum)
	assert_eq(van.arrival(3), shop.get_node("Room/Arrival"))
	assert_eq(van.arrival(4), mall.get_node("Room/Arrival"))
	van.use()
	assert_eq(van.panel._buttons.size(), 5)
	assert_false(van.panel._buttons[4].disabled)
	assert_true(van.panel._buttons[4].text.contains("Strip Mall"))
	for zone: int in OperationsVan.ZONE_NAMES.size():
		player.net_position = van.to_global(Vector3(-1.6, 1, 1))
		player.global_position = player.net_position
		runs.begin(1, slum)
		assert_true(runs.is_active(1))
		if zone == 4:
			van.panel.open_map(van)
			van.panel._buttons[4].pressed.emit()
		else:
			van.request_trip(zone)
		if zone == 4:
			assert_true((mall.get_node("Room") as StreamedRoom).arrival_held())
			assert_true(van.panel._travelling)
		if zone == 2:
			assert_true((street.get_node("Room") as StreamedRoom).arrival_held())
		if zone == 3:
			assert_true((shop.get_node("Room") as StreamedRoom).arrival_held())
		van._physics_process(OperationsVan.TRAVEL_SECONDS)
		assert_eq(player.net_position, van.arrival(zone).global_position)
		assert_false(runs.is_active(1), "reuse existing excursion finish on development travel")
		van.panel.close(false)
	await wait_physics_frames(3)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			player.net_position, player.net_position - Vector3.UP * 2
		)
	)
	assert_false(hit.is_empty(), "mall arrival's streamed floor exists before teleport")


func test_casino_entrance_is_on_supported_north_promenade_with_clear_approach() -> void:
	var casino := CASINO.instantiate() as Node3D
	add_child_autofree(casino)
	var starter := FEATURE.instantiate() as Node3D
	add_child_autofree(starter)
	await wait_physics_frames(3)
	var arrival := starter.get_node("CasinoArrival") as Marker3D
	var hit := arrival.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			arrival.global_position, arrival.global_position - Vector3.UP * 2
		)
	)
	assert_false(hit.is_empty())
	assert_almost_eq((hit["position"] as Vector3).y, 0.0, .001)
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = Vector3(-7, .95, -16)
	query.motion = Vector3(0, 0, -2.2)
	assert_eq(arrival.get_world_3d().direct_space_state.cast_motion(query)[0], 1.0)
	var room := starter.get_node("Room") as StreamedRoom
	var gps := room.get_node("Destination") as GpsDestination
	assert_true(room.contains(gps.global_position))
	var door := starter.get_node("CasinoReturn") as RoomDoor
	assert_eq(door.destination_room(), room)
