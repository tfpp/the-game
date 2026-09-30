extends GutTest
## Real transport covers remote search, a late observer and sender isolation.

const CONTAINER := preload("res://features/loot/loot_container.tscn")
const MODEL := preload("res://features/slum_alley/dumpster_model.tscn")
const PLAYER := preload("res://core/player/player.tscn")
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


func _branch(title: String, peer: ENetMultiplayerPeer, owner: int) -> LootContainer:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var player := PLAYER.instantiate() as Player
	player.name = "Player"
	player.set_multiplayer_authority(owner)
	root.add_child(player)
	player.set_physics_process(false)
	player.net_position = Vector3.ZERO
	var container := CONTAINER.instantiate() as LootContainer
	container.name = "Loot"
	root.add_child(container)
	root.add_child(MODEL.instantiate())
	return container


func test_remote_search_replicates_to_late_joiner_and_only_owner_can_end_it() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var driver_peer := ENetMultiplayerPeer.new()
	assert_eq(driver_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var owner := driver_peer.get_unique_id()
	var server := _branch("Server", server_peer, owner)
	var driver := _branch("Driver", driver_peer, owner)
	await wait_physics_frames(10)
	driver.request_search()
	for frame: int in 120:
		await get_tree().physics_frame
		if driver.net_active_searchers == 1:
			break
	assert_eq(server.net_active_searchers, 1)
	assert_eq(driver.net_active_searchers, 1)
	var observer_peer := ENetMultiplayerPeer.new()
	assert_eq(observer_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var observer := _branch("Observer", observer_peer, owner)
	for frame: int in 120:
		await get_tree().physics_frame
		if observer.net_active_searchers == 1:
			break
	assert_eq(observer.net_active_searchers, 1, "Late join receives current search state")
	assert_true(observer.net_searched)
	driver.request_keep_searching()
	var entity := observer.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	entity.request_action(&"search_end", {"peer": owner})
	observer.request_stop_searching()
	await wait_physics_frames(10)
	assert_eq(server.net_active_searchers, 1, "Observer cannot close another player's search")
	var model := observer.get_node("../Model") as DumpsterVisual
	await wait_physics_frames(30)
	assert_almost_eq(model.get_node("Hinge").rotation_degrees.x, DumpsterVisual.OPEN_ANGLE, .01)
	driver.request_stop_searching()
	for frame: int in 120:
		await get_tree().physics_frame
		if observer.net_active_searchers == 0:
			break
	assert_eq(server.net_active_searchers, 0)
	assert_eq(observer.net_active_searchers, 0)
	assert_true(server.net_searched, "Closing preserves the loot roll")
	await wait_physics_frames(35)
	assert_almost_eq(model.get_node("Hinge").rotation_degrees.x, 0.0, .01)
	driver.request_search()
	for frame: int in 120:
		await get_tree().physics_frame
		if observer.net_active_searchers == 1:
			break
	assert_eq(server.net_active_searchers, 1)
	var driver_root := driver.get_parent()
	var driver_path := driver_root.get_path()
	_roots.erase(driver_root)
	driver_root.free()
	get_tree().set_multiplayer(null, driver_path)
	driver_peer.close()
	for frame: int in 120:
		await get_tree().physics_frame
		if observer.net_active_searchers == 0:
			break
	assert_eq(server.net_active_searchers, 0, "Disconnect releases the search immediately")
	assert_eq(observer.net_active_searchers, 0)
