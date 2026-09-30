extends GutTest
## Real transport: server-owned gaze state and late observers.

const BOOT := preload("res://features/parking_garage/car_boot.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()


func _branch(title: String, peer: ENetMultiplayerPeer, owner: int) -> CarBoot:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var hinge := Node3D.new()
	hinge.name = "BootLid"
	root.add_child(hinge)
	var player := PLAYER.instantiate() as Player
	player.name = "Player"
	player.position = Vector3(-3.4, .95, 0)
	player.net_position = player.position
	player.set_multiplayer_authority(owner)
	root.add_child(player)
	player.set_physics_process(false)
	player.net_yaw = -PI / 2
	player.yaw = player.net_yaw
	player.net_pitch = -.4
	player.pitch = player.net_pitch
	var boot := BOOT.instantiate() as CarBoot
	boot.position = Vector3(-1.65, .9, 0)
	root.add_child(boot)
	return boot


func test_gaze_state_replicates_without_search_and_late_join_then_closes() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var driver_peer := ENetMultiplayerPeer.new()
	assert_eq(driver_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var owner := driver_peer.get_unique_id()
	var server := _branch("Server", server_peer, owner)
	var driver := _branch("Driver", driver_peer, owner)
	await wait_physics_frames(30)
	assert_true(server.net_boot_open)
	assert_true(driver.net_boot_open)
	assert_false(server.net_searched)
	var observer_peer := ENetMultiplayerPeer.new()
	assert_eq(observer_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var observer := _branch("Observer", observer_peer, owner)
	await wait_physics_frames(40)
	assert_true(observer.net_boot_open, "Late observer receives the open state")
	assert_almost_eq(observer.get_node("../BootLid").rotation_degrees.z, -68.0, .01)
	var entity := observer.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	entity.request_action(&"open", {"open": true})
	await wait_physics_frames(5)
	assert_false(server.net_searched, "Gaze cannot roll loot or accept spoofed open actions")
	var player := driver.get_node("../Player") as Player
	player.yaw += PI
	player.net_yaw = player.yaw
	await wait_physics_frames(50)
	assert_false(server.net_boot_open)
	assert_false(observer.net_boot_open)
	assert_almost_eq(observer.get_node("../BootLid").rotation_degrees.z, 0.0, .01)
