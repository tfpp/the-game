extends GutTest

const SHOWCASE := preload("res://features/casino_props/bundle_showcase.tscn")
const PLACEMENT := preload("res://features/casino_props/bundle_furnishings.tscn")
const COUNTS := [116, 150, 60, 160, 104, 12, 44, 76, 154, 68, 134, 48, 68, 20, 68]
const SIZES := [128, 128, 128, 128, 32, 32, 32, 32, 64, 64, 32, 32, 16, 16, 32]


func test_import_preserves_counts_dimensions_uvs_and_outward_normals() -> void:
	var showcase := SHOWCASE.instantiate() as Node3D
	add_child_autofree(showcase)
	assert_eq(showcase.get_child_count(), 15)
	for i: int in showcase.get_child_count():
		var prop := showcase.get_child(i) as StaticBody3D
		var visual := prop.get_node("Model") as MeshInstance3D
		var arrays := visual.mesh.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_eq(indices.size(), COUNTS[i] * 3, prop.name)
		assert_eq(normals.size(), positions.size())
		assert_eq(uvs.size(), positions.size())
		for index: int in positions.size():
			assert_true(positions[index].is_finite())
			assert_almost_eq(normals[index].length(), 1.0, 0.001)
			assert_true(uvs[index].is_finite())
			assert_true(uvs[index].x >= 0 and uvs[index].x <= 1)
			assert_true(uvs[index].y >= 0 and uvs[index].y <= 1)
		for index: int in range(0, indices.size(), 3):
			var a := positions[indices[index]]
			var b := positions[indices[index + 1]]
			var c := positions[indices[index + 2]]
			var cross := (b - a).cross(c - a)
			assert_true(cross.length_squared() > 1e-16)
			assert_true(cross.dot(normals[indices[index]]) < 0, "Godot clockwise front")
		var material := visual.material_override as StandardMaterial3D
		assert_eq(material.albedo_texture.get_width(), SIZES[i])
		assert_eq(material.albedo_texture.get_height(), SIZES[i])
		assert_true(material.albedo_texture.get_image().has_mipmaps())
		assert_eq(material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
		assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
		var collider := prop.get_node("Collider") as CollisionShape3D
		assert_almost_eq(
			collider.position, visual.mesh.get_aabb().get_center(), Vector3.ONE * 0.001
		)
	var cigar := showcase.get_node("Cigar/Model") as MeshInstance3D
	assert_almost_eq(cigar.mesh.get_aabb().size.x, 0.13, 0.001)
	var emission := cigar.material_override as StandardMaterial3D
	assert_true(emission.emission_enabled)
	assert_eq(emission.emission_operator, BaseMaterial3D.EMISSION_OP_MULTIPLY)
	assert_eq(emission.emission_texture.get_width(), 16)
	assert_eq(emission.emission_texture.get_height(), 16)


func test_live_placement_keeps_decorations_nonblocking_and_rejected_bin_out() -> void:
	var placement := PLACEMENT.instantiate() as Node3D
	add_child_autofree(placement)
	assert_eq(placement.get_child_count(), 13)
	for name: String in ["Martini", "Cigar", "WineBucket", "WineBottle", "BeerBottle", "Clock"]:
		var prop := placement.get_node(name) as StaticBody3D
		assert_eq(prop.collision_layer, 0)
		assert_eq(prop.collision_mask, 0)
	for prop: Node3D in placement.get_children():
		assert_ne(prop.get_meta("prop_id"), "galvanised-rubbish-bin")
		assert_true(absf(prop.position.x) > 4, "Keep central ramps clear")
	var furniture := load("res://features/casino_hub/gridmap/furnishings.tscn") as PackedScene
	var room := furniture.instantiate() as Node3D
	add_child_autofree(room)
	assert_not_null(room.get_node_or_null("BundleFurnishings/Sofa/Model"))
