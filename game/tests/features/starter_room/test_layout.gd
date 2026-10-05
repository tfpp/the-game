extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")


func test_entire_spawn_square_and_routes_have_floor_and_capsule_clearance() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var room := feature.get_node("Room") as StreamedRoom
	room.load_room(3000)
	await wait_physics_frames(3)
	var space := room.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	for x: int in range(-3, 4):
		for z: int in range(1, 8):
			var origin := room.to_global(Vector3(x, .95, z))
			var ray := PhysicsRayQueryParameters3D.create(origin, origin - Vector3.UP * 2)
			var hit := space.intersect_ray(ray)
			assert_false(hit.is_empty(), str(origin))
			if not hit.is_empty():
				assert_almost_eq((hit["position"] as Vector3).y, 0.0, .001)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform.origin = origin
			assert_true(space.intersect_shape(query).is_empty(), str(origin))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = room.to_global(Vector3(0, .95, 4))
	query.motion = Vector3(1.4, 0, -6)
	assert_eq(space.cast_motion(query)[0], 1.0, "spawn to van driver side")
	query.motion = Vector3(-4.5, 0, 2)
	assert_eq(space.cast_motion(query)[0], 1.0, "spawn to walking exit")
	for grid: GridMap in room.get_node("Content/Structure").get_children():
		assert_gt(grid.get_used_cells().size(), 0)
	assert_eq((room.get_node("Content/Structure/Walls") as GridMap).get_used_cells().size(), 60)
	assert_eq((room.get_node("Content/Structure/SideWalls") as GridMap).get_used_cells().size(), 72)


func test_actual_initial_player_preloads_floor_before_server_assignment() -> void:
	var visibility := Node.new()
	visibility.add_to_group(&"room_visibility")
	add_child_autofree(visibility)
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var room := feature.get_node("Room") as StreamedRoom
	var player := PLAYER.instantiate() as Player
	player.position = (room.get_node("Spawn") as Marker3D).global_position
	player.net_position = player.position
	add_child_autofree(player)
	await wait_physics_frames(40)
	assert_true(room.is_loaded())
	assert_true(player.is_on_floor())
	assert_gt(player.net_position.y, .5)
	# Content lifetime after departure remains owned by RoomVisibility.
	player.global_position = Vector3(0, 1, 16)
	player.net_position = player.global_position
	room.unload_room()
	await wait_physics_frames(3)
	assert_false(room.is_loaded())


func test_van_export_has_finite_indexed_geometry_small_texture_and_grounded_wheels() -> void:
	var VanMesh := preload("res://assets/starter_room/van.res")
	var arrays := VanMesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(indices.size() / 3, 176)
	for i: int in vertices.size():
		assert_true(vertices[i].is_finite())
		assert_almost_eq(normals[i].length(), 1.0, .001)
		assert_true(uv[i].x >= 0 and uv[i].x <= 1 and uv[i].y >= 0 and uv[i].y <= 1)
	for i: int in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		assert_gt(cross.length(), .00001)
		assert_lt(cross.normalized().dot(normals[a]), -.99)
	assert_almost_eq(VanMesh.get_aabb().position.y, 0.0, .001)
	assert_eq(preload("res://assets/starter_room/van.png").get_size(), Vector2(128, 128))
	var Audio := preload("res://assets/starter_room/van_departure.wav")
	assert_almost_eq(Audio.get_length(), 2.0, .001)
	assert_eq(Audio.loop_mode, AudioStreamWAV.LOOP_DISABLED)


func test_workshop_equipment_keeps_service_aisles_clear_and_uses_small_shared_atlas() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var room := feature.get_node("Room") as StreamedRoom
	room.load_room(3000)
	await wait_physics_frames(3)
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	var space := room.get_world_3d().direct_space_state
	for point: Vector3 in [
		Vector3(-5, .95, -7.1),
		Vector3(-3, .95, -6.8),
		Vector3(6, .95, -6.6),
		Vector3(5.8, .95, -.6)
	]:
		query.transform.origin = room.to_global(point)
		assert_true(
			space.intersect_shape(query).is_empty(),
			"Workbench and right-wall tools have standing clearance"
		)
	query.transform.origin = room.to_global(Vector3(0, .95, -3.3))
	query.motion = Vector3(-5, 0, -3.8)
	assert_eq(space.cast_motion(query)[0], 1.0, "Lift controls to workbench route stays clear")
	var equipment := room.get_node("Content/WorkshopEquipment") as Node3D
	var triangles := 0
	for model: MeshInstance3D in equipment.find_children("*", "MeshInstance3D"):
		var mesh := model.mesh as ArrayMesh
		assert_not_null(mesh)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3
		for index: int in vertices.size():
			assert_true(vertices[index].is_finite())
			assert_almost_eq(normals[index].length(), 1.0, .001)
			assert_true(
				uv[index].x >= 0 and uv[index].x <= 1 and uv[index].y >= 0 and uv[index].y <= 1
			)
		for index: int in range(0, indices.size(), 3):
			var a := indices[index]
			var cross := (vertices[indices[index + 1]] - vertices[a]).cross(
				vertices[indices[index + 2]] - vertices[a]
			)
			assert_gt(cross.length(), .000001)
			assert_lt(cross.normalized().dot(normals[a]), -.99)
	assert_eq(triangles, 2528)
	assert_eq(preload("res://assets/starter_room/workshop_lift.png").get_size(), Vector2(128, 128))
