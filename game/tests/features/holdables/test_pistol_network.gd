extends GutTest
## Real transport checks reload ownership and an in-progress late-join snapshot.

const FEATURE := preload("res://features/holdables/feature.tscn")
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


func _hand(root: Node, peer: int) -> Hand:
	return root.get_node_or_null("Holdables/Hands/%d" % peer) as Hand


func test_reload_authority_and_late_join_elapsed_state() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	var port := server_peer.host.get_local_port()
	var client := _client(port, "Client")
	var peer := client.multiplayer.get_unique_id()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return _hand(client, peer) != null, 5.0
		)
	)
	var server_hand := _hand(server, peer)
	server_hand.set_process(false)
	var client_hand := _hand(client, peer)
	client_hand.set_process(false)
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	server.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	server_hand.net_item_id = "pistol"
	server_hand.inventory().collect("ammo:pistol:20")
	server_hand.pistol.advance(0.0)
	server_hand.inventory().spend_ammo("pistol")
	server_hand.pistol.record_shot()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return client_hand.pistol.loaded() == 6, 5.0
		)
	)
	client_hand.pistol.entity.request_action(&"reload")
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server_hand.pistol.active(), 5.0
		)
	)
	server_hand.pistol.advance(.65)
	var late := _client(port, "Late")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return _hand(late, peer) != null and _hand(late, peer).pistol.active(),
			5.0
		)
	)
	var late_hand := _hand(late, peer)
	late_hand.set_process(false)
	assert_eq(late_hand.pistol.loaded(), 6)
	assert_almost_eq(float(late_hand.pistol.state["left"]), 1.0, .01)
	late_hand.pistol.entity.request_action(&"reload")
	await RealTime.wait(get_tree(), .15)
	assert_almost_eq(float(server_hand.pistol.state["left"]), 1.0, .01)
	assert_eq(server_hand.pistol.loaded(), 6)
	server_hand.pistol.advance(1.1)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return not late_hand.pistol.active() and late_hand.pistol.loaded() == 7,
			5.0
		)
	)
	assert_eq(server_hand.inventory().ammo_for("pistol"), 19)
