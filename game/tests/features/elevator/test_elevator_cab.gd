extends GutTest
## Door policy and opt-in transfers. Production leaves travel disabled.

const CAB := preload("res://features/elevator/elevator_cab.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _root: Node3D
var _cab: ElevatorCab
var _arrival: ElevatorCab


func before_each() -> void:
	_root = Node3D.new()
	_cab = CAB.instantiate() as ElevatorCab
	_cab.name = "Source"
	_arrival = CAB.instantiate() as ElevatorCab
	_arrival.name = "Arrival"
	_arrival.position = Vector3(20, 0, 0)
	_arrival.rotation.y = PI / 2
	_cab.destination = NodePath("../Arrival")
	_root.add_child(_cab)
	_root.add_child(_arrival)
	add_child_autofree(_root)
	_cab.set_physics_process(false)
	_arrival.set_physics_process(false)
	_cab.set_process(false)
	_arrival.set_process(false)


func _player_at(offset: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = _cab.car.to_global(offset)
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func _cycle() -> void:
	assert_true(_cab.request_doors())
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S)
	assert_eq(_cab.net_state, ElevatorCab.State.OPEN)
	_cab._server_advance(ElevatorCab.BOARDING_S)
	assert_eq(_cab.net_state, ElevatorCab.State.CLOSING)
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S)
	assert_eq(_cab.net_state, ElevatorCab.State.CLOSED)


func test_default_cycle_opens_and_closes_without_moving_cab_or_riders() -> void:
	var player := _player_at(Vector3(0, 0.95, 0))
	var start := player.global_transform
	var cab_start := _cab.global_transform
	_cycle()
	assert_true(player.global_transform.is_equal_approx(start))
	assert_true(_cab.global_transform.is_equal_approx(cab_start))
	assert_eq(_cab.net_aperture, 0.0)


func test_ride_locks_controls_ticks_indicators_and_arrival_stops_it() -> void:
	_cab.server_begin_ride()
	assert_true(_cab.net_riding)
	assert_false(_cab.request_doors())
	_cab._physics_process(.65)
	assert_eq(_cab.net_floor, "B1")
	assert_eq((_cab.get_node("Car/CabIndicator") as SignBoard).text, "B1")
	assert_eq(_cab.net_aperture, 0.0)
	_cab.server_arrive()
	assert_false(_cab.net_riding)
	assert_eq(_cab.net_floor, "C")
	assert_eq(_cab.net_state, ElevatorCab.State.OPENING)
	assert_eq(_arrival.net_state, ElevatorCab.State.CLOSED)


func test_ride_indicators_follow_alley_and_return_destinations() -> void:
	_cab.server_begin_ride("A")
	assert_eq(_cab.net_floor, "C")
	_cab._physics_process(.5)
	assert_eq(_cab.net_floor, "-")
	_cab._physics_process(.2)
	assert_eq(_cab.net_floor, "A")
	_cab.server_end_ride()
	_cab.home_floor = "B1"
	_cab.server_begin_ride("C")
	assert_eq(_cab.net_floor, "B1")
	_cab._physics_process(.7)
	assert_eq(_cab.net_floor, "C")
	_cab.server_end_ride()
	assert_eq(_cab.net_floor, "B1", "The empty parked departure cab keeps its home floor")


func test_ride_shake_only_offsets_local_camera_and_restores_it() -> void:
	var player := _player_at(Vector3(0, .95, 0))
	var camera := player.get_node("Camera") as Camera3D
	camera.current = true
	camera.h_offset = .12
	camera.v_offset = -.08
	var pose := player.global_transform
	_cab.server_begin_ride()
	_cab._process(.03)
	assert_ne(camera.h_offset, .12)
	assert_ne(camera.v_offset, -.08)
	assert_lt(absf(camera.h_offset - .12), .0041)
	assert_lt(absf(camera.v_offset + .08), .0061)
	assert_eq(player.global_transform, pose)
	player.net_position = _cab.car.to_global(Vector3(4, .95, 0))
	_cab._process(.03)
	assert_almost_eq(camera.h_offset, .12, .00001)
	assert_almost_eq(camera.v_offset, -.08, .00001)
	player.net_position = pose.origin
	_cab._process(.03)
	_cab._reset(Network.Mode.OFFLINE)
	assert_false(_cab.net_riding)
	assert_almost_eq(camera.h_offset, .12, .00001)
	assert_almost_eq(camera.v_offset, -.08, .00001)
	assert_false(_cab._ride_hum.playing)


func test_opt_in_trip_preserves_group_offsets_facing_and_pitch() -> void:
	_cab.travel_enabled = true
	var offsets: Array[Vector3] = [Vector3(-0.8, 0.95, -0.7), Vector3(0.8, 0.95, 0.4)]
	var riders: Array[Player] = []
	for offset: Vector3 in offsets:
		var player := _player_at(offset)
		player.yaw = 0.4
		player.net_yaw = 0.4
		player.pitch = -0.2
		riders.append(player)
	var outside := _player_at(Vector3(4, 0.95, 0))
	var outside_start := outside.global_position
	assert_true(_cab.request_doors())
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S)
	_cab._server_advance(ElevatorCab.BOARDING_S)
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S * 0.5)
	assert_gt(_cab.net_aperture, 0.0)
	assert_true(riders[0].global_position.is_equal_approx(_cab.car.to_global(offsets[0])))
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S)
	for index: int in riders.size():
		assert_true(
			riders[index].global_position.is_equal_approx(_arrival.car.to_global(offsets[index]))
		)
		assert_almost_eq(riders[index].yaw, PI / 2 + 0.4, 0.0001)
		assert_almost_eq(riders[index].pitch, -0.2, 0.0001)
	assert_true(outside.global_position.is_equal_approx(outside_start))
	assert_eq(_arrival.net_state, ElevatorCab.State.OPENING)
	# An arrival opens to unload; it cannot send everyone straight back automatically.
	_arrival.travel_enabled = true
	_arrival.destination = NodePath("../Source")
	_arrival._server_advance(ElevatorCab.DOOR_SLIDE_S)
	_arrival._server_advance(ElevatorCab.BOARDING_S)
	_arrival._server_advance(ElevatorCab.DOOR_SLIDE_S)
	assert_true(riders[0].global_position.is_equal_approx(_arrival.car.to_global(offsets[0])))


func test_hall_call_authenticates_sender_and_rejects_forged_or_distant_requests() -> void:
	var hall := _cab.get_node("Car/HallButton") as Node3D
	var entity := hall.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(99, &"use", {}), NetworkedEntity.Result.DENIED)
	var player := _player_at(Vector3(0, 0.95, 0))
	assert_eq(entity._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	player.net_position = Vector3(50, 1, 0)
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	player.net_position = hall.global_position + Vector3(0, 0, 1)
	entity.request_use()
	assert_eq(_cab.net_state, ElevatorCab.State.OPENING)
	assert_false(_cab.request_doors(), "Moving doors ignore repeat calls")


func test_open_doors_can_be_closed_manually_from_the_cab_plate() -> void:
	_player_at(Vector3(0.5, 0.95, -0.4))
	assert_true(_cab.request_doors())
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S)
	var entity := _cab.get_node("Car/CabButton/NetworkedEntity") as NetworkedInteraction
	entity.request_use()
	assert_eq(_cab.net_state, ElevatorCab.State.CLOSING)


func test_threshold_occupant_holds_open_and_reverses_a_closing_door() -> void:
	var player := _player_at(Vector3(0, 0.95, 1.35))
	assert_true(_cab.request_doors())
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S)
	_cab._server_advance(ElevatorCab.BOARDING_S)
	assert_eq(_cab.net_state, ElevatorCab.State.OPEN)
	assert_false(_cab.request_doors())
	player.net_position = _cab.car.to_global(Vector3(0, 0.95, 0))
	assert_true(_cab.request_doors())
	_cab._server_advance(0.2)
	var aperture := _cab.net_aperture
	player.net_position = _cab.car.to_global(Vector3(0, 0.95, 1.35))
	_cab._server_advance(0.1)
	assert_eq(_cab.net_state, ElevatorCab.State.OPENING)
	assert_eq(_cab.net_aperture, aperture, "Reverse from current position without snapping")
	assert_true(player.global_position.is_equal_approx(_cab.car.to_global(Vector3(0, 0.95, 1.35))))


func test_late_join_snapshot_declares_aperture_and_applies_actual_leaf_position() -> void:
	var sync := _cab.entity.get_node("Sync") as MultiplayerSynchronizer
	var config := sync.replication_config
	for path: NodePath in [
		NodePath(".:net_state"),
		NodePath(".:net_aperture"),
		NodePath(".:net_riding"),
		NodePath(".:net_floor")
	]:
		assert_true(config.property_get_spawn(path))
	# Applying a late snapshot midway through closing must not restart a full slide.
	_cab.net_state = ElevatorCab.State.CLOSING
	_cab.net_aperture = 0.35
	_cab._update_doors()
	assert_almost_eq((_cab.get_node("Car/Doors/LeftLeaf") as Node3D).position.x, -1.275, 0.0001)
	assert_almost_eq((_cab.get_node("Car/Doors/RightLeaf") as Node3D).position.x, 1.275, 0.0001)
	_cab.entity._on_session_changed(Network.Mode.OFFLINE)
	assert_eq(_cab.net_state, ElevatorCab.State.CLOSED)
	assert_eq(_cab.net_aperture, 0.0)
