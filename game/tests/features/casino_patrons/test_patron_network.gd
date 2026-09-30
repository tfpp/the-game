extends GutTest
## Real transport verifies the migrated shared patron state and follower authority.

const TRUMP := preload("res://features/casino_patrons/trump.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for branch: Node in _roots:
		var path := branch.get_path()
		branch.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()


func _branch(title: String, peer: ENetMultiplayerPeer) -> CasinoPatron:
	var branch := Node3D.new()
	branch.name = title
	add_child(branch)
	_roots.append(branch)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, branch.get_path())
	var npc := TRUMP.instantiate() as CasinoPatron
	npc.name = "NPC"
	npc.look = PatronModel.TRUMP_LOOK
	branch.add_child(npc)
	npc.set_physics_process(false)
	return npc


func test_late_join_receives_follower_state_and_clients_cannot_change_it() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	server.position = Vector3(8.5, -1.5, -7)
	server.net_position = server.position
	server.net_yaw = 1.25
	server.net_ragdoll = true
	server.net_fall_dir = Vector3.RIGHT
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("Client", client_peer)
	await RealTime.wait_until(
		get_tree(),
		func() -> bool:
			return (
				client.net_ragdoll
				and client.net_position == server.net_position
				and is_equal_approx(client.net_yaw, server.net_yaw)
			),
		5.0
	)
	assert_true(client.net_ragdoll, "late join sees knockdown")
	assert_eq(client.net_position, server.net_position)
	assert_almost_eq(client.net_yaw, server.net_yaw, 0.001)
	assert_eq(client.net_fall_dir, Vector3.RIGHT)
	client.take_hit(client_peer.get_unique_id())
	client._physics_process(100.0)
	assert_true(client.net_alive, "client cannot kill or simulate the NPC")
	assert_true(client.net_ragdoll)
	var talk := client.get_node("Talk") as NetworkedInteraction
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	talk.request_action(&"use", {"peer": 1})
	await wait_physics_frames(3)
	assert_true(server.net_alive)
	server.take_hit(1)
	for frame: int in 120:
		await get_tree().physics_frame
		if not client.net_alive:
			break
	assert_false(client.net_alive)
	server._physics_process(CasinoPatron.RESPAWN_DELAY_S)
	for frame: int in 120:
		await get_tree().physics_frame
		if client.net_alive:
			break
	assert_true(client.net_alive, "respawn replicates")
