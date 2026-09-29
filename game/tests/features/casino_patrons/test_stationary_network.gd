extends GutTest
## Separate multiplayer APIs exercise actual transport and late-join replication.

const DEALER := preload("res://features/casino_patrons/stationary_dealer.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer) -> StationaryPatron:
	var branch := Node3D.new()
	branch.name = title
	add_child(branch)
	_roots.append(branch)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, branch.get_path())
	var npc := DEALER.instantiate() as StationaryPatron
	npc.name = "NPC"
	branch.add_child(npc)
	npc.set_physics_process(false)
	return npc


func test_late_client_receives_death_cannot_revive_and_sees_server_respawn() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	server.take_hit(1)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("Client", client_peer)
	for _frame: int in 120:
		await get_tree().physics_frame
		if not client.net_alive:
			break
	assert_false(client.net_alive, "late join receives existing death")
	assert_false(client._body.visible)
	client._physics_process(100.0)
	assert_false(client.net_alive, "clients never run the respawn timer")
	server._physics_process(StationaryPatron.RESPAWN_DELAY_S)
	for _frame: int in 120:
		await get_tree().physics_frame
		if client.net_alive:
			break
	assert_true(client.net_alive, "server respawn reaches the client")
	client.take_hit(client_peer.get_unique_id())
	assert_true(client.net_alive, "client cannot commit a weapon hit locally")
	client._entity.request_action(&"death")
	await wait_physics_frames(3)
	assert_true(server.net_alive, "forged death requests have no registered action")
	watch_signals(client._entity)
	server.take_hit(1)
	for _frame: int in 120:
		await get_tree().physics_frame
		if not client.net_alive:
			break
	assert_false(client.net_alive, "new deaths also replicate")
	assert_signal_emitted(client._entity, "event_received")
