extends GutTest

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


func test_loop_opens_only_platform_side_and_actually_leaves() -> void:
	metro.stations[0].load_room(10000)
	metro.net_time = 5
	metro._update_collision()
	metro.stations[0].update_view()
	await wait_physics_frames(3)
	var train := metro.stations[0].train
	assert_eq(train.position, Vector3.ZERO)
	assert_eq(metro.stations[1].is_loaded(), false)
	assert_eq(metro.rides[0].is_loaded(), false)
	var collision := metro._collision[0]
	assert_almost_eq((collision.get_node("Car01/DoorR1A") as Node3D).position.z, -8.596, 0.001)
	metro.net_time = MetroRules.DEPART + 2
	metro._update_collision()
	metro.stations[0].update_view()
	assert_lt(train.position.z, -50.0)
	assert_lt(collision.position.y, -100.0)
	metro.net_time = MetroRules.DEPART + 5
	metro.stations[0].update_view()
	assert_false(train.visible)
	metro.net_time = MetroRules.PERIOD - 1
	metro.stations[0].update_view()
	assert_gt(train.position.z, 0.0)
	assert_lt(train.position.z, 20.0)
	for cycle: int in 8:
		var stops: Array[int] = []
		for service: int in 4:
			stops.append(MetroRules.station(service, cycle))
		stops.sort()
		assert_eq(stops, [0, 1, 2, 3])


func test_rider_keeps_car_and_can_walk_during_the_trip() -> void:
	var offset := Vector3(0, 2.1244, MetroRules.car_center(4) + 2.5)
	var player := rider(metro.stations[0].position + offset)
	metro.stations[0].load_room(10000)
	metro.net_time = MetroRules.OPEN + MetroRules.DWELL
	metro._begin_boarding_transfer()
	assert_true(metro.transfers.pending.has(1))
	assert_false(metro.transfers._may_ready(1, {"token": -1}))
	assert_false(metro.transfers._may_ready(2, {"token": metro.transfers.pending[1]["token"]}))
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"])
	metro.transfers._physics_process(MetroRules.CLOSE + 0.1)
	assert_lt(player.net_position.distance_to(metro.rides[0].position + offset), 0.002)
	assert_eq(metro.net_passengers, {1: 0})
	player.server_teleport.rpc_id(1, player.net_position + Vector3(0, 0, 1))
	offset.z += 1
	metro.net_time = MetroRules.PERIOD - 3
	metro._begin_arrival_transfer()
	metro.net_cycle = 1
	metro.net_time = 0
	metro._update_collision()
	await wait_physics_frames(8)
	metro.transfers._physics_process(3.1)
	assert_lt(player.net_position.distance_to(metro.stations[1].position + offset), 0.002)
	assert_true(metro.net_passengers.is_empty())
	assert_true(metro.transfers.pending.is_empty())


func test_platform_and_threshold_players_miss_the_train() -> void:
	var player := rider(metro.stations[0].position + Vector3(1.5, 2.1244, 2.5))
	metro._begin_boarding_transfer()
	assert_true(metro.transfers.pending.is_empty())
	assert_gt(player.net_position.x, 3.0)
	player.server_teleport.rpc_id(1, metro.stations[0].position + Vector3(4, 2.1244, 2.5))
	metro.net_time = MetroRules.DEPART + 1
	metro._physics_process(0.1)
	assert_true(metro.net_passengers.is_empty())
	assert_true(metro.transfers.pending.is_empty())
	assert_eq(player.net_position.x, 4.0)
	assert_false(MetroRules.aboard(Vector3(0, 4.7, 2.5)))
	assert_false(MetroRules.aboard(Vector3(0, 2.1244, 11.43)))


func test_unready_departure_recovers_and_death_cleans_passenger() -> void:
	var player := rider(metro.stations[0].position + Vector3(0, 2.1244, 2.5))
	metro._begin_boarding_transfer()
	metro.transfers._physics_process(4)
	assert_true(metro.transfers.pending.is_empty())
	assert_gt(player.net_position.x, 3.0)
	metro.add_passenger(1, 0)
	metro._on_death(1, 2)
	assert_true(metro.net_passengers.is_empty())
	assert_true(metro.transfers.pending.is_empty())
	await wait_physics_frames(5)


func test_dropped_item_preserves_flight_and_owner_on_room_transfer() -> void:
	# Exercise the owner's real item scene without introducing a second spawner.
	var scene := load("res://features/holdables/thrown_item.tscn") as PackedScene
	var dropped := scene.instantiate() as ThrownItem
	dropped.from = Vector3(0, 2, 2.5)
	dropped.to = Vector3(0, 1.3, 3)
	add_child_autofree(dropped)
	dropped.set_physics_process(false)
	var before := dropped._seg_to - dropped._seg_from
	var owner_peer := dropped.get_multiplayer_authority()
	dropped.transfer_by(Vector3(600, 0, -2000))
	assert_eq(dropped._seg_to - dropped._seg_from, before)
	assert_eq(dropped.get_multiplayer_authority(), owner_peer)
	assert_eq(dropped.net_position, dropped.from)


func test_elevator_round_trip_preserves_pose_and_destination_gate() -> void:
	var access := MetroAccess.new()
	access.zone_id = "test_room"
	access.label = "Test Room"
	access.rotation.y = PI / 2
	add_child_autofree(access)
	await wait_physics_frames(3)
	assert_true(metro.register_access(access))
	assert_eq(metro.accesses.size(), 1, "Registration is idempotent")
	var player := rider(access.source.car.to_global(Vector3(0, 0.93, 0)))
	var original := player.net_position
	metro.depart_elevator(access.source, [player])
	assert_true(access.source.net_riding)
	assert_true(access.destination.net_riding)
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"])
	metro.transfers._physics_process(1.1)
	assert_lt(
		player.net_position.distance_to(access.destination.car.to_global(Vector3(0, 0.93, 0))),
		0.002
	)
	assert_false(access.source.net_riding)
	access.access_policy = "vip"
	access.destination.net_state = ElevatorCab.State.CLOSED
	metro.depart_elevator(access.destination, [player])
	assert_true(metro.transfers.pending.is_empty(), "Missing VIP owner denies entry")
	access.access_policy = "public"
	access.source.net_state = ElevatorCab.State.CLOSED
	access.destination.net_state = ElevatorCab.State.CLOSED
	metro.depart_elevator(access.destination, [player])
	await wait_physics_frames(8)
	metro.transfers._physics_process(1.1)
	assert_lt(player.net_position.distance_to(original), 0.002)


func test_entering_after_boarding_cutoff_returns_to_platform() -> void:
	var player := rider(metro.stations[0].position + Vector3(4, 2.1244, 2.5))
	metro.net_time = MetroRules.OPEN + MetroRules.DWELL
	metro._begin_boarding_transfer()
	player.server_teleport.rpc_id(1, metro.stations[0].position + Vector3(0, 2.1244, 2.5))
	metro._physics_process(MetroRules.CLOSE + 0.01)
	assert_gt(player.net_position.x, 3.0)
	assert_true(metro.net_passengers.is_empty())


func test_slow_arrival_retains_safe_carriage_until_recovery_is_ready() -> void:
	var player := rider(metro.rides[0].position + Vector3(0, 2.1244, 2.5))
	metro.add_passenger(1, 0)
	metro.net_time = MetroRules.PERIOD - 3
	metro._begin_arrival_transfer()
	metro.transfers._physics_process(11)
	assert_eq(metro.transfers.pending[1]["kind"], "recover")
	assert_lt(
		player.net_position.distance_to(metro.rides[0].position + Vector3(0, 2.1244, 2.5)), 0.002
	)
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"])
	metro.transfers._physics_process(0.1)
	assert_lt(
		player.net_position.distance_to(metro.stations[1].position + Vector3(3.3, 2.15, 0)), 0.002
	)
	assert_true(metro.net_passengers.is_empty())


func test_gps_has_loop_and_ride_links_and_hides_ineligible_destinations() -> void:
	var access := MetroAccess.new()
	access.zone_id = "restricted"
	access.label = "Restricted"
	add_child_autofree(access)
	await wait_physics_frames(3)
	assert_eq(metro.gps_links().size(), 10)
	access.access_policy = "vip"
	assert_eq(metro.gps_links().size(), 8)
	assert_false((access.get_node("MetroDestination") as GpsDestination).available())
	metro.net_time = MetroRules.DEPART + 1
	var ride_link: Dictionary = metro.gps_links()[1]
	assert_eq(ride_link["to"], metro.stations[1].position + Vector3(3, 1.2, 0))


func test_dedicated_collision_has_no_meshes_or_lights_and_session_clears_rooms() -> void:
	for body: Node3D in metro._collision:
		assert_eq(body.find_children("*", "MeshInstance3D", true, false).size(), 0)
		assert_eq(body.find_children("*", "Light3D", true, false).size(), 0)
		for grid: GridMap in body.find_children("*", "GridMap", true, false):
			for id: int in grid.mesh_library.get_item_list():
				assert_null(grid.mesh_library.get_item_mesh(id))
	metro.stations[0].load_room(10000)
	metro.add_passenger(1, 0)
	metro._reset(Network.Mode.OFFLINE)
	assert_false(metro.stations[0].is_loaded())
	assert_true(metro.net_passengers.is_empty())
	await wait_physics_frames(3)


func test_jumping_passenger_gets_floor_readiness_and_can_board() -> void:
	var player := rider(metro.stations[0].position + Vector3(0, 2.65, 2.5))
	metro._begin_boarding_transfer()
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"])
	metro.transfers._physics_process(1.3)
	assert_lt(
		player.net_position.distance_to(metro.rides[0].position + Vector3(0, 2.65, 2.5)), 0.002
	)


func test_recovery_does_not_pull_back_a_player_who_used_an_existing_warp() -> void:
	var player := rider(metro.rides[0].position + Vector3(0, 2.1244, 2.5))
	metro.add_passenger(1, 0)
	metro.net_time = MetroRules.PERIOD - 3
	metro._begin_arrival_transfer()
	metro.transfers._physics_process(11)
	player.server_teleport.rpc_id(1, Vector3(0, 1, 0))
	await wait_physics_frames(8)
	metro.transfers._physics_process(0.1)
	assert_eq(player.net_position, Vector3(0, 1, 0))
	assert_true(metro.net_passengers.is_empty())


func test_departure_timeout_does_not_pull_back_a_player_who_warped() -> void:
	var player := rider(metro.stations[0].position + Vector3(0, 2.1244, 2.5))
	metro._begin_boarding_transfer()
	player.server_teleport.rpc_id(1, Vector3(0, 1, 0))
	metro.transfers._physics_process(4)
	assert_eq(player.net_position, Vector3(0, 1, 0))
	assert_true(metro.transfers.pending.is_empty())
	await wait_physics_frames(5)
