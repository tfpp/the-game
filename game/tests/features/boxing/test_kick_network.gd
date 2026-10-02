extends GutTest
## Real transport: requests derive identity from the sender; cosmetics are events.

const BOXING := preload("res://features/boxing/feature.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer) -> Boxing:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var boxing := BOXING.instantiate() as Boxing
	boxing.name = "Boxing"
	root.add_child(boxing)
	boxing.set_process(false)
	boxing._kicks.set_process(false)
	boxing._fists.set_process(false)
	return boxing


func test_validated_sender_charge_replication_and_late_observer_rest() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("Client", client_peer)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5.0
		)
	)
	var id := client_peer.get_unique_id()
	client.request_wind_up.rpc_id(1, true)
	await RealTime.wait(get_tree(), 0.05)
	assert_false(server._wind_up_ms.has(id), "No server player means no accepted request")
	var player := PLAYER.instantiate() as Player
	player.name = str(id)
	player.set_multiplayer_authority(id)
	# Disable the movement synchronizer: this probe only targets melee RPC transport.
	player.get_node("Sync").free()
	server.get_parent().add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	client.request_wind_up.rpc_id(1, true)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server._wind_up_ms.has(id), 5.0
		)
	)
	assert_false(server._wind_up_ms.has(1), "Client cannot charge on behalf of the host")
	server._wind_up_ms[id] -= 1000
	assert_null(client.punch(id, 1.0, true), "Client cannot apply a strike locally")
	client.request_punch.rpc_id(1, true)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not client.leg_pose(id).is_empty(), 5.0
		)
	)
	assert_true(server._kicks._power[id], "Server timed the power kick")
	assert_eq(client.leg_pose(id), server.leg_pose(id))
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("Late", late_peer)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	assert_true(late.leg_pose(id).is_empty(), "Do not replay historical kicks to late joiners")
	client_peer.close()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not server._ready_at_ms.has(id), 5.0
		)
	)
	assert_true(server.leg_pose(id).is_empty())
