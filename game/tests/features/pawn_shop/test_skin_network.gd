extends GutTest
## Real ENet requests, private collection events and public late-join equipment.

const SKINS := preload("res://features/pawn_shop/skin_crates.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const REAL_TIME := preload("res://tests/fixtures/real_time.gd")

var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []
var _playing := false


func before_each() -> void:
	_playing = Controls.playing


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()
	Controls.playing = _playing


func _branch(title: String, peer: ENetMultiplayerPeer) -> PrawnSkins:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var skins := SKINS.instantiate() as PrawnSkins
	skins.name = "Skins"
	root.add_child(skins)
	skins.set_process(false)
	return skins


func _client(port: int, title: String) -> PrawnSkins:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	return _branch(title, peer)


func _player(server: PrawnSkins, peer: int, at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	server.get_parent().add_child(player)
	player.set_physics_process(false)
	player.net_position = at
	server._players[peer] = player.get_instance_id()
	server._peers[peer] = server._key(peer)
	server._load(peer, server._key(peer))
	return player


func test_private_inventory_validated_requests_late_equipment_and_disconnect() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	server.odds = [10000, 0, 0, 0, 0]
	var wallet := PlayerMoney.new()
	server.get_parent().add_child(wallet)
	wallet.set_process(false)
	var port := server_peer.host.get_local_port()
	var client := _client(port, "Client")
	var other := _client(port, "Other")
	var peer := client.multiplayer.get_unique_id()
	wallet.balances = {peer: 2000}
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	var player := _player(server, peer, Vector3(0, .95, 1.2))
	watch_signals(client.entity)
	watch_signals(other.entity)
	watch_signals(server.entity)
	client.entity.request_action(&"collection")
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return get_signal_emit_count(client.entity, "event_received") >= 1,
			5.0
		)
	)
	assert_signal_not_emitted(other.entity, "event_received")
	assert_signal_not_emitted(server.entity, "event_received")
	# Extra peer/price/reward fields never reach collection/wallet mutations.
	(
		client
		. entity
		. request_action(
			&"operate",
			{
				"action": "buy",
				"id": "harbour",
				"revision": 0,
				"peer": peer,
				"price": 0,
			}
		)
	)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return get_signal_emit_count(client.entity, "request_finished") >= 2,
			5.0
		)
	)
	assert_eq(wallet.balances[peer], 2000)
	assert_eq(client.entity._evaluate(peer, &"operate", {}), NetworkedEntity.Result.DENIED)
	_send(client, "buy", "harbour", 0)
	# A repeated request carries the same observed revision, so only one commits.
	_send(client, "buy", "harbour", 0)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return server._collections[server._key(peer)]["revision"] == 1,
			5.0
		)
	)
	assert_eq(wallet.balances[peer], 1500)
	_send(client, "open", "harbour", 1)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return server._collections[server._key(peer)]["revision"] == 2,
			5.0
		)
	)
	_send(client, "equip", "brine", 2)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return other.net_equipped.get(peer, {}).get("pistol", "") == "brine",
			5.0
		)
	)
	assert_signal_not_emitted(other.entity, "event_received", "no collection or reveal leak")
	player.net_position = Vector3(0, 1, 50)
	_send(client, "buy", "night", 3)
	await REAL_TIME.wait(get_tree(), .1)
	assert_eq(wallet.balances[peer], 1500, "Range rechecked at purchase, not just menu open")
	var late := _client(port, "Late")
	watch_signals(late.entity)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return late.net_equipped.get(peer, {}).get("pistol", "") == "brine",
			5.0
		)
	)
	assert_signal_not_emitted(late.entity, "event_received", "late join is silent")
	assert_true(late._collections.is_empty(), "private inventory never synchronized")
	player.free()
	server._process(1)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return not late.net_equipped.has(peer), 5.0
		)
	)
	assert_false(server._collections.has("temporary:%d" % peer))


func _send(client: PrawnSkins, action: String, id: String, revision: int) -> void:
	client.entity.request_action(&"operate", {"action": action, "id": id, "revision": revision})
