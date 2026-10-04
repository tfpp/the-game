extends GutTest

const DOLL := preload("res://features/pawn_shop/creepy_doll_passer.tscn")
const REAL_TIME := preload("res://tests/fixtures/real_time.gd")

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
	# Audio commands are consumed on a real-time mixer thread, independently
	# of the accelerated test frames.
	await REAL_TIME.wait(get_tree(), .15)


func _branch(title: String, peer: ENetMultiplayerPeer) -> CreepyDollPasser:
	var branch := Node3D.new()
	branch.name = title
	add_child(branch)
	_roots.append(branch)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, branch.get_path())
	var doll := DOLL.instantiate() as CreepyDollPasser
	branch.add_child(doll)
	doll.set_process(false)
	return doll


func test_clock_boundaries_and_pass_end() -> void:
	assert_eq(CreepyDollPasser.next_boundary(599.9), 600.0)
	assert_eq(CreepyDollPasser.next_boundary(600.0), 1200.0)
	var doll := DOLL.instantiate() as CreepyDollPasser
	add_child_autofree(doll)
	doll.set_process(false)
	doll._next_boundary = 600.0
	doll.server_update(599.9)
	assert_eq(doll.net_phase, -1.0)
	doll.server_update(600.0)
	assert_eq(doll.net_phase, 0.0)
	doll.server_update(612.0)
	doll._present(0.0)
	assert_true(doll.visual.visible)
	assert_almost_eq(doll.visual.position.x, -14.8, 0.001)
	doll.server_update(600.0 + CreepyDollPasser.DURATION)
	doll._present(0.0)
	assert_false(doll.visual.visible)
	assert_true(doll.ambience.playing, "The track continues into the ending fade")
	assert_almost_eq(doll.ambience.volume_db, -14.0, .01)
	doll.server_update(601.5 + CreepyDollPasser.DURATION)
	doll._present(0.0)
	assert_almost_eq(doll.ambience.volume_db, -20.0206, .01)
	doll.server_update(640.0)
	doll._present(0.0)
	assert_false(doll.visual.visible)
	assert_false(doll.ambience.playing)
	var audio := doll.ambience.stream as AudioStreamWAV
	assert_eq(audio.format, AudioStreamWAV.FORMAT_QOA)
	assert_eq(audio.mix_rate, 11025)
	assert_false(audio.stereo)
	assert_lt(audio.data.size(), 250000)
	doll.server_update(1830.0)
	assert_eq(doll.net_phase, 30.0, "Missed boundaries do not queue repeated passes")


func test_server_phase_reaches_every_peer_and_late_joiner() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("DollServer", transport)
	server._next_boundary = 600.0
	server.server_update(612.0)
	var port := transport.host.get_local_port()
	for title: String in ["DollClient", "DollLateJoin"]:
		var peer := ENetMultiplayerPeer.new()
		assert_eq(peer.create_client("127.0.0.1", port), OK)
		var client := _branch(title, peer)
		assert_true(
			await REAL_TIME.wait_until(
				get_tree(), func() -> bool: return client.net_phase == 12.0, 5.0
			)
		)
		client._present(0.0)
		assert_true(client.visual.visible)
		assert_almost_eq(client.visual.position.x, -14.8, 0.001)
		client.server_update(1200.0)
		assert_eq(client.net_phase, 12.0, "Clients cannot start a new pass")
	server.server_update(640.0)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return (_roots[1].get_child(0) as CreepyDollPasser).net_phase == -1.0,
			5.0
		)
	)
