extends GutTest
## Real ENet requests and snapshots through the existing shared component.

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


func _branch(title: String, peer: ENetMultiplayerPeer) -> GarageJobTerminal:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var feature := FEATURE.instantiate() as Node3D
	feature.name = "StarterRoom"
	root.add_child(feature)
	feature.set_physics_process(false)
	(feature.get_node("Room/Van") as OperationsVan).set_physics_process(false)
	(feature.get_node("TravelPanel") as VanTravelPanel).set_process(false)
	var terminal := feature.get_node("Room/JobTerminal") as GarageJobTerminal
	terminal.set_physics_process(false)
	terminal.panel.set_process(false)
	return terminal


func _player(terminal: GarageJobTerminal, peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.get_node("Sync").free()
	player.net_position = terminal.to_global(Vector3(0, 0, .8))
	player.position = player.net_position
	terminal.get_parent().get_parent().add_child(player)
	player.set_physics_process(false)
	return player


func test_jobs_authenticate_sender_replicate_late_and_keep_each_peers_progress_separate() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("JobServer", server_peer)
	var port := server_peer.host.get_local_port()
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", port), OK)
	var client := _branch("JobClient", client_peer)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5
		)
	)
	var peer := client_peer.get_unique_id()
	var player := _player(server, peer)
	watch_signals(client.entity)
	client.entity.request_action(&"accept", {"job": 0, "peer": 1})
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return get_signal_emit_count(client.entity, "request_finished") == 1,
			5
		)
	)
	assert_true(server.records.is_empty())
	client.entity.request_action(&"accept", {"job": 0})
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return int(client.record(peer)["job"]) == 0, 5
		)
	)
	assert_eq(server.record(peer)["job"], 0)
	assert_eq(server.record(1)["job"], -1)
	player.net_position = server.van.arrival(0).global_position
	for i: int in 12:
		server._physics_process(.25)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return bool(client.record(peer)["ready"]), 5
		)
	)
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", port), OK)
	var late := _branch("JobLate", late_peer)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return bool(late.record(peer)["ready"]), 5
		)
	)
	assert_false(late.panel.is_open(), "snapshots never open another player's application")
	var other_peer := late_peer.get_unique_id()
	assert_eq(late.record(other_peer)["job"], -1)
	_player(server, other_peer)
	late.entity.request_action(&"accept", {"job": 0})
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return int(late.record(other_peer)["job"]) == 0, 5
		)
	)
	assert_false(bool(server.record(other_peer)["ready"]))
	assert_true(bool(server.record(peer)["ready"]))
	client_peer.close()
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return not late.records.has(peer), 5)
	)
	assert_eq(server.record(other_peer)["job"], 0)
