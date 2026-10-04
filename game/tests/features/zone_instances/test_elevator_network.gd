extends GutTest
## Full Crown/garage round trip uses the production WebSocket transport unchanged.

const HUB := preload("res://features/casino_hub/gridmap/playable.tscn")
const ZONES := preload("res://features/zone_instances/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
var _roots: Array[Node3D] = []
var _peers: Array[WebSocketMultiplayerPeer] = []


func after_each() -> void:
	for root: Node3D in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: WebSocketMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()


func _branch(title: String, transport: WebSocketMultiplayerPeer) -> Node3D:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(transport)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = transport
	get_tree().set_multiplayer(api, root.get_path())
	root.add_child(HUB.instantiate())
	var features := Node.new()
	features.name = "Features"
	root.add_child(features)
	features.add_child(ZONES.instantiate())
	var visibility := RoomVisibility.new()
	visibility.name = "Visibility"
	features.add_child(visibility)
	var destination := SlumArrivalPoint.new()
	destination.slum_name = "Parking Garage"
	root.add_child(destination)
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player
	root.add_child(spawner)
	(root.get_node("Room/Casino/Elevator/Cab") as ElevatorCab).set_physics_process(false)
	return root


func _spawn_player(data: Variant) -> Node:
	var info := data as Dictionary
	var player := PLAYER.instantiate() as Player
	player.name = str(info["peer"])
	player.set_multiplayer_authority(int(info["peer"]))
	player.position = info["position"]
	player.net_position = player.position
	player.set_physics_process(false)
	return player


func test_two_riders_round_trip_over_transport_and_outsider_keeps_hub() -> void:
	var transport := Network.create_transport()
	var port := randi_range(20000, 40000)
	assert_eq(transport.create_server(port), OK)
	var server := _branch("Server", transport)
	var clients: Array[Node3D] = []
	var owners: Array[int] = []
	for index: int in 3:
		var peer := Network.create_transport()
		assert_eq(peer.create_client("ws://127.0.0.1:%d" % port), OK)
		clients.append(_branch("Client%d" % index, peer))
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 3, 5.0
		)
	)
	for client: Node3D in clients:
		owners.append(client.multiplayer.get_unique_id())
	var crown := server.get_node("Room/Casino/Elevator/Cab") as ElevatorCab
	var offsets: Array[Vector3] = [Vector3(-.5, .95, -.4), Vector3(.5, .95, -.4)]
	var spawner := server.get_node("PlayerSpawner") as MultiplayerSpawner
	for index: int in 3:
		var point := crown.car.to_global(offsets[index]) if index < 2 else Vector3(20, 1, 0)
		spawner.spawn({"peer": owners[index], "position": point})
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return clients[2].get_node("Players").get_child_count() == 3,
			5.0
		)
	)
	for root: Node3D in _roots:
		for player: Node in root.get_node("Players").get_children():
			player.set_physics_process(false)
	await RealTime.wait(get_tree(), .1)
	var riders: Array[Player] = []
	for index: int in 2:
		riders.append(server.get_node("Players/" + str(owners[index])) as Player)
		offsets[index] = crown.car.to_local(riders[index].net_position)
	var zones := server.get_node("Features/ZoneInstances") as ZoneInstances
	zones.depart_cab(crown, riders)
	var id := zones.registry.instance_of(owners[0])
	assert_ne(id, -1)
	assert_eq(zones.registry.instance_of(owners[1]), id)
	assert_eq(zones.registry.instance_of(owners[2]), -1)
	var instance := zones.scope_for(id) as SlumInstance
	instance.return_cab.set_physics_process(false)
	var run_path := "Features/ZoneInstances/Instances/" + str(instance.name)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return riders[0].net_position.z > 10000 and riders[1].net_position.z > 10000,
			5.0
		)
	)
	for index: int in 2:
		var owner_player := clients[index].get_node("Players/" + str(owners[index])) as Player
		assert_lt(
			owner_player.global_position.distance_to(
				instance.return_cab.car.to_global(offsets[index])
			),
			.003
		)
		assert_true(clients[index].has_node(run_path))
		(
			(clients[index].get_node(run_path + "/ReturnElevator/Cab") as ElevatorCab)
			. set_physics_process(false)
		)
	assert_false(clients[2].has_node(run_path))
	# F2: the shared Crown remains resident in the mechanics PR. Cosmetic
	# unloading and its dedicated assertions are deferred to Part 2.
	for client: Node3D in clients:
		assert_gt((client.get_node("Room/Casino/Floors") as GridMap).get_used_cells().size(), 0)
	instance.return_cab.net_state = ElevatorCab.State.CLOSED
	zones.depart_cab(instance.return_cab, riders)
	var return_started := Time.get_ticks_msec()
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					zones.registry.instance_of(owners[0]) == -1
					and zones.registry.instance_of(owners[1]) == -1
				),
			5.0
		)
	)
	for index: int in 2:
		var owner_player := clients[index].get_node("Players/" + str(owners[index])) as Player
		assert_true(
			await RealTime.wait_until(
				get_tree(),
				func() -> bool:
					return (
						owner_player.global_position.distance_to(
							crown.car.to_global(offsets[index])
						)
						< .003
					),
				5.0
			)
		)
		assert_gt(
			(clients[index].get_node("Room/Casino/Floors") as GridMap).get_used_cells().size(), 0
		)
	var return_msec := Time.get_ticks_msec() - return_started
	assert_gte(return_msec, 1000, "Riders experience the short ride before arrival")
	assert_lte(return_msec, 2000, "An already-loaded return meets the two-second ride budget")
	print("PHASE_ONE_RETURN_RIDE_MSEC ", return_msec)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return not clients[0].has_node(run_path) and not clients[1].has_node(run_path),
			5.0
		)
	)
