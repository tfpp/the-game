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


func _setup(feature: Node3D) -> WorkshopLift:
	(feature.get_node("Room") as StreamedRoom).set_physics_process(false)
	(feature.get_node("TravelPanel") as VanTravelPanel).set_process(false)
	var lift := feature.get_node("Room/WorkshopLift") as WorkshopLift
	lift.set_physics_process(false)
	return lift


func _player(parent: Node, peer: int, at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.get_node("Sync").free()
	parent.add_child(player)
	player.set_physics_process(false)
	player.net_position = at
	return player


func _branch(title: String, peer: ENetMultiplayerPeer) -> WorkshopLift:
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
	return _setup(feature)


func test_shared_controls_validate_sender_range_and_replicate_height_to_late_join() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("LiftServer", server_peer)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("LiftClient", client_peer)
	client.set_physics_process(true)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5
		)
	)
	var id := client_peer.get_unique_id()
	var player := _player(
		server.get_parent().get_parent().get_parent(), id, server.to_global(Vector3(-6, 1, -.3))
	)
	assert_eq(server.entity._evaluate(id, &"use", {}), NetworkedEntity.Result.DENIED)
	player.net_position = server.to_global(Vector3(-2.8, 1, -.3))
	assert_eq(server.entity._evaluate(id, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	assert_eq(client.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	client.use()
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool: return server.net_target_height == WorkshopLift.MAX_HEIGHT,
			5
		)
	)
	server._physics_process(1)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool:
				return (
					absf(client.net_height - server.net_height) < .001
					and absf((client.van.get_node("Model") as Node3D).position.y - .65) < .001
				),
			5
		)
	)
	assert_almost_eq((client.van.get_node("Model") as Node3D).position.y, .65, .001)
	await REAL_TIME.wait(get_tree(), .26)
	client.use()
	assert_true(
		await REAL_TIME.wait_until(get_tree(), func() -> bool: return not server.moving(), 5)
	)
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("LiftLate", late_peer)
	late.set_physics_process(true)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool:
				return (
					absf(late.net_height - .65) < .001
					and not late.moving()
					and absf(late.arms.position.y - .65) < .001
				),
			5
		)
	)
	assert_almost_eq(late.arms.position.y, .65, .001)
	assert_almost_eq((late.van.get_node("Model") as Node3D).position.y, .65, .001)


func test_lowering_interlock_stops_for_a_player_and_travel_requires_grounded_van() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var lift := _setup(feature)
	var operator := _player(feature, 1, lift.to_global(Vector3(-2.8, 1, -.3)))
	assert_true(lift.can_use(operator))
	lift.van._pending[1] = {"zone": 0, "remaining": 2.0}
	assert_false(lift.can_use(operator), "An accepted trip locks the lift")
	lift.van._pending.clear()
	assert_true(lift._toggle(operator))
	assert_false(lift.van._available(1), "Travel locks as soon as lifting starts")
	lift._physics_process(3.0)
	assert_almost_eq(lift.net_height, WorkshopLift.MAX_HEIGHT, .001)
	var visitor := _player(feature, 2, lift.to_global(Vector3(0, .95, 0)))
	assert_false(lift._toggle(operator), "Lowering refuses an occupied bay")
	assert_true(lift.net_obstructed)
	visitor.net_position = lift.to_global(Vector3(5, .95, 0))
	assert_true(lift._toggle(operator))
	lift._physics_process(.5)
	var stopped_height := lift.net_height
	visitor.net_position = lift.to_global(Vector3(0, .95, 0))
	lift._physics_process(.5)
	assert_almost_eq(lift.net_height, stopped_height, .001, "Entering the bay stops descent")
	assert_false(lift.moving())
	assert_true(lift.net_obstructed)
	visitor.net_position = lift.to_global(Vector3(5, .95, 0))
	assert_true(lift._toggle(operator))
	lift._physics_process(3.0)
	assert_true(lift.grounded())
	assert_true(lift.van._available(1))


func test_raised_collision_leaves_walking_clearance_and_support_pads_touch_chassis() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var lift := _setup(feature)
	lift.net_height = WorkshopLift.MAX_HEIGHT
	lift.net_target_height = lift.net_height
	lift._physics_process(0)
	await wait_physics_frames(3)
	var shape := CapsuleShape3D.new()
	shape.radius = .4064
	shape.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var space := lift.get_world_3d().direct_space_state
	for z: float in [-1.6, 0, 1.6]:
		query.transform = Transform3D(Basis.IDENTITY, lift.to_global(Vector3(0, .95, z)))
		assert_true(space.intersect_shape(query).is_empty(), "Player fits under the raised van")
	for x: float in [-.64, .64]:
		for z: float in [-1.25, 1.25]:
			var ray := PhysicsRayQueryParameters3D.create(
				lift.to_global(Vector3(x, lift.net_height + .4, z)),
				lift.to_global(Vector3(x, lift.net_height + .3, z))
			)
			assert_false(space.intersect_ray(ray).is_empty(), "Support pads move with the van")
	assert_almost_eq(
		lift.arms.position.y + .36, (lift.van.get_node("Model") as Node3D).position.y + .36, .001
	)
	assert_lt(2.25 + lift.net_height, 4.28, "Raised roof clears lift bridge and garage ceiling")
	assert_eq(preload("res://assets/starter_room/workshop_lift.png").get_size(), Vector2(128, 128))
