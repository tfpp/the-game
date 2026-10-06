extends GutTest
## Production transport: an owner boards, an observer misses it, and a late peer joins.

const METRO := preload("res://features/metro/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
var roots: Array[Node3D] = []
var peers: Array[WebSocketMultiplayerPeer] = []


func after_each() -> void:
	for root: Node3D in roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: WebSocketMultiplayerPeer in peers:
		peer.close()
	roots.clear()
	peers.clear()


func branch(title: String, transport: WebSocketMultiplayerPeer) -> Node3D:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	roots.append(root)
	peers.append(transport)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = transport
	get_tree().set_multiplayer(api, root.get_path())
	var features := Node.new()
	features.name = "Features"
	root.add_child(features)
	var metro := METRO.instantiate() as MetroService
	features.add_child(metro)
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	var visibility := RoomVisibility.new()
	visibility.name = "Visibility"
	features.add_child(visibility)
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = spawn_player
	root.add_child(spawner)
	return root


func spawn_player(data: Variant) -> Node:
	var info := data as Dictionary
	var player := PLAYER.instantiate() as Player
	player.name = str(info["peer"])
	player.set_multiplayer_authority(int(info["peer"]))
	player.position = info["position"]
	player.net_position = player.position
	player.set_physics_process(false)
	return player


func connect_client(port: int, title: String) -> Node3D:
	var peer := Network.create_transport()
	assert_eq(peer.create_client("ws://127.0.0.1:%d" % port), OK)
	return branch(title, peer)


func test_boarding_departure_late_join_and_arrival_keep_shared_state() -> void:
	var transport := Network.create_transport()
	var port := randi_range(20000, 40000)
	assert_eq(transport.create_server(port), OK)
	var server := branch("Server", transport)
	var owner := connect_client(port, "Owner")
	var observer := connect_client(port, "Observer")
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5
		)
	)
	var rider_id := owner.multiplayer.get_unique_id()
	var observer_id := observer.multiplayer.get_unique_id()
	var metro := server.get_node("Features/Metro") as MetroService
	var owner_metro := owner.get_node("Features/Metro") as MetroService
	var observer_metro := observer.get_node("Features/Metro") as MetroService
	metro.net_time = 5
	metro._update_collision()
	var origin := MetroRules.station_position(0)
	var offset := Vector3(0, 2.1244, 25.36)
	var spawner := server.get_node("PlayerSpawner") as MultiplayerSpawner
	spawner.spawn({"peer": rider_id, "position": origin + offset})
	spawner.spawn({"peer": observer_id, "position": origin + Vector3(4, 2.1244, 25.36)})
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					owner.get_node("Players").get_child_count() == 2
					and observer.get_node("Players").get_child_count() == 2
				),
			5
		)
	)
	for root: Node3D in roots:
		for player: Node in root.get_node("Players").get_children():
			player.set_physics_process(false)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					owner_metro.stations[0].is_loaded() and observer_metro.stations[0].is_loaded()
				),
			5
		)
	)
	metro.net_time = MetroRules.OPEN + MetroRules.DWELL
	metro._begin_boarding_transfer()
	assert_true(metro.transfers.pending.has(rider_id))
	assert_false(
		metro.transfers._may_ready(
			observer_id, {"token": metro.transfers.pending[rider_id]["token"]}
		)
	)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return bool(metro.transfers.pending[rider_id]["ready"]), 5
		)
	)
	metro.transfers._physics_process(1.3)
	metro.net_time = MetroRules.DEPART + 2
	metro._update_collision()
	var player := server.get_node("Players/" + str(rider_id)) as Player
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return player.net_position.distance_to(MetroRules.ride_position(0) + offset) < 0.01,
			5
		)
	)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					observer_metro.net_passengers.has(rider_id)
					and observer_metro.stations[0].train.position.z < -40
				),
			5
		)
	)
	assert_false(observer_metro.rides[0].is_loaded())
	assert_false(owner_metro.stations[2].is_loaded())
	var late := connect_client(port, "Late")
	var late_metro := late.get_node("Features/Metro") as MetroService
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					late_metro.net_passengers.has(rider_id)
					and absf(late_metro.net_time - metro.net_time) < 0.01
				),
			5
		)
	)
	assert_almost_eq(late_metro.net_time, metro.net_time, 0.01)
	assert_eq(late_metro.net_cycle, metro.net_cycle)
	metro.net_time = MetroRules.PERIOD - 3
	metro._begin_arrival_transfer()
	metro.net_time = 0
	metro.net_cycle = 1
	metro._update_collision()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return bool(metro.transfers.pending[rider_id]["ready"]), 5
		)
	)
	metro.transfers._physics_process(3.1)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					player.net_position.distance_to(MetroRules.station_position(1) + offset) < 0.01
				),
			5
		)
	)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return late_metro.net_passengers.is_empty(), 5
		)
	)
	var missed := server.get_node("Players/" + str(observer_id)) as Player
	assert_lt(missed.net_position.distance_to(origin + Vector3(4, 2.1244, 25.36)), 0.01)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return owner_metro.stations[1].is_loaded() and not owner_metro.rides[0].is_loaded(),
			5
		)
	)
