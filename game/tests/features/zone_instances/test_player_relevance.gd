extends GutTest
## Real spawned players retain identities/owner RPCs while private movement is filtered.

const ZONES := preload("res://features/zone_instances/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
var _roots: Array[Node3D] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()


func _branch(title: String, peer: ENetMultiplayerPeer) -> Node3D:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var players := Node3D.new()
	players.name = "Players"
	root.add_child(players)
	root.add_child(ZONES.instantiate())
	var spawner := MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player
	root.add_child(spawner)
	return root


func _spawn_player(data: Variant) -> Node:
	var info := data as Dictionary
	var player := PLAYER.instantiate() as Player
	player.name = str(info["peer"])
	player.set_multiplayer_authority(int(info["peer"]))
	player.position = Vector3(2, 1, 0)
	player.net_position = player.position
	player.set_physics_process(false)
	return player


func test_other_instances_get_no_movement_but_owner_and_server_keep_player() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	var clients: Array[Node3D] = []
	var owners: Array[int] = []
	for index: int in 3:
		var peer := ENetMultiplayerPeer.new()
		assert_eq(peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
		clients.append(_branch("Client%d" % index, peer))
		owners.append(peer.get_unique_id())
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 3, 5.0
		)
	)
	var spawner := server.get_node("PlayerSpawner") as MultiplayerSpawner
	for owner: int in owners:
		spawner.spawn({"peer": owner})
	var path := "Players/" + str(owners[0])
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return clients[2].has_node(path), 5.0)
	)
	await RealTime.wait(get_tree(), .1)
	for root: Node3D in _roots:
		for player: Node in root.get_node("Players").get_children():
			player.set_physics_process(false)
	var zones := server.get_node("ZoneInstances") as ZoneInstances
	var marker := Marker3D.new()
	server.add_child(marker)
	zones.registry.create([owners[0], owners[1]] as Array[int], marker)
	zones.registry.create([owners[2]] as Array[int], marker)
	var third_zones := clients[2].get_node("ZoneInstances") as ZoneInstances
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return third_zones.net_peer_instances.size() == 3, 5.0
		)
	)
	await RealTime.wait(get_tree(), .1)
	var owner_player := clients[0].get_node(path) as Player
	var partner_player := clients[1].get_node(path) as Player
	var other_player := clients[2].get_node(path) as Player
	var server_player := server.get_node(path) as Player
	var old_position := other_player.net_position
	owner_player.net_position = Vector3(10, 1, 0)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return server_player.net_position.x == 10 and partner_player.net_position.x == 10,
			5.0
		)
	)
	await RealTime.wait(get_tree(), .1)
	assert_eq(other_player.net_position, old_position, "No movement goes to another instance")
	assert_false(other_player.visible)
	assert_true((other_player.get_node("Collider") as CollisionShape3D).disabled)
	assert_true(clients[2].has_node(path), "Global identity remains available for chat and roster")
	server_player.server_teleport.rpc_id(owners[0], Vector3(11, 1, 0), .4)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return owner_player.net_position.x == 11, 5.0
		)
	)
	for owner: int in owners:
		zones.registry.leave(owner)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return third_zones.net_peer_instances.is_empty(), 5.0
		)
	)
	owner_player.net_position = Vector3(12, 1, 0)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return other_player.net_position.x == 12 and other_player.visible,
			5.0
		)
	)
