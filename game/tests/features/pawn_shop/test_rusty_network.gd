extends GutTest
## Actual transport checks private replies and inherited late-join life replication.

const RUSTY := preload("res://features/pawn_shop/rusty_hogg.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const REAL_TIME := preload("res://tests/fixtures/real_time.gd")

var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()


func _branch(title: String, peer: ENetMultiplayerPeer) -> StationaryPatron:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var rusty := RUSTY.instantiate() as StationaryPatron
	rusty.name = "Rusty"
	root.add_child(rusty)
	rusty.set_physics_process(false)
	return rusty


func _client(port: int, title: String) -> StationaryPatron:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	return _branch(title, peer)


func test_private_reply_and_silent_late_join_with_server_respawn() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	var port := server_peer.host.get_local_port()
	var client := _client(port, "Client")
	var other := _client(port, "Other")
	var peer := client.multiplayer.get_unique_id()
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	server.get_parent().add_child(player)
	player.set_physics_process(false)
	player.net_position = Vector3(1, 0.95, 0)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	var talk := client.get_node("Talk") as NetworkedInteraction
	var other_talk := other.get_node("Talk") as NetworkedInteraction
	var server_talk := server.get_node("Talk") as NetworkedInteraction
	watch_signals(talk)
	watch_signals(other_talk)
	watch_signals(server_talk)
	talk.request_use()
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return get_signal_emit_count(talk, "event_received") == 1,
			5.0
		)
	)
	assert_signal_not_emitted(other_talk, "event_received")
	assert_signal_not_emitted(server_talk, "event_received")
	assert_eq(talk._evaluate(peer, &"use", {}), NetworkedEntity.Result.DENIED)
	server.take_hit(peer)
	var late := _client(port, "Late")
	var late_talk := late.get_node("Talk") as NetworkedInteraction
	watch_signals(late_talk)
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return not late.net_alive, 5.0)
	)
	assert_false(late._body.visible)
	assert_signal_not_emitted(late_talk, "event_received", "no old dialogue on late join")
	late.take_hit(late.multiplayer.get_unique_id())
	late._physics_process(100.0)
	assert_false(late.net_alive, "only the server can respawn Rusty")
	server._physics_process(StationaryPatron.RESPAWN_DELAY_S)
	assert_true(await REAL_TIME.wait_until(get_tree(), func() -> bool: return late.net_alive, 5.0))
	assert_signal_not_emitted(late_talk, "event_received", "respawn does not replay dialogue")
