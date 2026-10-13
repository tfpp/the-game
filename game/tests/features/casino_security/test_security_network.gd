extends GutTest
## Real server/client coverage over ENet: a detention and the answering guard
## replicate to the offender and a late joiner, only the offender hears the guard,
## clients cannot change or start detentions, and disconnecting clears it.

const SECURITY := preload("res://features/casino_security/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")

var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func before_each() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.25, 50)
	shape.shape = box
	floor.add_child(shape)
	floor.position = Vector3(0, -0.125, 0)
	add_child_autofree(floor)


func after_each() -> void:
	for root: Node in _roots:
		if not is_instance_valid(root):
			continue
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()


func _branch(title: String, peer: ENetMultiplayerPeer) -> Node:
	var root := Node.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var security := SECURITY.instantiate()
	security.name = "CasinoSecurity"
	root.add_child(security)
	return root


func _client(port: int, title: String) -> Node:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	return _branch(title, peer)


func _security(root: Node) -> CasinoSecurity:
	return root.get_node("CasinoSecurity") as CasinoSecurity


func test_detention_replicates_and_disconnect_clears_it() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var port := transport.host.get_local_port()
	var client := _client(port, "Client")
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return client.multiplayer.get_unique_id() > 1, 5
		)
	)
	var peer := client.multiplayer.get_unique_id()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return peer in server.multiplayer.get_peers(), 5
		)
	)
	var server_security := _security(server)
	server_security.build_grid_now()
	var offender := PLAYER.instantiate() as Player
	offender.name = str(peer)
	offender.set_multiplayer_authority(peer)
	offender.position = Vector3(-4, 0.92, -10)
	offender.net_position = offender.position
	server.add_child(offender)
	offender.set_physics_process(false)
	offender.set_process(false)
	# A client can neither start nor rewrite a detention.
	assert_false(_security(client).report_misconduct(peer, &"firearm"))
	assert_true(server_security.detentions.is_empty())
	var said: Array[String] = []
	_security(client).entity.event_received.connect(
		func(event: StringName, payload: Dictionary) -> void:
			if event == &"say":
				said.append(str(payload["text"]))
	)
	assert_true(server_security.report_misconduct(peer, &"vandalism"))
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return _security(client).phase_for(peer) == SecurityRules.Phase.HELD,
			5
		),
		"the offender's client sees the detention"
	)
	assert_eq(_security(client).offence_for(peer), &"vandalism")
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return not said.is_empty(), 5)
	)
	assert_eq(said[0], SecurityRules.callout(&"vandalism"), "the guard's line reaches them")
	var client_guard := _security(client).guard_for(peer)
	assert_eq(client_guard.net_carrying, peer)
	assert_eq(client_guard.net_state, SecurityRules.GuardState.RESPONDING)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				var guard := server_security.guard_for(peer)
				return client_guard.net_position.distance_to(guard.net_position) < 0.5,
			5
		),
		"the guard's walk replicates"
	)
	# A late joiner gets the current detention and guard state.
	var late := _client(port, "Late")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return _security(late).phase_for(peer) != SecurityRules.Phase.NONE,
			5
		),
		"late join sees the detention"
	)
	assert_eq(_security(late).guard_for(peer).net_carrying, peer)
	# Rewriting the snapshot on a client changes nothing on the server.
	_security(client).detentions = {}
	await RealTime.wait(get_tree(), 0.2)
	assert_true(server_security.detentions.has(peer))
	# Disconnecting the offender clears it everywhere and sends the guard home.
	var client_index := _roots.find(client)
	var path := client.get_path()
	client.free()
	get_tree().set_multiplayer(null, path)
	_peers[client_index].close()
	_roots[client_index] = null
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return _security(late).detentions.is_empty(), 5
		),
		"disconnect clears the detention"
	)
	assert_true(server_security.detentions.is_empty())
	for guard: CasinoGuard in server_security.guards():
		assert_true(guard.is_free(), "%s back on watch" % guard.name)
	offender.queue_free()
