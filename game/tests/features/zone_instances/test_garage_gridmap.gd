extends GutTest
## The saved level tiles preserve the authored shell, rather than substitute boxes.

const STATIC := preload("res://features/zone_instances/garage_gridmap/static.tscn")
const LAYOUT := preload("res://features/procedural_rooms/world_layout.gd")
const COLLISION := preload("res://features/zone_instances/garage_gridmap/collision.tscn")
const PLAYER := preload("res://core/player/player.tscn")


func test_actual_controller_traverses_every_saved_ramp_and_stair_both_ways() -> void:
	var old_device := Controls.device
	var old_playing := Controls.playing
	var old_move := Controls.xr_move
	Controls.device = Controls.Device.XR
	Controls.playing = true
	var root := Node3D.new()
	add_child_autofree(root)
	var world := LAYOUT.build(root, 73021, [], false, false)
	world.add_child(COLLISION.instantiate())
	var player := PLAYER.instantiate() as Player
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await wait_physics_frames(2)
	for index: int in 4:
		for kind: String in ["Ramp", "Stairs"]:
			var module := world.get_node("%s%d" % [kind, index]) as Node3D
			var length: float = module.get_meta("length")
			for reverse: bool in [false, true]:
				player.global_position = module.to_global(
					Vector3(0, 4.9644 if reverse else .9644, length + .7 if reverse else -.7)
				)
				player.velocity = Vector3.ZERO
				player.yaw = module.global_rotation.y + (0.0 if reverse else PI)
				Controls.xr_move = Vector2.ZERO
				for frame: int in 12:
					player._physics_process(1.0 / 64.0)
					await wait_physics_frames(1)
				Controls.xr_move = Vector2(0, -.5)
				for frame: int in ceili((length + 2) * 64 / 3) + 64:
					player._physics_process(1.0 / 64.0)
					await wait_physics_frames(1)
					var local := module.to_local(player.global_position)
					if local.z < -.6 if reverse else local.z > length + .6:
						break
				var final := module.to_local(player.global_position)
				assert_true(
					final.z < -.5 if reverse else final.z > length + .5,
					"%s%d traversal, reverse=%s" % [kind, index, reverse]
				)
				assert_almost_eq(
					final.y - player.movement.hull_height_m() * .5, 0.0 if reverse else 4.0, .06
				)
	Controls.device = old_device
	Controls.playing = old_playing
	Controls.xr_move = old_move


func test_saved_shortcuts_can_be_jumped_and_drop_only_one_floor() -> void:
	var old_device := Controls.device
	var old_playing := Controls.playing
	var old_move := Controls.xr_move
	var old_jump := Controls.jump_queued
	Controls.device = Controls.Device.XR
	Controls.playing = true
	var root := Node3D.new()
	add_child_autofree(root)
	var world := LAYOUT.build(root, 73021, [], false, false)
	world.add_child(COLLISION.instantiate())
	var player := PLAYER.instantiate() as Player
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await wait_physics_frames(2)
	var space := world.get_world_3d().direct_space_state
	for index: int in range(1, 5):
		var x := -13.0 if index % 2 == 0 else 13.0
		var floor_y := index * 4.0
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(
				Vector3(x, floor_y + .3, 21), Vector3(x, floor_y - 4.3, 21), 1
			)
		)
		assert_false(hit.is_empty(), "The shortcut has a landing")
		if not hit.is_empty():
			assert_almost_eq(
				hit["position"].y, floor_y - 4, .001, "No hidden ceiling or stacked hole"
			)
		player.global_position = Vector3(x, floor_y + .95, 18.5)
		player.velocity = Vector3.ZERO
		player.yaw = PI
		Controls.xr_move = Vector2.ZERO
		for frame: int in 12:
			player._physics_process(1.0 / 64.0)
			await wait_physics_frames(1)
		Controls.xr_move = Vector2(0, -1)
		var jumped := false
		for frame: int in 240:
			if not jumped and player.position.z >= 19 and player.is_on_floor():
				Controls.jump_queued = true
				jumped = true
			if player.position.z > 22.6:
				Controls.xr_move = Vector2.ZERO
			player._physics_process(1.0 / 64.0)
			await wait_physics_frames(1)
			if jumped and player.position.z > 22.6 and player.is_on_floor():
				break
		assert_true(jumped)
		assert_gt(player.position.z, 22.6, "Real movement crosses the two-metre gap")
		assert_almost_eq(player.position.y - player.movement.hull_height_m() * .5, floor_y, .06)
		Controls.xr_move = Vector2.ZERO
		player.global_position = Vector3(x, floor_y + .95, 21)
		player.velocity = Vector3.ZERO
		for frame: int in 120:
			player._physics_process(1.0 / 64.0)
			await wait_physics_frames(1)
			if player.is_on_floor() and player.position.y < floor_y - 2:
				break
		assert_true(player.is_on_floor(), "The drop lands on the next storey")
		assert_almost_eq(player.position.y - player.movement.hull_height_m() * .5, floor_y - 4, .06)
	Controls.device = old_device
	Controls.playing = old_playing
	Controls.xr_move = old_move
	Controls.jump_queued = old_jump


func test_saved_water_coverage_increases_with_depth_without_extra_collision() -> void:
	var saved := STATIC.instantiate() as Node3D
	add_child_autofree(saved)
	var grid := saved.get_node("Levels") as GridMap
	await wait_physics_frames(2)
	var previous_area := 0.0
	for depth: int in 5:
		var mesh := grid.mesh_library.get_item_mesh(4 - depth)
		var area := 0.0
		var wet_surfaces := 0
		for surface: int in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if material.resource_name != "Garage standing water":
				continue
			wet_surfaces += 1
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index: int in range(0, indices.size(), 3):
				var a := vertices[indices[index]]
				var b := vertices[indices[index + 1]]
				var c := vertices[indices[index + 2]]
				area += (b - a).cross(c - a).length() * .5
		assert_eq(wet_surfaces, 0 if depth == 0 else 1, "One batched water surface per wet deck")
		if depth > 0:
			assert_gt(area, previous_area, "Standing water grows on every lower floor")
		previous_area = area
		var y := (4 - depth) * 4.0
		var hit := saved.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(Vector3(7, y + .1, 8), Vector3(7, y - .2, 8), 1)
		)
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq(
				hit["position"].y, y, .001, "Water overlays do not change physical floor height"
			)


func test_server_collision_survives_unloading_visual_room() -> void:
	var saved := COLLISION.instantiate() as Node3D
	add_child_autofree(saved)
	var grid := saved.get_node("Levels") as GridMap
	for item: int in grid.mesh_library.get_item_list():
		assert_null(grid.mesh_library.get_item_mesh(item), "Server tiles have no render mesh")
	var room := StreamedRoom.new()
	room.room_scene = "res://features/zone_instances/garage_gridmap/static.tscn"
	add_child_autofree(room)
	room.load_room(10000)
	assert_true(room.is_loaded())
	room.unload_room()
	assert_false(room.is_loaded())
	await wait_physics_frames(2)
	var space := saved.get_world_3d().direct_space_state
	for floor_index: int in 5:
		var point := Vector3(-17, floor_index * 4.0, 5)
		var query := PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * .2, point - Vector3.UP * .2, 1
		)
		assert_false(space.intersect_ray(query).is_empty(), "Server deck remains after unload")


func test_saved_tiles_preserve_all_collision_triangles_and_render_surfaces() -> void:
	var source := Node3D.new()
	add_child_autofree(source)
	var world := LAYOUT.build(source, 73021, [], false)
	var authored := world.get_node("Structure/ShellCollision").get_child(0) as CollisionShape3D
	var original := (authored.shape as ConcavePolygonShape3D).get_faces()
	var saved := STATIC.instantiate() as Node3D
	add_child_autofree(saved)
	var grid := saved.get_node("Levels") as GridMap
	assert_eq(grid.get_used_cells().size(), 5)
	assert_eq(grid.mesh_library.get_item_list().size(), 5)
	var restored := PackedVector3Array()
	var triangles := 0
	for cell: Vector3i in grid.get_used_cells():
		var item := grid.get_cell_item(cell)
		var shapes := grid.mesh_library.get_item_shapes(item)
		var shape := shapes[0] as ConcavePolygonShape3D
		assert_true(shape.backface_collision)
		for vertex: Vector3 in shape.get_faces():
			restored.append(vertex + grid.map_to_local(cell))
		var mesh := grid.mesh_library.get_item_mesh(item)
		for surface: int in mesh.get_surface_count():
			triangles += (
				(mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			)
	assert_eq(
		_points(restored), _points(original), "No authored collision face is lost or duplicated"
	)
	var original_triangles := 0
	for node: Node in world.get_node("Structure").get_children():
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			original_triangles += (
				(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			)
	assert_eq(triangles, original_triangles)
	assert_true(saved.find_children("*", "MultiplayerSynchronizer", true, false).is_empty())
	assert_true(saved.find_children("*", "MultiplayerSpawner", true, false).is_empty())


func test_saved_decks_have_floor_support_and_an_open_central_shaft() -> void:
	var saved := STATIC.instantiate() as Node3D
	add_child_autofree(saved)
	await wait_physics_frames(2)
	var space := saved.get_world_3d().direct_space_state
	for floor_index: int in 5:
		var point := Vector3(-17, floor_index * 4.0, 5)
		var query := PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * .2, point - Vector3.UP * .2, 1
		)
		assert_false(space.intersect_ray(query).is_empty())
	var shaft := PhysicsRayQueryParameters3D.create(Vector3(0, 24, 21), Vector3(0, -.5, 21), 1)
	assert_true(
		space.intersect_ray(shaft).is_empty(), "Sky opening stays clear through all five levels"
	)


func _points(vertices: PackedVector3Array) -> Dictionary[Vector3, int]:
	var counts: Dictionary[Vector3, int] = {}
	for vertex: Vector3 in vertices:
		var key := vertex.snapped(Vector3.ONE * .00001)
		counts[key] = counts.get(key, 0) + 1
	return counts
