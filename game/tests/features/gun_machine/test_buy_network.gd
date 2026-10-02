extends GutTest
## Real transport for private menu events, sender validation and existing rig replication.

const FEATURE := preload("res://features/gun_machine/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const CHAT := preload("res://features/chat_box/chat_box.gd")
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
	Controls.pause()


func _branch(title: String, peer: ENetMultiplayerPeer) -> GunMachine:
	var root := Node.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var feature := FEATURE.instantiate() as GunMachine
	feature.name = "Guns"
	root.add_child(feature)
	var chat := CHAT.new()
	chat.name = "Chat"
	root.add_child(chat)
	chat.get_node("DiscordRelay")._configured = true
	return feature


func _client(port: int, title: String) -> GunMachine:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	return _branch(title, peer)


func _player(server: GunMachine, peer: int) -> void:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	server.get_parent().add_child(player)
	player.set_physics_process(false)


func test_private_command_purchase_sender_and_late_join_snapshot() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("Server", server_peer)
	var wallet := PlayerMoney.new()
	server.get_parent().add_child(wallet)
	wallet.set_process(false)
	var port := server_peer.host.get_local_port()
	var client := _client(port, "Client")
	var other := _client(port, "Other")
	var peer := client.multiplayer.get_unique_id()
	var other_peer := other.multiplayer.get_unique_id()
	_player(server, peer)
	_player(server, other_peer)
	wallet.balances = {peer: 6000, other_peer: 4000}
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					client.get_node("Rigs").get_child_count() == 2
					and other.get_node("Rigs").get_child_count() == 2
				),
			5.0
		)
	)
	var menu := client.get_node("BuyMenu") as CanvasLayer
	var other_menu := other.get_node("BuyMenu") as CanvasLayer
	var server_menu := server.get_node("BuyMenu") as CanvasLayer
	var chat := client.get_parent().get_node("Chat")
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return chat._log.get_child_count() == 2, 5.0
		)
	)
	chat.request_chat_command.rpc_id(1, "guns")
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return menu._panel.visible, 5.0)
	)
	assert_false(other_menu._panel.visible)
	assert_false(server_menu._panel.visible)
	assert_eq(chat._log.get_child_count(), 2, "private commands add no lines beyond join notices")
	menu.entity.request_action(&"buy", {"id": "ray", "peer": other_peer})
	await RealTime.wait(get_tree(), 0.1)
	assert_eq(wallet.balances[peer], 6000)
	menu._select("generated:5:2:0")
	other_menu._select("ray")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					not menu._pending
					and not other_menu._pending
					and wallet.balances[peer] == 4000
					and wallet.balances[other_peer] == 2000
				),
			5.0
		)
	)
	var rig := client.get_node("Rigs/%d" % peer) as GunRig
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not rig.net_stats.is_empty(), 5.0
		)
	)
	assert_eq(rig.net_stats["ammo_type"], GunGenerator.AmmoType.PLASMA)
	assert_eq(rig.net_stats["barrel_count"], 2)
	var late := _client(port, "Late")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				var late_rig := late.get_node_or_null("Rigs/%d" % peer) as GunRig
				return late_rig != null and not late_rig.net_stats.is_empty(),
			5.0
		)
	)
	var late_rig := late.get_node("Rigs/%d" % peer) as GunRig
	assert_eq(late_rig.net_stats, rig.net_stats)
	assert_eq(late_rig.net_ammo_in_mag, rig.net_ammo_in_mag)
	assert_false(late.get_node("BuyMenu")._panel.visible, "menus are never replayed")
	# The production Network switch tears down this client immediately on disconnect.
	client.get_parent().process_mode = Node.PROCESS_MODE_DISABLED
	client.multiplayer.multiplayer_peer.close()
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					server.get_node_or_null("Rigs/%d" % peer) == null
					and late.get_node_or_null("Rigs/%d" % peer) == null
				),
			5.0
		)
	)
