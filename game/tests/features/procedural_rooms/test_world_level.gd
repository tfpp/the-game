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
	assert_eq(joins.size(), 52)
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
		# Shaft openings have an interlocked gate and a floor only when the cab is docked.
		if (
			socket.get_parent().name == "LiftShaft"
			or (socket.name == "Out" and str(socket.get_parent().name).begins_with("LiftLobby"))
		):
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


func test_lift_is_one_physical_platform_with_closed_empty_landings() -> void:
	await wait_physics_frames(30)
	var lift := _world.get_node("Lift") as ProceduralMovingLift
	assert_eq(lift.cab.position.y, 16.0)
	assert_true(lift.cab is AnimatableBody3D)
	for index: int in 5:
		assert_eq(lift.gates[index]._amount, 1.0 if index == 4 else 0.0)
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(.5, index * 4 + 1, -7), Vector3(.5, index * 4 + 1, -9)
		)
		var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
		assert_eq(hit.is_empty(), index == 4, "Only the docked landing can be entered")


func test_real_player_rides_down_and_up_without_teleport_or_reparenting() -> void:
	var lift := _world.get_node("Lift") as ProceduralMovingLift
	Controls.device = Controls.Device.XR
	Controls.playing = true
	Controls.xr_move = Vector2.ZERO
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.position = Vector3(0, 16.95, -9.5)
	_world.add_child(player)
	await wait_physics_frames(30)
	var original_parent := player.get_parent()
	var panel := lift.cab.get_node("Floor3/NetworkedEntity") as NetworkedInteraction
	assert_eq(panel._evaluate(2, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(panel._evaluate(1, &"use", {"floor": 3}), NetworkedEntity.Result.DENIED)
	assert_eq(panel._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(lift.net_height, 16.0, "Request starts door closing, not an instant floor change")
	var previous := player.global_position
	for target: int in [3, 0, 4]:
		if target != 3:
			assert_true(lift.request_floor(target))
		for frame: int in 850:
			await wait_physics_frames(1)
			assert_lt(absf(player.global_position.y - previous.y), .15, "Continuous rider movement")
			previous = player.global_position
			if lift.net_phase == ProceduralMovingLift.Phase.DOCKED:
				break
		assert_eq(lift.net_floor, target)
		assert_eq(player.get_parent(), original_parent)
		assert_almost_eq(
			player.global_position.y, target * 4 + player.movement.hull_height_m() / 2, .08
		)
		assert_true(player.is_on_floor())
	Controls.device = Controls.Device.KEYBOARD
	Controls.playing = false
	player.free()


func test_lift_refuses_departure_when_doorway_is_occupied() -> void:
	var lift := _world.get_node("Lift") as ProceduralMovingLift
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.position = Vector3(0, 16.95, -8)
	_world.add_child(player)
	player.set_physics_process(false)
	assert_true(lift.doorway_occupied())
	assert_false(lift.request_floor(0))
	player.position.z = -9.5
	player.net_position = player.global_position
	assert_true(lift.request_floor(0))
	player.position.z = -8
	player.net_position = player.global_position
	lift._advance(.2)
	assert_eq(lift.net_phase, ProceduralMovingLift.Phase.OPENING)
	assert_eq(lift.net_height, 16.0)
	player.free()
