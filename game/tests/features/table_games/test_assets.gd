extends GutTest
const SUITES := preload("res://features/table_games/feature.tscn")
const MODELS: Array[ArrayMesh] = [
	preload("res://assets/table_games/models/blackjack_table.res"),
	preload("res://assets/table_games/models/poker_table.res"),
	preload("res://assets/table_games/models/baccarat_table.res"),
	preload("res://assets/table_games/models/craps_table.res"),
	preload("res://assets/table_games/models/video_poker_machine.res")
]


func test_assemblies_have_finite_indexed_geometry_and_small_painted_textures() -> void:
	for mesh: ArrayMesh in MODELS:
		assert_gte(mesh.get_surface_count(), 1)
		assert_lte(mesh.get_surface_count(), 2)
		assert_almost_eq(mesh.get_aabb().position.y, 0.0, .001)
		for surface: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			assert_gt(indices.size(), 0)
			assert_eq(indices.size() % 3, 0)
			assert_eq(positions.size(), normals.size())
			assert_eq(positions.size(), uvs.size())
			var geometry_ok := true
			for i: int in positions.size():
				geometry_ok = (
					geometry_ok
					and positions[i].is_finite()
					and normals[i].is_finite()
					and uvs[i].is_finite()
				)
				geometry_ok = (
					geometry_ok
					and uvs[i].x >= 0
					and uvs[i].x <= 1
					and uvs[i].y >= 0
					and uvs[i].y <= 1
				)
			for i: int in range(0, indices.size(), 3):
				for corner: int in 3:
					geometry_ok = (
						geometry_ok
						and indices[i + corner] >= 0
						and indices[i + corner] < positions.size()
					)
				var area := (positions[indices[i + 1]] - positions[indices[i]]).cross(
					positions[indices[i + 2]] - positions[indices[i]]
				)
				geometry_ok = geometry_ok and area.length_squared() > 0.000000000001
			assert_true(geometry_ok, "Finite indexed triangles and bounded UVs")
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			assert_not_null(material)
			assert_lte(material.albedo_texture.get_width(), 128)
			assert_lte(material.albedo_texture.get_height(), 128)


func test_streamed_rooms_have_supported_routes_matching_endpoints_and_safety() -> void:
	var suites := SUITES.instantiate() as Node3D
	add_child_autofree(suites)
	var room := suites.get_node("Room") as StreamedRoom
	room.load_room(60000)
	room.set_physics_process(false)
	for table: CrownGameTable in get_tree().get_nodes_in_group(&"crown_game_tables"):
		table.set_process(false)
	await get_tree().physics_frame
	assert_true(SafeZone.covers(get_tree(), Vector3(0, 1, -6000)))
	assert_not_null(suites.get_node("Room/CardGPS"))
	assert_not_null(suites.get_node("Room/DiceGPS"))
	assert_not_null(suites.get_node("Room/VIPGPS"))
	for x: float in [-12, -6, 0, 6, 12]:
		var at := room.to_global(Vector3(x, 0, 1))
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3, at - Vector3.UP, 1)
		var hit := room.get_world_3d().direct_space_state.intersect_ray(query)
		assert_false(hit.is_empty(), "Rooms and connecting aisle have floor support")
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, 0.0, .02)
	for x: float in [-6, 6]:
		var at := room.to_global(Vector3(x, 1, 1))
		var crossing := PhysicsRayQueryParameters3D.create(
			at - Vector3.RIGHT, at + Vector3.RIGHT, 1
		)
		assert_true(
			room.get_world_3d().direct_space_state.intersect_ray(crossing).is_empty(),
			"Connecting doorways have standing clearance"
		)
		at = room.to_global(Vector3(x, 1, -3))
		var partition := PhysicsRayQueryParameters3D.create(
			at - Vector3.RIGHT, at + Vector3.RIGHT, 1
		)
		assert_false(
			room.get_world_3d().direct_space_state.intersect_ray(partition).is_empty(),
			"Room partitions have collision"
		)
	for at: Vector3 in [Vector3(-17, 1, 0), Vector3(17, 1, 0)]:
		var direction := Vector3.LEFT if at.x < 0 else Vector3.RIGHT
		var boundary := PhysicsRayQueryParameters3D.create(
			room.to_global(at), room.to_global(at + direction * 2), 1
		)
		assert_false(
			room.get_world_3d().direct_space_state.intersect_ray(boundary).is_empty(),
			"Exterior side walls are closed"
		)
	for id: String in ["Blackjack", "Poker", "Baccarat", "Craps", "VideoPoker"]:
		var table := room.get_node(id) as CrownGameTable
		var collider := table.get_node("Collider") as CollisionShape3D
		assert_eq(
			(collider.shape as BoxShape3D).size,
			(table.get_node("Model") as MeshInstance3D).mesh.get_aabb().size
		)
		assert_eq(table.entity.replicated_properties, [NodePath(".:state")])
