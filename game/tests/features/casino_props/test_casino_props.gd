extends GutTest

const SHOWCASE := preload("res://features/casino_props/showcase.tscn")


func test_complete_kit_preserves_mesh_uvs_textures_and_collision() -> void:
	var showcase := SHOWCASE.instantiate() as Node3D
	add_child_autofree(showcase)
	assert_eq(showcase.get_child_count(), 50)
	var texture_paths: Array[String] = []
	var counts := {16: 0, 32: 0, 64: 0, 128: 0}
	var triangles := 0
	for prop: StaticBody3D in showcase.get_children():
		var visual := prop.get_node("Model") as MeshInstance3D
		assert_true(visual.mesh is ArrayMesh)
		var arrays := visual.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		assert_eq(vertices.size(), uvs.size())
		triangles += vertices.size() / 3
		for uv: Vector2 in uvs:
			assert_true(uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1)
		var material := visual.material_override as StandardMaterial3D
		assert_eq(material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
		var texture := material.albedo_texture
		assert_false(texture_paths.has(texture.resource_path), prop.name)
		texture_paths.append(texture.resource_path)
		assert_true(counts.has(texture.get_width()))
		assert_eq(texture.get_width(), texture.get_height())
		counts[texture.get_width()] += 1
		var collider := prop.get_node("Collider") as CollisionShape3D
		assert_true(collider.shape is BoxShape3D)
		var shape := collider.shape as BoxShape3D
		assert_true(shape.size.x > 0 and shape.size.y > 0 and shape.size.z > 0)
	assert_eq(counts, {16: 1, 32: 13, 64: 19, 128: 17})
	assert_eq(triangles, 9320)
