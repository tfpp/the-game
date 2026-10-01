extends GutTest
## Real server/client transport, including late terminal-state snapshots.

const BOMB := preload("res://features/timed_bomb/feature.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []
var _path := "user://test_bomb_network_337.json"


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	DirAccess.remove_absolute(_path)
	_roots.clear()
	_peers.clear()


func _branch(title: String, peer: ENetMultiplayerPeer) -> Node3D:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var bomb := BOMB.instantiate()
	bomb.practice_path = _path
	root.add_child(bomb)
	bomb.set_process(false)
	return bomb


func test_late_join_terminal_state_public_fields_and_rejected_client_actions() -> void:
	DirAccess.remove_absolute(_path)
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	server._fetch()
	server.net_state = "defused"
	server.net_remaining = 12345
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("Client", client_peer)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return client.net_state == "defused", 5.0
		)
	)
	assert_eq(client.net_remaining, 12345)
	assert_true(client.net_available)
	assert_null(client._local, "Secret practice data never reaches a client")
	watch_signals(client.entity)
	client.entity.request_action(&"reset")
	client.entity.request_action(&"defuse", {"code": "0042", "peer": 1})
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return get_signal_emit_count(client.entity, "request_finished") == 2,
			5.0
		)
	)
	assert_eq(server.net_state, "defused")
	assert_false(client._defuse(1, {"code": "0042"}))
	server.net_state = "exploded"
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return client.net_state == "exploded", 5.0
		)
	)
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("Late", late_peer)
	watch_signals(late.entity)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return late.net_state == "exploded", 5.0
		)
	)
	assert_signal_not_emitted(late.entity, "event_received", "Old explosions do not replay")
	late._process(0)
	assert_true(late.get_node("Wreck").visible)
	assert_false(late.get_node("Body").visible)
