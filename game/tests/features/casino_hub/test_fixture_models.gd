extends GutTest
## Validate actual native exports, not just the author's generation recipe.

const FIXTURES := [
	preload("res://features/casino_hub/models/brass_sconce.tscn"),
	preload("res://features/casino_hub/models/brass_chandelier.tscn")
]


func test_fixtures_have_valid_winding_uvs_and_small_shared_paint() -> void:
	for scene: PackedScene in FIXTURES:
		var root := scene.instantiate() as Node3D
		add_child_autofree(root)
		var model := root.get_node("Model") as MeshInstance3D
		assert_eq(model.mesh.get_surface_count(), 1)
		assert_lte(model.mesh.get_faces().size() / 3, 604)
		assert_true(root.find_children("*", "CollisionShape3D", true, false).is_empty())
		var finish := model.material_override as ShaderMaterial
		var atlas := finish.get_shader_parameter("atlas") as Texture2D
		assert_eq(atlas.get_size(), Vector2(64, 64))
		var arrays := model.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index: int in vertices.size():
			assert_true(vertices[index].is_finite())
			assert_almost_eq(normals[index].length(), 1.0, .001)
			assert_between(uvs[index].x, .05, .95)
			assert_between(uvs[index].y, .05, .95)
		for index: int in range(0, indices.size(), 3):
			var a := indices[index]
			var cross := (vertices[indices[index + 2]] - vertices[a]).cross(
				vertices[indices[index + 1]] - vertices[a]
			)
			assert_gt(cross.length(), .000001)
			assert_gt(cross.normalized().dot(normals[a]), .99)


func test_saved_decor_uses_replacement_fixtures_at_existing_cell_offsets() -> void:
	var library := load("res://features/casino_hub/gridmap/casino_decor.tres") as MeshLibrary
	assert_eq(library.get_item_mesh(1).get_faces().size() / 3, 200)
	assert_eq(library.get_item_mesh(2).get_faces().size() / 3, 604)
	assert_eq(library.get_item_mesh_transform(1).origin, Vector3(0, 0, .18))
	assert_eq(library.get_item_mesh_transform(2).origin.y, 0.0)
