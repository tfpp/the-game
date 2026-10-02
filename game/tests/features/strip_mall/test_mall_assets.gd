extends GutTest

const LIBRARY := preload("res://features/strip_mall/tiles.tres")
const STRUCTURE := preload("res://features/strip_mall/structure.tscn")


func test_new_gridset_has_small_painted_indexed_meshes_and_collision() -> void:
	assert_eq(LIBRARY.get_item_list().size(), 10)
	for id: int in LIBRARY.get_item_list():
		var mesh := LIBRARY.get_item_mesh(id) as ArrayMesh
		assert_not_null(mesh)
		assert_eq(mesh.get_surface_count(), 1)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_lte(indices.size() / 3, 100)
		for index: int in vertices.size():
			assert_true(vertices[index].is_finite())
			assert_almost_eq(normals[index].length(), 1.0, .001)
			assert_between(uv[index].x, 0.0, 1.0)
			assert_between(uv[index].y, 0.0, 1.0)
		for t: int in range(0, indices.size(), 3):
			var a := vertices[indices[t]]
			var b := vertices[indices[t + 1]]
			var c := vertices[indices[t + 2]]
			assert_gt((b - a).cross(c - a).length(), .000001)
			assert_lt((b - a).cross(c - a).dot(normals[indices[t]]), 0.0)
		var material := mesh.surface_get_material(0) as StandardMaterial3D
		assert_eq(material.albedo_texture.get_size(), Vector2(128, 128))
		assert_eq(material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
		assert_true(material.albedo_texture.get_image().has_mipmaps())
		if id != 4:
			assert_false(LIBRARY.get_item_shapes(id).is_empty())


func test_saved_architecture_uses_only_editable_gridmap_tiles() -> void:
	var scene := STRUCTURE.instantiate()
	add_child_autofree(scene)
	assert_true(scene.find_children("*", "CSGShape3D", true).is_empty())
	var grids := scene.find_children("*", "GridMap", false)
	assert_eq(grids.size(), 12)
	for grid: GridMap in grids:
		assert_eq(grid.mesh_library, LIBRARY)
		assert_eq(grid.cell_size, Vector3(1, .25, 1))
		assert_eq(grid.cell_octant_size, 8)
		assert_false(grid.get_used_cells().is_empty())


func test_floor_roofs_and_planters_share_exact_grounding() -> void:
	var floor_mesh := LIBRARY.get_item_mesh(0)
	assert_almost_eq(floor_mesh.get_aabb().end.y, 0.0, .001)
	var planter := LIBRARY.get_item_mesh(7)
	assert_almost_eq(planter.get_aabb().position.y, 0.0, .001)
	var scene := STRUCTURE.instantiate()
	add_child_autofree(scene)
	var roof := scene.get_node("ShopRoof") as GridMap
	for cell: Vector3i in roof.get_used_cells():
		assert_eq(cell.y, 16, "Ceiling underside is 4 m")
	var canopies := scene.get_node("Awnings") as GridMap
	var mesh := LIBRARY.get_item_mesh(4)
	assert_gte(mesh.get_aabb().position.y, 2.7, "Standing capsule fits under the awning")
	assert_eq(canopies.get_used_cells().size(), 22)
