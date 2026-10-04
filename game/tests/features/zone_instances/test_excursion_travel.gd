extends GutTest

const ZONES := preload("res://features/zone_instances/feature.tscn")
const ELEVATOR := preload("res://features/elevator/elevator.tscn")
const PLAYER := preload("res://core/player/player.tscn")


func test_cancelled_transfers_release_cabs_only_after_last_rider() -> void:
	var zones := ZONES.instantiate() as ZoneInstances
	add_child_autofree(zones)
	zones.set_physics_process(false)
	var source_kit := ELEVATOR.instantiate() as Node3D
	var arrival_kit := ELEVATOR.instantiate() as Node3D
	add_child_autofree(source_kit)
	add_child_autofree(arrival_kit)
	var source := source_kit.get_node("Cab") as ElevatorCab
	var arrival := arrival_kit.get_node("Cab") as ElevatorCab
	source.set_physics_process(false)
	arrival.set_physics_process(false)
	source.server_begin_ride()
	arrival.server_begin_ride()
	zones._transfers[2] = {"source": source, "arrival": arrival}
	zones._transfers[3] = {"source": source, "arrival": arrival}
	zones._erase_transfer(2)
	assert_true(source.net_riding, "Another rider still owns the departure")
	assert_true(arrival.net_riding, "Another rider still reserves the destination")
	zones._on_peer_disconnected(3)
	assert_false(source.net_riding)
	assert_false(arrival.net_riding)
	assert_true(source.request_doors(), "Cancelled trip can be boarded again")


func test_crown_departure_waits_for_loaded_map_and_round_trip_preserves_cab_pose() -> void:
	var zones := ZONES.instantiate() as ZoneInstances
	add_child_autofree(zones)
	zones.set_physics_process(false)
	var destination := SlumArrivalPoint.new()
	destination.slum_name = "Rain Alleys"
	add_child_autofree(destination)
	var elevator := ELEVATOR.instantiate() as Node3D
	elevator.rotation.y = .6
	add_child_autofree(elevator)
	var crown := elevator.get_node("Cab") as ElevatorCab
	crown.set_physics_process(false)
	var player := PLAYER.instantiate() as Player
	var offset := Vector3(.7, .95, -.4)
	player.position = crown.car.to_global(offset)
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	player.yaw = .9
	player.net_yaw = .9
	player.pitch = -.2
	var start := player.global_position
	assert_true(crown.request_doors())
	crown._server_advance(ElevatorCab.DOOR_SLIDE_S)
	crown._server_advance(ElevatorCab.BOARDING_S)
	crown._server_advance(ElevatorCab.DOOR_SLIDE_S)
	var id := zones.registry.instance_of(1)
	assert_ne(id, -1)
	var instance := zones.scope_for(id) as SlumInstance
	assert_not_null(instance)
	assert_eq(instance.destination, SlumInstance.Destination.ALLEYS)
	instance.return_cab.set_physics_process(false)
	var trip: Dictionary = zones._transfers[1]
	trip["after"] = 0
	instance.ready_peers.clear()
	zones._physics_process(0)
	assert_eq(player.global_position, start, "No teleport until owning client loaded collision")
	instance.ready_peers.append(1)
	zones._physics_process(0)
	assert_true(player.global_position.is_equal_approx(instance.return_cab.car.to_global(offset)))
	assert_almost_eq(wrapf(player.yaw - (PI + .3), -PI, PI), 0.0, .0001)
	assert_almost_eq(player.pitch, -.2, .0001)
	assert_eq(instance.return_cab.net_state, ElevatorCab.State.OPENING)
	instance.return_cab.net_state = ElevatorCab.State.CLOSED
	zones.depart_cab(instance.return_cab, [player] as Array[Player])
	assert_true(zones._transfers.has(1))
	assert_eq(crown.net_state, ElevatorCab.State.CLOSED, "Return doors wait for riders")
	assert_true(crown.net_riding)
	assert_false(crown.request_doors(), "A reserved arrival cannot be opened early")
	trip = zones._transfers[1]
	trip["after"] = 0
	zones._physics_process(0)
	assert_lt(
		player.global_position.distance_to(start), .002, "Round trip retains placement to 2 mm"
	)
	assert_almost_eq(player.yaw, .9, .0001)
	assert_eq(zones.registry.instance_of(1), -1)
	assert_eq(crown.net_state, ElevatorCab.State.OPENING)
	assert_false(crown.net_riding)
	await wait_physics_frames(1)
	assert_false(is_instance_valid(instance))


func test_garage_copy_contains_all_five_decks_and_top_arrival() -> void:
	var zones := ZONES.instantiate() as ZoneInstances
	add_child_autofree(zones)
	var destination := Marker3D.new()
	add_child_autofree(destination)
	var instance := zones.create_excursion(
		[1] as Array[int], destination, SlumInstance.Destination.GARAGE, 73021
	)
	assert_not_null(instance)
	for deck: int in 5:
		assert_not_null(instance.get_node_or_null("Map/CrownGarage/Deck%d" % deck))
	assert_eq(instance.return_cab.get_parent().position.y, 16.0)
	var grid := instance.get_node("Map/CrownGarage/Structure/Content/Levels") as GridMap
	assert_eq(grid.get_used_cells().size(), 5)
	assert_false(
		(instance.get_node("Map/CrownGarage/Lift") as ProceduralMovingLift).casino_connection
	)
	var world := instance.get_node("Map/CrownGarage") as Node3D
	assert_eq(world.get_node("Enemies").get_child_count(), 19)
	assert_eq(world.get_node("Loot").get_child_count(), 20)
	await wait_physics_frames(1)
	for node: Node in world.get_node("Enemies").get_children():
		var enemy := node as GarageEnemy
		var query := PhysicsRayQueryParameters3D.create(
			enemy.global_position + Vector3.UP * .2, enemy.global_position - Vector3.UP * .2, 1
		)
		assert_false(
			world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),
			"Enemy marker has floor support"
		)
	var crate := world.get_node("Loot/B1Crate0") as LootContainer
	crate.regenerate()
	assert_true(crate.net_searched)
	zones.registry.leave(1)
	await wait_physics_frames(1)
	var next := zones.create_excursion(
		[1] as Array[int], destination, SlumInstance.Destination.GARAGE, 73021
	)
	assert_false(
		(next.get_node("Map/CrownGarage/Loot/B1Crate0") as LootContainer).net_searched,
		"New instance resets loot without changing other runs"
	)
