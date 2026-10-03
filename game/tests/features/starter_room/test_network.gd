extends GutTest
## Real transport verifies sender lookup, owner-only transition and silent late join.

const FEATURE := preload("res://features/starter_room/feature.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer) -> OperationsVan:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var mall := preload("res://features/strip_mall/feature.tscn").instantiate() as Node3D
	mall.name = "strip_mall"
	root.add_child(mall)
	var feature := FEATURE.instantiate() as Node3D
	feature.name = "StarterRoom"
	root.add_child(feature)
	(feature.get_node("Room") as StreamedRoom).set_physics_process(false)
	var van := feature.get_node("Room/Van") as OperationsVan
	van.set_physics_process(false)
	van.panel.set_process(false)
	return van


func test_authenticated_travel_is_owner_only_and_not_replayed_to_late_joiners() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("Client", client_peer)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5
		)
	)
	var peer := client_peer.get_unique_id()
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.position = server.to_global(Vector3(-1.6, 1, 1))
	player.net_position = player.position
	# Only server needs the lookup mirror; this test isolates requests, not movement sync.
	player.get_node("Sync").free()
	server.get_parent().get_parent().add_child(player)
	player.set_physics_process(false)
	watch_signals(client.entity)
	watch_signals(server.entity)
	client.entity.request_action(&"travel", {"zone": 4, "peer": 1})
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return get_signal_emit_count(client.entity, "request_finished") == 1,
			5
		)
	)
	assert_true(server._pending.is_empty())
	client.use()
	assert_true(await REAL_TIME.wait_until(get_tree(), client.panel.is_open, 5))
	assert_false(server.panel.is_open())
	client.request_trip(4)
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return server._pending.has(peer), 5)
	)
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return client.panel._travelling, 5)
	)
	var client_room := client.arrival(4).get_parent() as StreamedRoom
	assert_true(client_room.arrival_held(), "private departure preloads the mall")
	assert_eq(server._pending[peer]["zone"], 4)
	assert_false(client._pending.has(peer), "client cannot commit shared state")
	assert_signal_not_emitted(server.entity, "event_received")
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("Late", late_peer)
	watch_signals(late.entity)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5
		)
	)
	assert_false(late.panel.is_open())
	assert_false((late.arrival(4).get_parent() as StreamedRoom).is_loaded())
	assert_signal_not_emitted(late.entity, "event_received")
	late.entity.send_event(&"depart", {"zone": 0}, peer)
	assert_signal_not_emitted(late.entity, "event_received")
	client_peer.close()
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return server._pending.is_empty(), 5)
	)
