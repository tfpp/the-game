extends GutTest
## Real transport pins authenticated chat dispatch and owner-only teleport delivery.

const Chat := preload("res://features/chat_box/chat_box.gd")
const ROOM := preload("res://features/dev_room/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer, owner: int) -> Node:
	var root := Node.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var chat := Chat.new()
	chat.name = "Chat"
	root.add_child(chat)
	chat.get_node("DiscordRelay")._configured = true
	var room := ROOM.instantiate()
	room.name = "dev_room"
	root.add_child(room)
	var player := PLAYER.instantiate() as Player
	player.name = "Traveler"
	player.set_multiplayer_authority(owner)
	root.add_child(player)
	player.set_physics_process(false)
	player.net_position = Vector3(0, 1.2, 0)
	return root


func test_remote_command_moves_only_sender_and_stays_private() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var owner := client_peer.get_unique_id()
	var server := _branch("Server", server_peer, owner)
	var client := _branch("Client", client_peer, owner)
	var chat := client.get_node("Chat")
	watch_signals(server.get_node("Chat"))
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5.0
		)
	)
	var player := client.get_node("Traveler") as Player
	var start := player.net_position
	client.get_node("dev_room").handle_chat_command(owner, "warp dev")
	assert_eq(player.net_position, start, "Clients cannot apply travel directly")
	chat.request_chat_command.rpc_id(1, "warp dev")
	var arrival := client.get_node("dev_room/Room/Arrival") as Marker3D
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return player.net_position == arrival.global_position, 5.0
		)
	)
	assert_signal_not_emitted(server.get_node("Chat"), "message_accepted")
	chat.request_chat_message.rpc_id(1, "!warp casino")
	await RealTime.wait(get_tree(), 0.1)
	assert_signal_not_emitted(server.get_node("Chat"), "message_accepted")
	assert_eq(player.net_position, arrival.global_position)
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("Late", late_peer, owner)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	assert_eq((late.get_node("Traveler") as Player).net_position, start, "No warp event replay")
