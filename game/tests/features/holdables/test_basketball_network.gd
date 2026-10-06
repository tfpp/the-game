extends GutTest
## Real server/client coverage of throwing, late joins, pickup races and disconnects.

const FEATURE := preload("res://features/holdables/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
const BALL_PATH := "Holdables/Thrown/Thrown1"
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
	Controls.pause()


func _branch(title: String, peer: ENetMultiplayerPeer) -> Node:
	var root := Node.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var feature := FEATURE.instantiate()
	feature.name = "Holdables"
	root.add_child(feature)
	return root


func _client(port: int, title: String) -> Node:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	return _branch(title, peer)


func _player(root: Node, peer: int, at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.position = at
	player.net_position = at
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	return player


func test_throw_late_join_disconnect_and_competing_pickups() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var client := _client(transport.host.get_local_port(), "Client")
	var peer := client.multiplayer.get_unique_id()
	var hand_path := "Holdables/Hands/%d" % peer
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return client.has_node(hand_path), 5)
	)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 1, 40)
	collider.shape = shape
	collider.position.y = -0.5
	floor_body.add_child(collider)
	server.add_child(floor_body)
	_player(server, peer, Vector3(0, 0.9, 0))
	var hand := server.get_node(hand_path) as Hand
	hand.net_item_id = "ball"
	(client.get_node(hand_path) as Hand).request_primary_action.rpc_id(1)
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return client.has_node(BALL_PATH), 5)
	)
	assert_eq(hand.net_item_id, "")
	var ball := server.get_node(BALL_PATH) as ThrownItem
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return ball.net_landed and ball.velocity.length() < .05, 5
		)
	)
	ball.set_physics_process(false)
	var current := ball.net_position
	assert_gt(current.distance_to(ball.from), 1.0)
	var late := _client(transport.host.get_local_port(), "Late")
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return late.has_node(BALL_PATH), 5)
	)
	var late_ball := late.get_node(BALL_PATH) as ThrownItem
	assert_eq(late_ball.net_position, current, "Late join receives the current position")
	assert_true(late_ball.net_landed, "Late join can recover an already-thrown ball")
	assert_false(late_ball.is_physics_processing(), "Only the server simulates collisions")
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return late_ball.position.distance_to(current) < .1, 5
		),
		"View converges to the snapshot"
	)
	var late_peer := late.multiplayer.get_unique_id()
	var late_hand := server.get_node("Holdables/Hands/%d" % late_peer) as Hand
	var late_player := _player(server, late_peer, Vector3(30, 1, 30))
	late_ball.use()
	await RealTime.wait(get_tree(), .1)
	assert_eq(late_hand.net_item_id, "", "Distant clients cannot claim the ball")
	# A connected peer cannot command another player's hand.
	hand.net_item_id = "ball"
	(late.get_node(hand_path) as Hand).request_primary_action.rpc_id(1)
	await RealTime.wait(get_tree(), .1)
	assert_eq(hand.net_item_id, "ball")
	hand.net_item_id = ""
	var client_path := client.get_path()
	_roots.erase(client)
	client.free()
	get_tree().set_multiplayer(null, client_path)
	_peers[1].close()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not server.has_node(hand_path), 5
		)
	)
	assert_true(server.has_node(BALL_PATH), "Thrower disconnect leaves the ball in the hub")
	var rival := _client(transport.host.get_local_port(), "Rival")
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return rival.has_node(BALL_PATH), 5)
	)
	var rival_peer := rival.multiplayer.get_unique_id()
	_player(server, rival_peer, current + Vector3.UP * .9)
	late_player.position = current + Vector3.UP * .9
	late_player.net_position = late_player.position
	late_ball.use()
	(rival.get_node(BALL_PATH) as ThrownItem).use()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not server.has_node(BALL_PATH), 5
		)
	)
	var rival_hand := server.get_node("Holdables/Hands/%d" % rival_peer) as Hand
	var collected := int(late_hand.net_item_id == "ball") + int(rival_hand.net_item_id == "ball")
	assert_eq(collected, 1, "Concurrent requests collect exactly one ball")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return not late.has_node(BALL_PATH) and not rival.has_node(BALL_PATH),
			5
		)
	)


func test_late_join_receives_in_flight_position_without_restarting_simulation() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var holdables := server.get_node("Holdables")
	holdables.spawn_thrown_item("ball", Vector3(0, 2, 0), Vector3(5, 0, 0))
	var ball := server.get_node(BALL_PATH) as ThrownItem
	ball.set_physics_process(false)
	for frame in range(12):
		ball._physics_process(1.0 / 64.0)
	var current := ball.net_position
	assert_false(ball.net_landed)
	assert_gt(current.distance_to(ball.from), 1.0)
	var late := _client(transport.host.get_local_port(), "Late")
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return late.has_node(BALL_PATH), 5)
	)
	var replica := late.get_node(BALL_PATH) as ThrownItem
	assert_eq(replica.net_position, current)
	assert_false(replica.net_landed)
	assert_false(replica.is_physics_processing())
	(late.get_node("Holdables")).spawn_thrown_item("ball", Vector3.ZERO, Vector3.ONE)
	assert_eq(late.get_node("Holdables/Thrown").get_child_count(), 1)
	assert_eq(server.get_node("Holdables/Thrown").get_child_count(), 1)
