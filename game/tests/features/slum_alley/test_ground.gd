extends GutTest

const GROUND := preload("res://features/slum_alley/ground.tscn")


func test_tiled_ground_preserves_entire_playable_floor_and_local_light_bounds() -> void:
	var grid := GROUND.instantiate() as GridMap
	add_child_autofree(grid)
	assert_eq(grid.get_used_cells().size(), 25)
	assert_eq(
		grid.cell_octant_size, 1, "Keep local light selection independent for each floor tile"
	)
	grid.make_baked_meshes(false)
	assert_eq(grid.get_bake_meshes().size() / 2, 25)
	await wait_physics_frames(2)
	var space := grid.get_world_3d().direct_space_state
	for x: float in [-24.9, -15.0, -.01, .01, 15.0, 24.9]:
		for z: float in [-24.9, -15.0, -.01, .01, 15.0, 24.9]:
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, 1, z), Vector3(x, -1, z), 1)
			var hit := space.intersect_ray(query)
			assert_false(hit.is_empty(), "Floor coverage at %s" % Vector2(x, z))
			if not hit.is_empty():
				assert_almost_eq((hit["position"] as Vector3).y, 0.0, .001)
	for index: int in grid.get_bake_meshes().size() / 2:
		var mesh := grid.get_bake_meshes()[index * 2] as Mesh
		assert_eq(mesh.get_aabb().size, Vector3(10, .4, 10))
