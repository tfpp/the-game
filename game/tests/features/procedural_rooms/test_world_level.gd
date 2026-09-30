extends GutTest

const Layout := preload("res://features/procedural_rooms/world_layout.gd")
const PLAYER := preload("res://core/player/player.tscn")
var _root: Node3D
var _world: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child(_root)
	_world = Layout.build(_root)


func after_each() -> void:
	_root.free()


func test_every_join_matches_and_has_caps_removed() -> void:
	var joins: Dictionary[String, Array] = {}
	for socket: ProceduralSocketAttachment in _world.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if socket.join_id.is_empty():
			continue
		if not joins.has(socket.join_id):
			joins[socket.join_id] = []
		joins[socket.join_id].append(socket)
		assert_null(socket.cap)
	assert_eq(joins.size(), 47)
	for pair: Array in joins.values():
		assert_eq(pair.size(), 2)
		assert_eq(pair[0].errors_with(pair[1]), [])
	assert_eq(get_tree().get_nodes_in_group(&"world_lift_stops").size(), 5)


func test_all_socket_crossings_have_capsule_clearance_and_floor_support() -> void:
	await wait_physics_frames(30)
	var space := _world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	for socket: ProceduralSocketAttachment in _world.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if socket.join_id.is_empty():
			continue
		for x: float in [-0.7, 0, 0.7]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(
				Basis.IDENTITY, socket.to_global(Vector3(x, 0.9544, -0.45))
			)
			query.motion = socket.global_basis.z * 0.9
			assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, str(socket.get_path()))
			for offset: float in [-0.2, 0.2]:
				var point := socket.to_global(Vector3(x, 1.0, offset))
				var hit := space.intersect_ray(
					PhysicsRayQueryParameters3D.create(point, point - Vector3.UP * 2.0)
				)
				assert_false(hit.is_empty(), str(socket.get_path()) + " floor support")
				if not hit.is_empty():
					assert_almost_eq(hit["position"].y, socket.global_position.y, 0.001)


func test_player_walks_from_elevator_into_garage_without_falling() -> void:
	Controls.device = Controls.Device.XR
	Controls.playing = true
	Controls.xr_move = Vector2.ZERO
	var player := PLAYER.instantiate() as Player
	_world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector3(0, 17, -4)
	player.yaw = PI
	await wait_physics_frames(30)
	Controls.xr_move = Vector2(0, -0.5)
	for frame: int in 200:
		player._physics_process(1.0 / 64.0)
		await wait_physics_frames(1)
		if player.global_position.z > 6:
			break
	assert_gt(player.global_position.z, 6.0)
	assert_gt(player.global_position.y, 16.8)
	assert_true(player.is_on_floor())
	Controls.xr_move = Vector2.ZERO
	Controls.device = Controls.Device.KEYBOARD
	Controls.playing = false
	player.free()


func test_lift_validates_range_and_transports_through_every_floor() -> void:
	var player := PLAYER.instantiate() as Player
	_world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var stops := get_tree().get_nodes_in_group(&"world_lift_stops")
	var top := stops[4] as Node3D
	player.global_position = Vector3(100, 1, 100)
	player.net_position = player.global_position
	var entity := top.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	for index: int in [4, 0, 1, 2, 3]:
		var stop := stops[index] as Node3D
		player.global_position = stop.global_position + Vector3.UP
		player.net_position = player.global_position
		var interaction := stop.get_node("NetworkedEntity") as NetworkedInteraction
		assert_eq(interaction._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
		var target := stops[int(stop.call("destination_index"))] as Node3D
		assert_almost_eq(player.global_position.y, target.global_position.y + 1, 0.001)
	player.free()
