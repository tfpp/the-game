extends GutTest
## Real server/client coverage: replicated drink stock, validated pickup over the
## transport, blackout phases for the drinker, an observer and a late joiner, and
## disconnect cleanup.

const HOLDABLES := preload("res://features/holdables/feature.tscn")
const BAR := preload("res://features/bar_companion/feature.tscn")
const BOOZE := preload("res://features/booze/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
const SPOT := "Booze/Spots/Spot0"
var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


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
	var holdables := HOLDABLES.instantiate()
	holdables.name = "Holdables"
	root.add_child(holdables)
	var bar := BAR.instantiate()
	bar.name = "BarCompanion"
	root.add_child(bar)
	var booze := BOOZE.instantiate()
	booze.name = "Booze"
	root.add_child(booze)
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


func _booze(root: Node) -> Booze:
	return root.get_node("Booze") as Booze


func test_stock_pickup_blackout_late_join_and_disconnect() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var port := transport.host.get_local_port()
	var client := _client(port, "Client")
	var peer := client.multiplayer.get_unique_id()
	var hand_path := "Holdables/Hands/%d" % peer
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return client.has_node(hand_path), 5)
	)
	var spot := server.get_node(SPOT) as DrinkSpot
	spot.net_item = "martini"
	var client_spot := client.get_node(SPOT) as DrinkSpot
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return client_spot.net_item == "martini", 5
		),
		"stock replicates"
	)
	# Out of range: the server refuses the client's Use.
	_player(server, peer, spot.global_position + Vector3(6, 0.6, 0))
	client_spot.use()
	await RealTime.wait(get_tree(), 0.3)
	assert_eq(spot.net_item, "martini")
	var server_player := server.get_node(str(peer)) as Player
	server_player.net_position = spot.global_position + Vector3(1.2, 0.6, 0)
	await RealTime.wait(get_tree(), 0.5)
	client_spot.use()
	var server_hand := server.get_node(hand_path) as Hand
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server_hand.net_item_id == "martini", 5
		),
		"in-range Use collects the drink"
	)
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return client_spot.net_item == "", 5)
	)
	# Eight drinks black the client out; phases replicate to the drinker.
	var bar := server.get_node("BarCompanion") as BarCompanion
	for _i: int in 8:
		bar.add_drink(peer)
	var server_booze := _booze(server)
	server_booze.advance(0.0)
	assert_eq(server_booze.phase_for(peer), BoozeRules.Phase.COLLAPSE)
	assert_true(server_hand.inventory().backpack.has("martini"), "drink stowed on collapse")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return _booze(client).phase_for(peer) == BoozeRules.Phase.COLLAPSE,
			5
		)
	)
	server_booze.advance(BoozeRules.COLLAPSE_S)
	assert_eq(server_booze.phase_for(peer), BoozeRules.Phase.OUT)
	# A late joiner receives the current blackout snapshot.
	var late := _client(port, "Late")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return _booze(late).phase_for(peer) == BoozeRules.Phase.OUT,
			5
		),
		"late join sees the blacked-out player"
	)
	assert_eq((late.get_node(SPOT) as DrinkSpot).net_item, "", "and the empty spot")
	# Clients cannot change phases themselves.
	_booze(client).blackouts = {}
	await RealTime.wait(get_tree(), 0.2)
	assert_eq(server_booze.phase_for(peer), BoozeRules.Phase.OUT)
	# Disconnecting the drinker clears their blackout for everyone else.
	var client_index := _roots.find(client)
	var path := client.get_path()
	client.free()
	get_tree().set_multiplayer(null, path)
	_peers[client_index].close()
	_roots[client_index] = null
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return _booze(late).blackouts.is_empty(), 5
		),
		"disconnect clears the blackout"
	)
	assert_true(server_booze.blackouts.is_empty())
