extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const TILES := preload("res://features/starter_room/upstairs_tiles.tres")
const FLOOR := preload("res://features/procedural_rooms/materials/garage_floor.tres")
const STEEL := preload("res://features/procedural_rooms/materials/garage_rail.tres")


func test_garage_tiles_keep_collision_and_replace_every_casino_finish() -> void:
	var Casino := preload("res://features/casino_hub/gridmap/casino_tiles.tres")
	for id: int in [9, 10, 15, 16]:
		var mesh := TILES.get_item_mesh(id)
		assert_true(TILES.get_item_name(id).begins_with("Garage"))
		var shapes := TILES.get_item_shapes(id)
		var original := Casino.get_item_shapes(id)
		assert_eq(shapes.size(), original.size())
		assert_eq(shapes[1], original[1])
		if shapes[0] is BoxShape3D:
			assert_eq((shapes[0] as BoxShape3D).size, (original[0] as BoxShape3D).size)
		else:
			assert_eq(
				(shapes[0] as ConvexPolygonShape3D).points,
				(original[0] as ConvexPolygonShape3D).points
			)
		assert_eq(TILES.get_item_mesh_transform(id), Casino.get_item_mesh_transform(id))
		assert_eq(mesh.get_surface_count(), 1)
		assert_eq(mesh.surface_get_material(0), FLOOR if id == 15 else STEEL)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_gt(indices.size(), 0)
		for index: int in vertices.size():
			assert_true(vertices[index].is_finite())
			assert_true(uv[index].is_finite())
			assert_almost_eq(normals[index].length(), 1.0, .001)
		for index: int in range(0, indices.size(), 3):
			var a := indices[index]
			var b := indices[index + 1]
			var c := indices[index + 2]
			var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
			assert_gt(cross.length(), .000001)
			assert_lt(cross.normalized().dot(normals[a]), -.99)
	assert_almost_eq(TILES.get_item_mesh(9).get_aabb().end.y, 1.105, .001)
	assert_almost_eq(TILES.get_item_mesh(16).get_aabb().end.y, 2.355, .001)


func test_posters_face_room_stay_on_wall_and_survive_streaming_reload() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var room := feature.get_node("Room") as StreamedRoom
	room.load_room(60000)
	await wait_physics_frames(3)
	for id: String in ["WorldMap", "CasinoBlueprints"]:
		var board := room.get_node("Content/" + id) as Node3D
		assert_almost_eq(board.position.x, 7.9, .001)
		assert_almost_eq(board.position.y, 2.4, .001)
		assert_almost_eq((board.basis * Vector3.BACK).dot(Vector3.LEFT), 1.0, .001)
		var paper := board.get_node("Paper") as MeshInstance3D
		var material := paper.material_override as StandardMaterial3D
		assert_eq(material.albedo_texture.get_size(), Vector2(128, 128))
		assert_true(material.albedo_texture.get_image().has_mipmaps())
		assert_lt(board.position.z + 1.44, 9.0)
		assert_gt(board.position.y - 1.09, 0.0)
		assert_lt(board.position.y + 1.09, 4.75)
		for part: String in ["Diagram", "Markup"]:
			var arrays := (board.get_node(part) as MeshInstance3D).mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index: int in range(0, indices.size(), 3):
				var a := vertices[indices[index]]
				var b := vertices[indices[index + 1]]
				var c := vertices[indices[index + 2]]
				assert_lt((b - a).cross(c - a).z, 0.0, "diagram faces the room")
		assert_null(board.find_child("*Collision*", true, false), "art never blocks routes")
		var texts: Array[String] = []
		for key: StringName in board.get_meta_list():
			texts.append(str(board.get_meta(key)))
		if id == "WorldMap":
			assert_has(texts, "YOU ARE HERE")
			assert_has(texts, "OPERATIONS\nGARAGE")
			assert_has(texts, "THE GOLDEN CROWN")
			assert_has(texts, "STREET\nDISTRICT")
			assert_has(texts, "BASEMENT\nGARAGE B1-B5")
		else:
			assert_has(texts, "GOLDEN CROWN / BLUEPRINTS")
			assert_has(texts, "GAMING\nPIT")
		var shape := CapsuleShape3D.new()
		shape.radius = .4064
		shape.height = 1.8288
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = room.to_global(Vector3(6.8, .95, board.position.z))
		assert_true(room.get_world_3d().direct_space_state.intersect_shape(query).is_empty())
	room.unload_room()
	assert_false(room.is_loaded())
	room.load_room(60000)
	await wait_physics_frames(2)
	assert_eq(room.get_node("Content/WorldMap").get_child_count(), 6)
	assert_eq(room.get_node("Content/CasinoBlueprints").get_child_count(), 6)
	for id: String in ["Stairs", "StairRails", "Rails", "Posts"]:
		var grid := room.get_node("Content/Upstairs/" + id) as GridMap
		assert_eq(grid.mesh_library, TILES)
