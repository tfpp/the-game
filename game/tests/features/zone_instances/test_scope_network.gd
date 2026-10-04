extends GutTest
## Real transport checks state/event privacy and membership revocation.

const COUNTER := preload("res://tests/fixtures/networked_counter.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer, owner: int) -> ZoneScope:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var scope := ZoneScope.new()
	scope.name = "Instance"
	scope.members = [owner]
	var counter := COUNTER.instantiate()
	counter.name = "Counter"
	scope.add_child(counter)
	root.add_child(scope)
	return scope


func test_only_members_receive_state_and_events_and_can_mutate() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var driver_peer := ENetMultiplayerPeer.new()
	assert_eq(driver_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var owner := driver_peer.get_unique_id()
	var server := _branch("Server", server_peer, owner)
	var driver := _branch("Driver", driver_peer, owner)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5.0
		)
	)
	var driver_entity := driver.get_node("Counter/NetworkedEntity") as NetworkedEntity
	driver_entity.request_action(&"add", {"amount": 3})
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return driver.get_node("Counter").value == 10, 5.0
		)
	)
	var observer_peer := ENetMultiplayerPeer.new()
	assert_eq(observer_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var observer := _branch("Observer", observer_peer, owner)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	var observer_entity := observer.get_node("Counter/NetworkedEntity") as NetworkedEntity
	watch_signals(driver_entity)
	watch_signals(observer_entity)
	var server_entity := server.get_node("Counter/NetworkedEntity") as NetworkedEntity
	server_entity.send_event(&"blast")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return get_signal_emit_count(driver_entity, "event_received") == 1,
			5.0
		)
	)
	observer_entity.request_action(&"add", {"amount": 3})
	await RealTime.wait(get_tree(), 0.15)
	assert_eq(observer.get_node("Counter").value, 7, "Unrelated late peer gets no state")
	assert_eq(server.get_node("Counter").value, 10, "Outsider's valid request is rejected")
	assert_signal_not_emitted(observer_entity, "event_received")
	server.replace_members([])
	driver_entity.request_action(&"add", {"amount": 3})
	await RealTime.wait(get_tree(), 0.1)
	assert_eq(server.get_node("Counter").value, 10, "Leaving immediately revokes authority")
	server.replace_members([owner, observer_peer.get_unique_id()])
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return observer.get_node("Counter").value == 10, 5.0
		)
	)
	observer_entity.request_action(&"add", {"amount": 2})
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return driver.get_node("Counter").value == 12, 5.0
		)
	)
