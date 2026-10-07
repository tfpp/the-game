extends GutTest
## Real transport: shared tenure stays authoritative, including late snapshots.

const DOOR := preload("res://features/hotel_annex/guest_door.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer) -> HotelGuestDoor:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var door := DOOR.instantiate() as HotelGuestDoor
	door.name = "Room101"
	root.add_child(door)
	door.set_physics_process(false)
	return door


func _player(door: HotelGuestDoor, peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.display_name = "Network resident"
	player.set_multiplayer_authority(peer)
	player.get_node("Sync").free()
	player.position = Vector3(0, 1, -1.5)
	player.net_position = player.position
	door.get_parent().add_child(player)
	player.set_physics_process(false)
	return player


func _reply(door: HotelGuestDoor, count: int) -> bool:
	return await REAL_TIME.wait_until(
		get_tree(),
		func() -> bool: return get_signal_emit_count(door._entity, "request_finished") >= count,
		5
	)


func test_real_requests_payment_competition_guests_and_late_snapshot() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("HotelServer", server_peer)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("HotelClient", client_peer)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5
		)
	)
	var peer := client_peer.get_unique_id()
	var player := _player(server, peer)
	var wallet := PlayerMoney.new()
	server.get_parent().add_child(wallet)
	wallet.set_process(false)
	wallet.balances = {peer: 20000}
	watch_signals(client._entity)
	client._entity.request_action(&"manage", {"operation": "rent", "peer": 1})
	assert_true(await _reply(client, 1))
	assert_eq(server.occupant, "")
	player.net_position.z = -10
	client.request_manage("rent")
	assert_true(await _reply(client, 2))
	assert_eq(server.occupant, "")
	player.net_position.z = -1.5
	client.request_manage("rent")
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return client.occupant == "Network resident", 5
		)
	)
	assert_eq(wallet.balances[peer], 19000)
	assert_true(client.locked)
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("HotelLate", late_peer)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return late.occupant == client.occupant, 5
		)
	)
	assert_true(late.locked)
	assert_eq(late.tenure, "Rental")
	assert_eq(late._owner, "", "Account/owner identity is not sent to clients")
	assert_null(late._panel, "Snapshot never opens another player's UI")
	var other := late_peer.get_unique_id()
	_player(server, other)
	wallet.balances[other] = 20000
	watch_signals(late._entity)
	await REAL_TIME.wait(get_tree(), .5)
	late.request_manage("buy")
	assert_true(await _reply(late, 1))
	late.request_manage("lock")
	assert_true(await _reply(late, 2))
	assert_true(server.locked)
	assert_eq(wallet.balances[other], 20000, "Competing tenant never pays for an occupied room")
	client.request_manage("guest", other)
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return other in late.guests, 5)
	)
	await REAL_TIME.wait(get_tree(), .5)
	late.request_manage("toggle")
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return client.net_state == SwingDoor.State.OPEN_IN, 5
		)
	)
	late_peer.close()
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return server.guests.is_empty(), 5)
	)
	client_peer.close()
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return server.occupant.is_empty(), 5)
	)
