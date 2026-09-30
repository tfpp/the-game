extends GutTest

const LAYOUT := preload("res://features/casino_wing/layout.gd")
const CATALOGUE := preload("res://features/casino_wing/catalogue.gd")
const POPULATION := preload("res://features/procedural_rooms/room_population.gd")


func test_all_rooms_connect_through_matching_clear_socket_boundaries() -> void:
	var root := Node3D.new()
	add_child(root)
	var wing := LAYOUT.build(root)
	var door := wing.get_node("VaultDoor") as ProceduralSlidingDoor
	door.net_open = true
	await wait_physics_frames(35)
	assert_eq(door.interaction_text(), "Close vault door")
	var joins: Dictionary[String, Array] = {}
	for socket: ProceduralSocketAttachment in wing.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if socket.join_id.is_empty() or socket.join_id == "casino-north-wing":
			continue
		if not joins.has(socket.join_id):
			joins[socket.join_id] = []
		joins[socket.join_id].append(socket)
	var visited: Array[Node] = [wing.get_node("Promenade")]
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var space := wing.get_world_3d().direct_space_state
	for pair: Array in joins.values():
		assert_eq(pair.size(), 2)
		var socket := pair[0] as ProceduralSocketAttachment
		assert_eq(socket.errors_with(pair[1]), [])
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = socket.to_global(Vector3(0, .95, -.45))
		query.motion = socket.global_basis.z * .9
		assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, socket.join_id)
		for offset: float in [-.45, .45]:
			var point := socket.to_global(Vector3(0, .2, offset))
			assert_false(
				(
					space
					. intersect_ray(PhysicsRayQueryParameters3D.create(point, point + Vector3.DOWN))
					. is_empty()
				),
				"Floor support at " + socket.join_id
			)
	for _pass: int in joins.size():
		for pair: Array in joins.values():
			if pair[0].get_parent() in visited and pair[1].get_parent() not in visited:
				visited.append(pair[1].get_parent())
			if pair[1].get_parent() in visited and pair[0].get_parent() not in visited:
				visited.append(pair[0].get_parent())
	for module: Node3D in wing.get_children():
		if module.has_meta("shell_faces"):
			assert_true(module in visited, str(module.name))
	assert_almost_eq((wing.get_node("Vault") as Node3D).position.y, -4.0, .001)
	root.free()


func test_room_volumes_do_not_overlap_and_sets_preserve_reserved_routes() -> void:
	var root := Node3D.new()
	add_child(root)
	var wing := LAYOUT.build(root)
	var volumes: Array[AABB] = []
	for room: Node3D in wing.get_children():
		if not room.has_meta("dimensions"):
			continue
		var dimensions: Vector3 = room.get_meta("dimensions")
		var bounds := room.transform * AABB(Vector3(-dimensions.x * .5, 0, 0), dimensions)
		bounds = bounds.grow(-.001)
		for other: AABB in volumes:
			assert_false(bounds.intersects(other), str(room.name) + " overlaps another room")
		volumes.append(bounds)
		if not room.has_meta("population_rule"):
			continue
		var rule: ProceduralPopulationRule = room.get_meta("population_rule")
		var placements: Array = room.get_node("Population").get_meta("placements")
		assert_gt(placements.size(), 0, str(room.name) + " is furnished")
		for value: Dictionary in placements:
			assert_true(rule.placement_bounds.encloses(value["bounds"]))
			for forbidden: AABB in rule.forbidden_volumes:
				assert_false(value["bounds"].intersects(forbidden))
		for mesh: MeshInstance3D in room.get_node("Population").find_children(
			"*", "MeshInstance3D", true, false
		):
			var model_bounds := (
				(room.global_transform.affine_inverse() * mesh.global_transform)
				* mesh.mesh.get_aabb()
			)
			var enclosed := false
			for value: Dictionary in placements:
				enclosed = enclosed or (value["bounds"] as AABB).grow(.005).encloses(model_bounds)
			assert_true(enclosed, str(mesh.get_path()) + " fits the declared set footprint")
	root.free()


func test_catalogue_uses_roles_sizes_rotations_and_deterministic_seeds() -> void:
	var rule := ProceduralPopulationRule.new()
	rule.set_definitions = CATALOGUE.definitions()
	rule.allowed_sets = ["slot_bank", "cards", "lounge", "vault_safes"]
	rule.room_tag = "gaming"
	rule.forbidden_volumes = []
	rule.weights = PackedFloat32Array()
	rule.density = 1
	rule.placement_bounds = AABB(Vector3(-10, 0, 0), Vector3(20, 4, 20))
	rule.slots = [Vector3(-5, 0, 5), Vector3(5, 0, 5), Vector3(-5, 0, 15), Vector3(5, 0, 15)]
	rule.allowed_yaws = PackedFloat32Array([0, PI / 2, PI])
	var first := POPULATION.plan(rule, 1964)
	assert_eq(first.size(), 4)
	assert_eq(first, POPULATION.plan(rule, 1964))
	assert_ne(first, POPULATION.plan(rule, 2026))
	for value: Dictionary in first:
		assert_ne(value["kind"], "vault_safes")
	rule.room_tag = "vault"
	rule.allowed_sets = ["vault_safes"]
	rule.allowed_yaws = PackedFloat32Array([PI / 2])
	assert_eq(POPULATION.plan(rule, 1964).size(), 4)
	for value: Dictionary in POPULATION.plan(rule, 1964):
		assert_almost_eq(value["bounds"].size.x, 1.5, .001)
		assert_almost_eq(value["bounds"].size.z, 4, .001)
	rule.forbidden_volumes = [rule.placement_bounds]
	assert_eq(POPULATION.plan(rule, 1964), [])


func test_player_walks_between_casino_and_wing_and_descends_vault_stairs() -> void:
	var root := Node3D.new()
	add_child(root)
	root.add_child(load("res://world/room.tscn").instantiate())
	var feature := load("res://features/casino_wing/feature.tscn").instantiate() as Node3D
	root.add_child(feature)
	await wait_physics_frames(3)
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = Vector3(0, .95, -32)
	query.motion = Vector3(0, 0, -5)
	assert_almost_eq(root.get_world_3d().direct_space_state.cast_motion(query)[0], 1.0, .001)
	Controls.device = Controls.Device.XR
	Controls.playing = true
	var player := load("res://core/player/player.tscn").instantiate() as Player
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var stairs := feature.get_node("Wing/VaultStairs") as Node3D
	for reverse: bool in [false, true]:
		player.global_position = stairs.to_global(
			Vector3(0, 4.9644 if reverse else .9644, 10.7 if reverse else -.7)
		)
		player.velocity = Vector3.ZERO
		player.yaw = stairs.global_rotation.y + (0.0 if reverse else PI)
		Controls.xr_move = Vector2.ZERO
		for frame: int in 12:
			player._physics_process(1.0 / 64.0)
			await wait_physics_frames(1)
		Controls.xr_move = Vector2(0, -.5)
		for frame: int in 350:
			player._physics_process(1.0 / 64.0)
			await wait_physics_frames(1)
			var point := stairs.to_local(player.global_position)
			if point.z < -.6 if reverse else point.z > 10.6:
				break
		var final := stairs.to_local(player.global_position)
		assert_true(final.z < -.5 if reverse else final.z > 10.5, "Physical stairs traversal")
		assert_almost_eq(
			final.y - player.movement.hull_height_m() * .5, 0.0 if reverse else 4.0, .06
		)
	Controls.xr_move = Vector2.ZERO
	Controls.playing = false
	Controls.device = Controls.Device.KEYBOARD
	root.free()
