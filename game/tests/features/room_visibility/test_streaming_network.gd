extends GutTest

const RealTime := preload("res://tests/fixtures/real_time.gd")
var _roots: Array[Node3D] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for root: Node3D in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()


func _branch(title: String, transport: ENetMultiplayerPeer) -> RoomVisibility:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(transport)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = transport
	get_tree().set_multiplayer(api, root.get_path())
	var room := StreamedRoom.new()
	room.name = "Room"
	room.room_scene = "res://features/room_doors/rooms/lounge.tscn"
	root.add_child(room)
	var features := Node.new()
	features.name = "Features"
	root.add_child(features)
	var loader := RoomVisibility.new()
	loader.name = "Visibility"
	features.add_child(loader)
	return loader


func test_room_assignment_and_preload_reach_only_owner_across_distinct_peer_roots() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var member_transport := ENetMultiplayerPeer.new()
	assert_eq(member_transport.create_client("127.0.0.1", transport.host.get_local_port()), OK)
	var member := _branch("Member", member_transport)
	var outsider_transport := ENetMultiplayerPeer.new()
	assert_eq(outsider_transport.create_client("127.0.0.1", transport.host.get_local_port()), OK)
	var outsider := _branch("Outsider", outsider_transport)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	var member_room := member.get_node("../../Room") as StreamedRoom
	var outsider_room := outsider.get_node("../../Room") as StreamedRoom
	var selection := server._room_at(Vector3.ZERO)
	server.assign_room.rpc_id(
		member_transport.get_unique_id(), selection["path"], selection["bounds"]
	)
	assert_true(await RealTime.wait_until(get_tree(), member_room.is_loaded, 5.0))
	assert_false(outsider_room.is_loaded())
	server.assign_room.rpc_id(member_transport.get_unique_id(), NodePath(""), AABB())
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not member_room.is_loaded(), 5.0
		)
	)
	server.preload_at.rpc_id(member_transport.get_unique_id(), Vector3.ZERO)
	assert_true(await RealTime.wait_until(get_tree(), member_room.is_loaded, 5.0))
	assert_true(member_room.arrival_held())
	assert_false(outsider_room.is_loaded())
