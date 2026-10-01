extends GutTest
## Real server/client transport exercises the existing chat RPCs and relay boundary.

const ChatBox := preload("res://features/chat_box/chat_box.gd")
const PlayerScene := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")

var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()


func _branch(title: String, peer: ENetMultiplayerPeer) -> CanvasLayer:
	var root := Node.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var chat := ChatBox.new()
	chat.name = "Chat"
	root.add_child(chat)
	# Keep this transport test disconnected from any deployment configuration.
	var relay := chat.get_node("DiscordRelay")
	relay._configured = true
	return chat


func test_clients_receive_public_chat_but_only_server_emits_for_discord() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var server := _branch("Server", server_peer)
	var client := _branch("Client", client_peer)
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(client_peer.get_unique_id())
	player.display_name = "Alice"
	server.get_parent().add_child(player)
	player.set_physics_process(false)
	watch_signals(server)
	watch_signals(client)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5.0
		)
	)
	client.request_chat_message("direct client call must not be accepted")
	assert_signal_not_emitted(client, "message_accepted")
	client.request_chat_message.rpc_id(1, "  hello  ")
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return client._log.get_child_count() == 1, 5.0
		)
	)
	assert_signal_emit_count(server, "message_accepted", 1)
	assert_signal_emitted_with_parameters(server, "message_accepted", ["Alice", "hello"])
	assert_signal_not_emitted(client, "message_accepted")
	assert_eq(client._log.get_child(0).text, ChatBox.format_line("Alice", "hello"))
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("Late", late_peer)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	assert_eq(late._log.get_child_count(), 0, "late joining never replays or re-exports history")
	client.request_chat_message.rpc_id(1, "second")
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return late._log.get_child_count() == 1, 5.0
		)
	)
	assert_signal_emit_count(server, "message_accepted", 2)
	assert_signal_not_emitted(client, "message_accepted")
