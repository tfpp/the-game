extends GutTest

var _avatar: BlockPlayerModel


func before_each() -> void:
	_avatar = BlockPlayerModel.new()
	add_child_autofree(_avatar)


func test_projection_is_paired_forward_bounded_and_clear_of_other_body_parts() -> void:
	var center := Vector3(PlayerChest.CENTER.x, PlayerChest.CENTER.y, -0.1)
	assert_eq(PlayerChest.projection_at(center), PlayerChest.PROJECTION)
	assert_eq(
		PlayerChest.projection_at(center),
		PlayerChest.projection_at(Vector3(-center.x, center.y, center.z))
	)
	assert_lt(
		PlayerChest.projection_at(Vector3(0, center.y, center.z)), PlayerChest.PROJECTION * 0.5
	)
	for point: Vector3 in [
		Vector3(0.3, 0.3, -0.1),
		Vector3(0.1, 0.5, -0.1),
		Vector3(0.1, 0, -0.1),
		Vector3(0.1, 0.3, 0.1)
	]:
		assert_eq(PlayerChest.projection_at(point), 0.0)
	for x: int in range(-30, 31):
		for y: int in range(0, 51):
			assert_between(
				PlayerChest.projection_at(Vector3(x * 0.01, y * 0.01, -0.1)),
				0.0,
				PlayerChest.PROJECTION
			)


func test_morph_preserves_topology_uvs_weights_other_shapes_and_default_vertices() -> void:
	var original: Node = SkinnedHuman.MODEL.instantiate()
	add_child_autofree(original)
	var surface: MeshInstance3D = original.find_children("*", "MeshInstance3D", true, false)[0]
	var base := surface.mesh as ArrayMesh
	var mesh := _avatar.human.surface.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var original_arrays := base.surface_get_arrays(0)
	for slot: int in [
		Mesh.ARRAY_VERTEX,
		Mesh.ARRAY_INDEX,
		Mesh.ARRAY_TEX_UV,
		Mesh.ARRAY_TEX_UV2,
		Mesh.ARRAY_BONES,
		Mesh.ARRAY_WEIGHTS,
		Mesh.ARRAY_COLOR
	]:
		assert_eq(arrays[slot], original_arrays[slot], "Base data is untouched")
	_assert_normals_close(arrays[Mesh.ARRAY_NORMAL], original_arrays[Mesh.ARRAY_NORMAL])
	assert_eq(mesh.blend_shape_mode, base.blend_shape_mode)
	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(mesh.get_blend_shape_count(), base.get_blend_shape_count() + 1)
	var shapes := mesh.surface_get_blend_shape_arrays(0)
	var original_shapes := base.surface_get_blend_shape_arrays(0)
	for index: int in original_shapes.size():
		assert_eq(shapes[index][Mesh.ARRAY_VERTEX], original_shapes[index][Mesh.ARRAY_VERTEX])
		_assert_normals_close(
			shapes[index][Mesh.ARRAY_NORMAL], original_shapes[index][Mesh.ARRAY_NORMAL]
		)
		var tangents: PackedFloat32Array = shapes[index][Mesh.ARRAY_TANGENT]
		var original_tangents: PackedFloat32Array = original_shapes[index][Mesh.ARRAY_TANGENT]
		var maximum_error := 0.0
		for sample: int in tangents.size():
			maximum_error = maxf(maximum_error, absf(tangents[sample] - original_tangents[sample]))
		assert_lt(
			maximum_error, 0.001, "Normal/tangent repacking stays below quantization tolerance"
		)
	assert_eq(mesh.get_blend_shape_name(5), PlayerChest.SHAPE)
	assert_eq(_avatar.human.shape_weight(PlayerChest.SHAPE), 0.0)
	var second := BlockPlayerModel.new()
	add_child_autofree(second)
	assert_eq(second.human.surface.mesh, mesh, "All avatars share the cached mesh")


func test_morphed_vertices_and_normals_are_finite_front_only_and_connected_at_seams() -> void:
	var mesh := _avatar.human.surface.mesh
	var base := mesh.surface_get_arrays(0)
	var full: Array = (mesh as ArrayMesh).surface_get_blend_shape_arrays(0)[5]
	var vertices: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	var moved: PackedVector3Array = full[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = full[Mesh.ARRAY_NORMAL]
	var seam_positions: Dictionary = {}
	var changed := 0
	for index: int in vertices.size():
		assert_true(moved[index].is_finite())
		assert_true(
			mesh.get_aabb().grow(0.00001).has_point(moved[index]),
			"Culling bounds contain the morph"
		)
		assert_true(normals[index].is_finite())
		assert_almost_eq(normals[index].length(), 1.0, 0.001)
		assert_eq(moved[index].x, vertices[index].x)
		assert_eq(moved[index].y, vertices[index].y)
		var shift := vertices[index].z - moved[index].z
		assert_between(shift, -0.00001, PlayerChest.PROJECTION + 0.00001)
		if shift > 0.0001:
			changed += 1
			assert_lt(vertices[index].z, 0.0)
			assert_between(vertices[index].y, 0.17, 0.42)
			assert_lt(absf(vertices[index].x), 0.21)
		var key := Vector3i(
			roundi(vertices[index].x * 100000),
			roundi(vertices[index].y * 100000),
			roundi(vertices[index].z * 100000)
		)
		if seam_positions.has(key):
			assert_almost_eq(moved[index], seam_positions[key], Vector3.ONE * 0.00002)
		seam_positions[key] = moved[index]
	assert_gt(changed, 20, "The choice must change the actual silhouette")


func test_full_chest_has_no_degenerate_or_inverted_triangles_with_build_and_outfit() -> void:
	var mesh := _avatar.human.surface.mesh
	var arrays := mesh.surface_get_arrays(0)
	var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var shapes := (mesh as ArrayMesh).surface_get_blend_shape_arrays(0)
	var full: PackedVector3Array = shapes[5][Mesh.ARRAY_VERTEX]
	var feminine: PackedVector3Array = shapes[0][Mesh.ARRAY_VERTEX]
	var tactical: PackedVector3Array = shapes[4][Mesh.ARRAY_VERTEX]
	for girl: bool in [false, true]:
		for gear: bool in [false, true]:
			var reference := base.duplicate()
			for index: int in base.size():
				if girl:
					reference[index] += feminine[index] - base[index]
				if gear:
					reference[index] += tactical[index] - base[index]
			var final_vertices := reference.duplicate()
			for index: int in base.size():
				final_vertices[index] += full[index] - base[index]
			for offset: int in range(0, indices.size(), 3):
				var a := indices[offset]
				var b := indices[offset + 1]
				var c := indices[offset + 2]
				# Test triangles affected by the chest, not tiny legacy finger/hair
				# triangles or the original outfit deformation elsewhere.
				if full[a] == base[a] and full[b] == base[b] and full[c] == base[c]:
					continue
				var before := (reference[b] - reference[a]).cross(reference[c] - reference[a])
				var after := (final_vertices[b] - final_vertices[a]).cross(
					final_vertices[c] - final_vertices[a]
				)
				assert_gt(after.length_squared(), 0.000000000001)
				assert_gt(before.dot(after), 0.0, "Retain outward winding in every outfit")


func _assert_normals_close(actual: PackedVector3Array, original: PackedVector3Array) -> void:
	var maximum_error := 0.0
	assert_eq(actual.size(), original.size())
	for index: int in actual.size():
		maximum_error = maxf(maximum_error, actual[index].distance_to(original[index]))
	assert_lt(maximum_error, 0.001, "Repacking original normals only adds quantization error")


func test_human_builds_heads_tails_and_clothing_keep_the_chest_choice() -> void:
	var look := PlayerAppearance.defaults()
	look["chest"] = "full"
	_avatar.set_appearance(look)
	for body: String in ["default", "girl"]:
		_avatar.set_body_type(body)
		for head: String in PlayerModels.VALID_HEAD_TYPES:
			_avatar.set_head_type(head)
			for tail: String in PlayerModels.VALID_TAIL_TYPES:
				_avatar.set_tail_type(tail)
				assert_eq(_avatar.human.shape_weight(PlayerChest.SHAPE), 1.0)
				assert_true(_avatar.human.visible)
	_avatar.set_clothing("shirt:4", "pants:3")
	var pose := _avatar.human.skeleton.get_bone_global_pose(1)
	for outfit: String in PlayerAppearance.OUTFITS:
		look["outfit"] = outfit
		_avatar.set_appearance(look)
		assert_eq(_avatar.human.shape_weight(PlayerChest.SHAPE), 1.0)
		assert_eq(_avatar.shirt_color, ClothingCatalog.COLORS[4])
		assert_eq(_avatar.shirt_id, "shirt:4")
		assert_eq(_avatar.pants_id, "pants:3")
		assert_eq(_avatar.human.skeleton.get_bone_global_pose(1), pose)
	_avatar.set_body_type("penguin")
	assert_false(_avatar.human.visible, "Costume keeps its original silhouette")
	assert_eq(_avatar.chest, "full", "Preference is retained inside the costume")
	_avatar.set_body_type("default")
	assert_eq(_avatar.human.shape_weight(PlayerChest.SHAPE), 1.0)
	look.erase("chest")
	_avatar.set_appearance(look)
	assert_eq(_avatar.human.shape_weight(PlayerChest.SHAPE), 0.0)


func test_unshirted_full_chest_uses_coverage_and_reverts_without_inventory_changes() -> void:
	var look := PlayerAppearance.defaults()
	look["chest"] = "full"
	_avatar.set_appearance(look)
	assert_true(bool(_avatar.human.material.get_shader_parameter("chest_covered")))
	assert_false(bool(_avatar.human.material.get_shader_parameter("shirt_equipped")))
	assert_eq(_avatar.shirt_id, "")
	_avatar.set_clothing("shirt:2", "")
	assert_true(bool(_avatar.human.material.get_shader_parameter("shirt_equipped")))
	assert_eq(_avatar.shirt_color, ClothingCatalog.COLORS[2])
	_avatar.set_clothing("", "")
	assert_true(bool(_avatar.human.material.get_shader_parameter("chest_covered")))
	look["chest"] = "default"
	_avatar.set_appearance(look)
	assert_false(bool(_avatar.human.material.get_shader_parameter("chest_covered")))
	assert_eq(_avatar.shirt_id, "")
