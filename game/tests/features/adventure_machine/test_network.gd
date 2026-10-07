extends GutTest
## Real authenticated transport, concurrent private stories and late joining.

const FEATURE := preload("res://features/adventure_machine/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
const SOLUTION: Array[String] = [
	"go_tavern",
	"take_cracker",
	"learn",
	"go_quay",
	"feed",
	"go_shop",
	"buy_rope",
	"go_quay",
	"combine",
	"fish",
	"go_fort",
	"challenge",
	"retort_0",
	"retort_1",
	"retort_2",
	"unlock",
	"go_quay",
	"sail"
]
var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []
var _pages: Dictionary[int, Dictionary] = {}
var _replies: Dictionary[int, int] = {}


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()


func _branch(title: String, peer: ENetMultiplayerPeer) -> AdventureMachine:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var machine := FEATURE.instantiate() as AdventureMachine
	machine.name = "Cabinet"
	root.add_child(machine)
	if not machine.multiplayer.is_server():
		# These simulated peers share one physics world; only the server cabinet may block rays.
		machine.collision_layer = 0
	# Test packets without allowing global modal UI to affect the other simulated peers.
	machine.entity.event_received.disconnect(machine._event)
	machine.entity.event_received.connect(
		func(event: StringName, page: Dictionary) -> void:
			if event in [&"open", &"page"]:
				_pages[peer.get_unique_id()] = page
	)
	machine.entity.request_finished.connect(
		func(_action: StringName, _result: NetworkedEntity.Result) -> void:
			var id := peer.get_unique_id()
			_replies[id] = _replies.get(id, 0) + 1
	)
	return machine


func _player(server: AdventureMachine, peer: int, x: float) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.get_node("Sync").free()
	player.position = server.global_position + Vector3(x, 1, 1.6)
	player.net_position = player.position
	server.get_parent().add_child(player)
	player.set_physics_process(false)
	return player


func _connect(server: AdventureMachine, branch_name: String) -> AdventureMachine:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(
		peer.create_client(
			"127.0.0.1",
			(server.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.get_local_port()
		),
		OK
	)
	var machine := _branch(branch_name, peer)
	var id := peer.get_unique_id()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return id in server.multiplayer.get_peers(), 5
		)
	)
	return machine


func _request(client: AdventureMachine, action: StringName, payload: Dictionary = {}) -> void:
	var peer := client.multiplayer.get_unique_id()
	var count: int = _replies.get(peer, 0) + 1
	client.entity.request_action(action, payload)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return _replies.get(peer, 0) >= count, 5
		)
	)


func test_real_requests_keep_two_voyages_private_and_late_joiners_start_fresh() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("AdventureServer", server_peer)
	var first := await _connect(server, "AdventureFirst")
	var second := await _connect(server, "AdventureSecond")
	var id1 := first.multiplayer.get_unique_id()
	var id2 := second.multiplayer.get_unique_id()
	var player1 := _player(server, id1, -.45)
	_player(server, id2, .45)
	await wait_physics_frames(4)
	await _request(first, &"use", {"peer": id2})
	assert_true(server._stories.is_empty())
	await _request(first, &"choose", {"choice": "take_magnet", "revision": 0})
	assert_true(server._stories.is_empty(), "Opening is required")
	first.use()
	second.use()
	var opened := await RealTime.wait_until(
		get_tree(), func() -> bool: return _pages.has(id1) and _pages.has(id2), 5
	)
	assert_true(opened)
	if not opened:
		return
	assert_eq(server._stories.size(), 2)
	assert_true(first._stories.is_empty(), "Clients own no story authority")
	assert_eq(first.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_null(server._screen, "Remote use never allocates a server UI")
	first.request_choice("take_magnet", 0)
	second.request_choice("go_tavern", 0)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return int(_pages[id1]["revision"]) == 1 and int(_pages[id2]["revision"]) == 1,
			5
		)
	)
	assert_eq(_pages[id1]["inventory"], "Horseshoe magnet")
	assert_eq(_pages[id2]["inventory"], "Empty pockets")
	assert_eq(_pages[id2]["place"], "The Uninsured Mermaid")
	var late := await _connect(server, "AdventureLate")
	var id3 := late.multiplayer.get_unique_id()
	_player(server, id3, 1)
	await RealTime.wait(get_tree(), .14)
	assert_false(_pages.has(id3), "A late joiner receives no one else's story or historical events")
	assert_false(server._stories.has(id3))
	await _request(late, &"use")
	assert_eq(_pages[id3]["revision"], 0)
	assert_eq(_pages[id3]["inventory"], "Empty pockets")
	await _request(first, &"choose", {"choice": "go_tavern", "revision": 0})
	assert_eq(server._stories[id1].revision, 1, "Stale request is rejected")
	await _request(first, &"choose", {"choice": "go_tavern", "revision": 1, "peer": id2})
	assert_eq(server._stories[id1].revision, 1, "Identity injection is rejected")
	player1.net_position.z += 10
	await _request(first, &"choose", {"choice": "go_tavern", "revision": 1})
	assert_eq(server._stories[id1].revision, 1, "Range is rechecked for every choice")
	player1.net_position.z -= 10
	for choice: String in SOLUTION:
		await RealTime.wait(get_tree(), .13)
		await _request(
			first, &"choose", {"choice": choice, "revision": int(_pages[id1]["revision"])}
		)
	assert_true(server._stories[id1].won)
	assert_string_contains(_pages[id1]["message"], "THE END")
	assert_eq(_pages[id2]["revision"], 1, "Another player's ending never changes my voyage")
	assert_eq(_pages[id3]["revision"], 0)
	await _request(first, &"use")
	assert_eq(_pages[id1]["place"], "Curtain call", "Reopening resends current state")
	await RealTime.wait(get_tree(), .13)
	await _request(first, &"choose", {"choice": "restart", "revision": _pages[id1]["revision"]})
	await RealTime.wait(get_tree(), .13)
	await _request(
		first, &"choose", {"choice": "confirm_restart", "revision": _pages[id1]["revision"]}
	)
	assert_false(server._stories[id1].won)
	assert_eq(_pages[id1]["inventory"], "Empty pockets")
	second.multiplayer.multiplayer_peer.close()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not server._stories.has(id2), 5
		)
	)
	assert_true(server._stories.has(id1))
	assert_true(server._stories.has(id3))
	server._reset(Network.Mode.SERVER)
	assert_true(server._stories.is_empty())
