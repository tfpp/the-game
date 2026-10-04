extends GutTest

const GARAGE := preload("res://features/procedural_rooms/feature.tscn")
const ZONES := preload("res://features/zone_instances/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const Cheats := preload("res://tests/features/dev_access/cheats_fixture.gd")


func test_startup_registration_has_no_garage_map_or_collision() -> void:
	var registration := GARAGE.instantiate() as Node3D
	add_child_autofree(registration)
	var marker_root := registration.get_node("Garage")
	assert_eq(marker_root.find_children("*", "GeometryInstance3D", true, false).size(), 0)
	assert_eq(marker_root.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_true(marker_root.get_node("Arrival") is SlumArrivalPoint)


func test_portal_waits_for_private_garage_readiness() -> void:
	await _exercise_route("portal")


func test_warp_waits_for_private_garage_readiness() -> void:
	await _exercise_route("warp")


func test_van_updates_overlay_destination_and_waits_for_private_garage() -> void:
	await _exercise_route("van")


func _exercise_route(route: String) -> void:
	Cheats.enable(self)
	var features := Node3D.new()
	add_child_autofree(features)
	var registration := GARAGE.instantiate() as Node3D
	registration.name = "procedural_rooms"
	features.add_child(registration)
	var zones := ZONES.instantiate() as ZoneInstances
	features.add_child(zones)
	zones.set_physics_process(false)
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	features.add_child(player)
	player.set_physics_process(false)
	var van: OperationsVan
	match route:
		"portal":
			var portal := registration.get_node("Entrance") as GarageDoor
			player.net_position = portal.global_position
			player.global_position = player.net_position
			portal.use()
		"warp":
			var room := preload("res://features/dev_room/feature.tscn").instantiate()
			features.add_child(room)
			room.handle_chat_command(1, "warp garage")
		"van":
			var starter := preload("res://features/starter_room/feature.tscn").instantiate()
			features.add_child(starter)
			van = starter.get_node("Room/Van") as OperationsVan
			van.set_physics_process(false)
			player.net_position = van.to_global(Vector3(-1.6, 1, 1))
			player.global_position = player.net_position
			van.request_trip(1)
			van._physics_process(OperationsVan.TRAVEL_SECONDS)
	var start := player.net_position
	var id := zones.registry.instance_of(1)
	assert_ne(id, -1, route)
	if id == -1:
		return
	var run := zones.scope_for(id) as SlumInstance
	assert_eq(run.destination, SlumInstance.Destination.GARAGE)
	assert_true(run.has_node("Map"), "Actual private map is instantiated")
	assert_gt(run.entry_position().z, 10000.0)
	if van != null:
		assert_true(van.panel.is_open())
		assert_eq(van.panel._destination, run.entry_position())
		van.panel.set_process(false)
	var trip: Dictionary = zones._transfers[1]
	trip["after"] = 0
	run.ready_peers.clear()
	zones._physics_process(0)
	assert_eq(player.net_position, start, "Unavailable map must not receive the player")
	run.ready_peers.append(1)
	zones._physics_process(0)
	assert_eq(player.net_position, run.entry_position())
	assert_eq(run.return_cab.net_state, ElevatorCab.State.OPENING)
	if van != null:
		van.panel._process(OperationsVan.TRAVEL_SECONDS)
		assert_false(van.panel.is_open(), "Travel overlay closes at the actual private arrival")
	await wait_physics_frames(2)
