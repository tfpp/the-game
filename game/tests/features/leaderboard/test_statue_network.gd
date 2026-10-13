extends GutTest
## Real server/client authority and late-join presentation over ENet.

const BOARD := preload("res://features/leaderboard/feature.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer) -> Leaderboard:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var board := BOARD.instantiate() as Leaderboard
	board.name = "Leaderboard"
	root.add_child(board)
	board.set_process(false)
	(board.get_node("OnlineStatue") as OnlineStatue).set_process(false)
	return board


func test_late_join_receives_portrait_and_cannot_select_or_advance_the_honor() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	var server_statue := server.get_node("OnlineStatue") as OnlineStatue
	var portrait := OnlineStatue.portrait_for(get_tree(), 0)
	portrait["body"] = "penguin"
	portrait["tail"] = "fluffy"
	server_statue.champion = {"name": "Champion", "seconds": 7200, "portrait": portrait}
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("Client", client_peer)
	var client_statue := client.get_node("OnlineStatue") as OnlineStatue
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return client_statue.champion == server_statue.champion, 5.0
		)
	)
	var model := client_statue.get_node("Portrait") as BlockPlayerModel
	assert_eq(model.body_type, &"penguin")
	assert_eq(model.tail_type, &"fluffy")
	assert_string_contains((client_statue.get_node("Plaque") as Label3D).text, "Champion")
	client_statue._process(120.0)
	assert_true(client.longest_online().is_empty(), "Clients cannot compute shared scores")
	var entity := client_statue.get_node("NetworkedEntity") as NetworkedEntity
	watch_signals(entity)
	entity.request_action(&"set_champion", {"name": "Cheater", "seconds": 999999})
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return get_signal_emit_count(entity, "request_finished") > 0,
			5.0
		)
	)
	assert_eq(server_statue.champion["name"], "Champion")
	assert_eq(client_statue.champion["name"], "Champion")
	server_statue.champion = {"name": "New champion", "seconds": 7201, "portrait": portrait}
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return client_statue.champion.get("seconds") == 7201, 5.0
		)
	)
	assert_string_contains((client_statue.get_node("Plaque") as Label3D).text, "New champion")
