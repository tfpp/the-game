extends GutTest

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
	_roots.clear()
	_peers.clear()


func _branch(title: String, peer: ENetMultiplayerPeer) -> GarageRollerDoor:
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
	(feature.get_node("Room") as StreamedRoom).set_physics_process(false)
	var door := feature.get_node("Room/RollerDoor") as GarageRollerDoor
	door.set_physics_process(false)
	return door


func test_shutter_clears_real_opening_and_reverses_when_blocked() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var room := feature.get_node("Room") as StreamedRoom
	room.load_room(3000)
	var door := room.get_node("RollerDoor") as GarageRollerDoor
	door.set_physics_process(false)
	await wait_physics_frames(3)
	assert_false(door.obstructed(), "Empty service doorway can close")
	var from := door.to_global(Vector3(0, 1.5, 2))
	var to := door.to_global(Vector3(0, 1.5, -2))
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	var space := room.get_world_3d().direct_space_state
	assert_false(space.intersect_ray(ray).is_empty(), "Closed leaf seals opening")
	door.net_height = GarageRollerDoor.HEIGHT
	door.net_target = GarageRollerDoor.HEIGHT
	door._pose()
	await wait_physics_frames(3)
	var boundary := door.get_node("Boundary") as StaticBody3D
	assert_eq((space.intersect_ray(ray)["collider"] as Node).name, &"Boundary")
	ray.exclude = [boundary.get_rid()]
	assert_true(space.intersect_ray(ray).is_empty(), "Leaf clears while fixed boundary remains")
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.motion = Vector3(0, 0, -4)
	for y: float in [.95, 1.8, 2.0]:
		query.transform.origin = door.to_global(Vector3(0, y, 1.5))
		assert_lt(space.cast_motion(query)[0], 1.0, "Walking and jumping cannot leave")
	var player := PLAYER.instantiate() as Player
	player.get_node("Sync").free()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = door.to_global(Vector3(0, .95, 0))
	player.net_position = player.global_position
	await wait_physics_frames(3)
	assert_true(door.obstructed())
	door.net_target = 0.0
	door._physics_process(.1)
	assert_eq(door.net_target, GarageRollerDoor.HEIGHT, "Blocked close reverses to open")
	player.net_position = door.to_global(Vector3(-2.65, 1.25, .2))
	assert_true(door.can_use(player))
	player.net_position += Vector3.RIGHT * 8
	assert_false(door.can_use(player))


func test_road_is_visible_scenery_outside_membership_and_safe_zone() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var room := feature.get_node("Room") as StreamedRoom
	room.load_room(3000)
	await wait_physics_frames(3)
	var at := room.to_global(Vector3(3, 1, -17))
	var ray := PhysicsRayQueryParameters3D.create(at, at - Vector3.UP * 2)
	var hit := room.get_world_3d().direct_space_state.intersect_ray(ray)
	assert_false(hit.is_empty())
	assert_false(room.bounds.has_point(Vector3(3, 1, -17)))
	assert_true(room.render_bounds.has_point(Vector3(3, 1, -17)))
	var Zones := preload("res://features/safe_zone/feature.tscn")
	var zones := Zones.instantiate()
	add_child_autofree(zones)
	assert_false(SafeZone.covers(get_tree(), at))


func test_remote_control_and_late_join_replicate_shutter_height() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("DoorServer", server_peer)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("DoorClient", client_peer)
	client.set_physics_process(true)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5
		)
	)
	var player := PLAYER.instantiate() as Player
	player.name = "Operator"
	player.set_multiplayer_authority(client_peer.get_unique_id())
	player.get_node("Sync").free()
	server.get_parent().get_parent().add_child(player)
	player.set_physics_process(false)
	player.net_position = server.to_global(Vector3(-2.65, 1.25, .2))
	client.use()
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.net_target == GarageRollerDoor.HEIGHT, 5
		)
	)
	server._physics_process(1.0)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool:
				return (
					absf(client.net_height - .8) < .001 and absf(client.leaf.position.y - .8) < .001
				),
			5
		)
	)
	assert_almost_eq(client.leaf.position.y, .8, .001)
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("DoorLate", late_peer)
	late.set_physics_process(true)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return absf(late.leaf.position.y - .8) < .001, 5
		)
	)
	assert_ne(server.entity._evaluate(999, &"use", {}), NetworkedEntity.Result.ACCEPTED)
