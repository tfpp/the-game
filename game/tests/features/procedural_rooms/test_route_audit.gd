extends GutTest

const Layout := preload("res://features/procedural_rooms/world_layout.gd")


func test_all_rooms_connect_to_their_socket_from_inside() -> void:
	var root := Node3D.new()
	add_child(root)
	var world := Layout.build(root)
	await wait_physics_frames(30)
	var space := world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	for module: Node3D in world.get_children():
		if (
			not module.has_meta("shell_faces")
			or (
				not module.name.to_lower().contains("west")
				and not module.name.to_lower().contains("east")
			)
		):
			continue
		for socket: ProceduralSocketAttachment in module.find_children(
			"*", "ProceduralSocketAttachment", true, false
		):
			if socket.join_id.is_empty():
				continue
			var start := module.to_global(Vector3(0, .95, 4))
			var end := socket.to_global(Vector3(0, .95, -.6))
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform.origin = start
			query.motion = end - start
			assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, str(socket.get_path()))
	root.free()


func test_top_and_bottom_perimeter_walls_are_closed_outside_joined_openings() -> void:
	var root := Node3D.new()
	add_child(root)
	var world := Layout.build(root)
	await wait_physics_frames(30)
	var space := world.get_world_3d().direct_space_state
	for index: int in [0, 4]:
		for side: float in [-1, 1]:
			for z: float in [1, 7, 9, 20, 33, 35, 41]:
				var start := Vector3(side * 20, index * 4 + 1.5, z)
				var end := Vector3(side * 22, index * 4 + 1.5, z)
				assert_false(
					space.intersect_ray(PhysicsRayQueryParameters3D.create(start, end)).is_empty(),
					"Deck%d perimeter x%s z%s" % [index, side, z]
				)
		for side: String in ["West", "East"]:
			for end: int in 2:
				var room := world.get_node("%s%d_%d" % [side, index, end]) as Node3D
				for socket: ProceduralSocketAttachment in room.find_children(
					"*", "ProceduralSocketAttachment", true, false
				):
					if not socket.join_id.is_empty():
						continue
					var from := socket.to_global(Vector3(0, 1.5, -.5))
					var to := socket.to_global(Vector3(0, 1.5, .5))
					assert_false(
						(
							space
							. intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
							. is_empty()
						),
						str(socket.get_path()) + " sealed end"
					)
	root.free()


func test_storey_wall_bands_have_no_half_metre_gaps() -> void:
	var root := Node3D.new()
	add_child(root)
	var world := Layout.build(root)
	await wait_physics_frames(3)
	var material := (
		(world.get_node("Structure/Wall") as MeshInstance3D).material_override as StandardMaterial3D
	)
	assert_eq(material.cull_mode, BaseMaterial3D.CULL_DISABLED)
	var space := world.get_world_3d().direct_space_state
	for index: int in 5:
		for side: float in [-1, 1]:
			for z: float in [1, 7, 9, 20, 33, 35, 41]:
				var from := Vector3(side * 20, index * 4 + 3.75, z)
				var to := Vector3(side * 22, index * 4 + 3.75, z)
				assert_false(
					space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)).is_empty(),
					"Storey wall band must meet the next floor"
				)
	root.free()


func test_every_room_is_reachable_from_top_deck_without_using_the_lift() -> void:
	var root := Node3D.new()
	add_child(root)
	var world := Layout.build(root)
	var joins: Dictionary[String, Array] = {}
	var modules: Array[Node] = []
	for module: Node in world.get_children():
		if module.has_meta("shell_faces") and module.name != "LiftShaft":
			modules.append(module)
	for socket: ProceduralSocketAttachment in world.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if socket.join_id.is_empty():
			continue
		if not joins.has(socket.join_id):
			joins[socket.join_id] = []
		joins[socket.join_id].append(socket.get_parent())
	var visited: Array[Node] = [world.get_node("Deck4")]
	var pending := visited.duplicate()
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for pair: Array in joins.values():
			if pair.size() != 2 or world.get_node("LiftShaft") in pair or current not in pair:
				continue
			for next: Node in pair:
				if next not in visited:
					visited.append(next)
					pending.append(next)
	for module: Node in modules:
		assert_true(
			module in visited, str(module.name) + " must have a physical route from arrival"
		)
	root.free()
