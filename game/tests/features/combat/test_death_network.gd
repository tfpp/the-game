extends GutTest
## Real RPC transport for the server-owned death/respawn lifecycle.

const CombatScene := preload("res://features/combat/feature.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer) -> Combat:
	var root := Node.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var combat := CombatScene.instantiate() as Combat
	combat.name = "Combat"
	# This probe targets reliable lifecycle RPCs, not the unchanged health sync.
	combat.get_node("Sync").free()
	root.add_child(combat)
	return combat


func test_only_victim_sees_screen_and_only_server_completes_respawn() -> void:
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
	watch_signals(server)
	watch_signals(client)
	var victim := client_peer.get_unique_id()
	client.apply_damage(victim, Combat.MAX_HEALTH, 1)
	assert_signal_not_emitted(client, "player_died")
	server.apply_damage(victim, Combat.MAX_HEALTH, 1)
	# Pause server countdown to examine the UI regardless of CPU/fixed-fps speed.
	server.set_process(false)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return (client.get_node("Hud/DeathScreen") as Control).visible,
			5.0
		)
	)
	assert_false((server.get_node("Hud/DeathScreen") as Control).visible)
	assert_signal_emit_count(client, "player_died", 1)
	assert_signal_not_emitted(client, "player_respawned")
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("Late", late_peer)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	assert_false((late.get_node("Hud/DeathScreen") as Control).visible)
	server._process(Combat.RESPAWN_DELAY_S)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return not (client.get_node("Hud/DeathScreen") as Control).visible,
			5.0
		)
	)
	assert_signal_emit_count(client, "player_respawned", 1)
	assert_false((late.get_node("Hud/DeathScreen") as Control).visible)
