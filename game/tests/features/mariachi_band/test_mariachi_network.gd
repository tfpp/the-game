extends GutTest
## Real ENet transport: late joiners hear the current song, requests go through the
## server, and clients can't change the song themselves.

const FEATURE := preload("res://features/mariachi_band/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")

var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for branch: Node in _roots:
		var path := branch.get_path()
		branch.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()


func _branch(title: String, peer: ENetMultiplayerPeer) -> MariachiBand:
	var branch := Node3D.new()
	branch.name = title
	add_child(branch)
	_roots.append(branch)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, branch.get_path())
	var band := FEATURE.instantiate() as MariachiBand
	band.name = "Band"
	branch.add_child(band)
	band.set_process(false)
	return band


func test_late_joiner_gets_the_song_and_requests_go_through_the_server() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	server.advance()
	server.net_stocky_member = 4
	server.net_banter = 1
	var take := server.net_take
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("Client", client_peer)
	var joined := func() -> bool: return client.net_take == take and client.net_song == 1
	assert_true(await RealTime.wait_until(get_tree(), joined, 5.0), "late join gets the song")
	await wait_process_frames(1)
	assert_eq((client.get_node("NowPlaying") as Label3D).text, "Now playing: Jarabe Tapatío")
	assert_eq(client.get_node("Audio").get("stream"), MariachiBand.STREAMS[1])
	assert_eq(client.net_stocky_member, 4, "late join gets the same selected musician")
	assert_eq(client.net_banter, 1, "late join sees the current backstage whisper")
	var body := client.get_node("Musicians/VihuelaPlayer/Body") as Node3D
	assert_eq(body.scale, MariachiBand.STOCKY_SCALE)
	assert_true((client.get_node("Musicians/GuitarronPlayer/Whisper") as Label3D).visible)
	client._reset_session(Network.Mode.OFFLINE)
	client._process(16.0)
	assert_eq(client.net_stocky_member, 4, "clients cannot reroll the shared selection")
	assert_eq(client.net_banter, 1, "clients cannot advance the shared gossip clock")
	server.net_banter = 2
	var whispered := func() -> bool: return client.net_banter == 2
	assert_true(await RealTime.wait_until(get_tree(), whispered, 5.0))
	client.net_stocky_member = 0
	client.net_banter = 0
	await RealTime.wait(get_tree(), 0.1)
	assert_eq(server.net_stocky_member, 4, "client state does not replicate to the server")
	assert_eq(server.net_banter, 2)
	server.net_stocky_member = 2
	server.net_banter = 0
	var restored := func() -> bool: return client.net_stocky_member == 2 and client.net_banter == 0
	assert_true(await RealTime.wait_until(get_tree(), restored, 5.0))

	client.advance()
	client.net_song = 0
	await RealTime.wait(get_tree(), 0.2)
	assert_eq(server.net_song, 1, "a client can't pick the song itself")

	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(client_peer.get_unique_id())
	add_child_autofree(player)
	player.net_position = server.to_global(Vector3(0, 0.9, -3.8))
	client.use()
	var moved := func() -> bool: return server.net_song == 0 and client.net_take == take + 1
	assert_true(await RealTime.wait_until(get_tree(), moved, 5.0), "request reaches the server")
	assert_eq(client.net_song, 0, "the new song replicates back")
