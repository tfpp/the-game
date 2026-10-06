extends GutTest

const METRO := preload("res://features/metro/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var metro: MetroService
var court: MetroSeating
var player: Player


func before_each() -> void:
	metro = METRO.instantiate() as MetroService
	add_child_autofree(metro)
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	for zone: MetroZone in metro.stations + metro.rides:
		zone.seating.set_physics_process(false)
	court = metro.stations[0].seating
	metro.net_time = 5
	player = add_player(1)
	player.global_position = court.stand_position(0) + Vector3.UP * 0.94
	player.net_position = player.global_position
	await wait_physics_frames(3)


func add_player(peer: int) -> Player:
	var rider := PLAYER.instantiate() as Player
	rider.name = str(peer)
	rider.set_multiplayer_authority(peer)
	add_child_autofree(rider)
	rider.set_physics_process(false)
	return rider


func test_authenticated_requests_competition_and_payload_validation() -> void:
	var denied := NetworkedEntity.Result.DENIED
	for payload: Dictionary in [
		{}, {"seat": -1}, {"seat": 500}, {"seat": "0"}, {"seat": 0, "peer": 2}
	]:
		assert_eq(court.entity._evaluate(1, &"sit", payload), denied)
	assert_eq(court.entity._evaluate(9, &"sit", {"seat": 0}), denied)
	assert_eq(court.entity._evaluate(1, &"sit", {"seat": 25}), denied)
	var original := player.net_position
	player.net_position = metro.stations[0].position + Vector3(-2, 0.94, court.seats[0].position.z)
	assert_false(court._may_sit(1, {"seat": 0}), "Cannot sit through wall from tracks")
	player.net_position = original
	var other := add_player(2)
	other.net_position = player.net_position
	assert_eq(court.entity._evaluate(2, &"sit", {"seat": 0}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(court.entity._evaluate(1, &"sit", {"seat": 0}), denied)
	assert_eq(court.entity._evaluate(1, &"stand", {}), denied)
	assert_eq(court.net_seats[0], 2)


func test_use_pins_owner_and_stands_in_clear_aisle() -> void:
	var seat := court.seats[0]
	assert_true(seat.call("can_use", player))
	seat.call("use")
	court._physics_process(0.016)
	assert_eq(player.net_position, court.sit_position(0))
	assert_false(player.is_physics_processing())
	assert_almost_eq(player.yaw, -PI / 2, 0.001)
	assert_eq(seat.call("interaction_text"), "Stand up")
	court._stand(1, {})
	court._physics_process(0.016)
	assert_true(player.is_physics_processing())
	assert_almost_eq(player.global_position.x, court.global_position.x, 0.001)
	assert_almost_eq(player.global_position.y, 2.1344, 0.001)


func test_warning_releases_seat_and_original_boarding_still_works() -> void:
	court.request_sit(0)
	court._physics_process(0.016)
	metro.net_time = MetroRules.OPEN + MetroRules.DWELL - 2
	court._physics_process(0.016)
	player.set_physics_process(false)
	assert_false(court.is_seated(1))
	assert_false(court._may_sit(1, {"seat": 0}))
	assert_true(MetroRules.aboard(player.net_position - metro.stations[0].position))
	metro.net_time = MetroRules.OPEN + MetroRules.DWELL
	metro._begin_boarding_transfer()
	assert_true(metro.transfers.pending.has(1))
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"])
	metro.transfers._physics_process(1.3)
	assert_eq(metro.net_passengers, {1: 0})
	assert_lt(
		player.net_position.distance_to(
			metro.rides[0].position + Vector3(0, 2.1344, court.seats[0].position.z)
		),
		0.002
	)


func test_riding_seats_free_before_arrival_and_lifecycle_cleanup() -> void:
	court = metro.rides[0].seating
	metro.net_time = MetroRules.DEPART + 1
	player.global_position = court.stand_position(0) + Vector3.UP * 0.94
	player.net_position = player.global_position
	court.request_sit(0)
	court._physics_process(0.016)
	assert_true(court.is_seated(1))
	metro.net_time = MetroRules.PERIOD - 4
	court._physics_process(0.016)
	assert_false(court.is_seated(1))
	assert_true(player.is_physics_processing())
	player.set_physics_process(false)
	metro.net_time = 5
	for cleanup: String in ["_on_peer_disconnected", "_on_player_died", "_reset_session"]:
		court._sit(1, {"seat": 0})
		if cleanup == "_on_player_died":
			court.call(cleanup, 1, 2)
		elif cleanup == "_reset_session":
			court.call(cleanup, Network.Mode.OFFLINE)
		else:
			court.call(cleanup, 1)
		assert_false(court.is_seated(1))
	court._sit(1, {"seat": 0})
	player.net_position = Vector3.ZERO
	court._release_moved_players()
	assert_false(court.is_seated(1))


func test_endpoints_survive_streaming_and_all_exits_have_floor_clearance() -> void:
	assert_eq(court.seats.size(), 50)
	metro.stations[0].load_room(10000)
	await wait_physics_frames(4)
	var capsule := CapsuleShape3D.new()
	capsule.radius = player.movement.hull_radius_m()
	capsule.height = player.movement.hull_height_m()
	for index: int in court.seats.size():
		var seat := court.seats[index]
		assert_almost_eq(seat.position.y, 1.68, 0.001)
		assert_gt((-seat.basis.z).dot(Vector3(-signf(seat.position.x), 0, 0)), 0.99)
		var at := court.stand_position(index)
		var ray := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * 0.1, at + Vector3.DOWN * 0.1, 1
		)
		var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
		assert_false(hit.is_empty())
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = at + Vector3.UP * 0.94
		query.collision_mask = 1
		query.exclude = [player.get_rid()]
		assert_true(player.get_world_3d().direct_space_state.intersect_shape(query).is_empty())
	metro.stations[0].unload_room()
	await wait_physics_frames(2)
	assert_eq(court.seats.size(), 50)
	assert_true(court.entity.is_inside_tree())


func test_remote_avatar_reads_metro_snapshot_and_fixed_seat_heading() -> void:
	var models := (load("res://features/player_models/feature.tscn") as PackedScene).instantiate()
	add_child_autofree(models)
	var remote := add_player(2)
	models._process(0.0)
	var avatar := remote.get_node("Body/Avatar") as BlockPlayerModel
	# Initial occupancy is sufficient for an observer/late joiner's avatar pose.
	court._sit(2, {"seat": 0})
	remote.net_yaw = 0.7
	avatar._process(1.0)
	assert_true(avatar.seated)
	assert_almost_eq((avatar.get_parent() as Node3D).global_rotation.y, court.sit_yaw(0), 0.001)
	assert_eq(avatar.locomotion, &"seated")
	court._free_peer(2)
	avatar._process(1.0)
	assert_false(avatar.seated)


func test_existing_seating_provider_prevents_double_seating() -> void:
	var booths := (
		(load("res://features/food_court/feature.tscn") as PackedScene).instantiate() as FoodCourt
	)
	add_child_autofree(booths)
	booths.set_physics_process(false)
	booths._sit(1, {"seat": 0})
	assert_false(court._may_sit(1, {"seat": 0}))
	booths._free_peer(1)
	assert_true(court._may_sit(1, {"seat": 0}))
	metro.transfers.pending[1] = {"token": 123}
	assert_false(court._may_sit(1, {"seat": 0}))
	metro.transfers.pending.clear()
