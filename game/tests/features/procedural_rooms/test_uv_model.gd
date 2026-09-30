extends GutTest

const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const MODEL := preload("res://features/procedural_rooms/service_cabinet.tscn")
const GLB := preload("res://assets/procedural_rooms/models/service_cabinet/service_cabinet.glb")


func test_glb_round_trip_preserves_the_uv_layout() -> void:
	var model := GLB.instantiate() as Node3D
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1)
	var arrays := (meshes[0] as MeshInstance3D).mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var native := UV.mesh(UV.cabinet_faces()).surface_get_arrays(0)
	var expected: PackedVector2Array = native[Mesh.ARRAY_TEX_UV]
	var positions: PackedVector3Array = native[Mesh.ARRAY_VERTEX]
	assert_eq(uv.size(), expected.size())
	for index: int in expected.size():
		var found := false
		for exported: int in uv.size():
			# Godot quantizes imported mesh attributes; tolerate < 0.01 runtime pixel.
			if (
				expected[index].distance_to(uv[exported]) * UV.ATLAS_SIZE < 0.01
				and positions[index].distance_to(vertices[exported]) < 0.001
			):
				found = true
		assert_true(found, "UV and geometry corner association survives GLB export/import")
	model.free()


func test_feature_runtime_textures_obey_the_128px_limit() -> void:
	_check_textures("res://assets/procedural_rooms")


func _check_textures(directory: String) -> void:
	for name: String in DirAccess.get_files_at(directory):
		if name.get_extension() != "png":
			continue
		var path := directory.path_join(name)
		var texture := load(path) as Texture2D
		assert_not_null(texture, path)
		if texture != null:
			assert_lte(texture.get_width(), 128, path + " width")
			assert_lte(texture.get_height(), 128, path + " height")
	for name: String in DirAccess.get_directories_at(directory):
		_check_textures(directory.path_join(name))


func test_named_islands_have_unique_space_padding_and_consistent_density() -> void:
	var faces := UV.cabinet_faces()
	assert_eq(faces.size(), 6)
	assert_eq(UV.validate(faces), [])
	var broken := faces.duplicate(true)
	broken[1]["rect"] = broken[0]["rect"]
	assert_true(str(UV.validate(broken)).contains("overlapping"))
	broken = faces.duplicate(true)
	broken[0]["rect"] = Rect2i(0, 0, 30, 75)
	assert_true(str(UV.validate(broken)).contains("outside atlas"))
	broken = faces.duplicate(true)
	broken[0]["rect"] = Rect2i(4, 4, 20, 75)
	assert_true(str(UV.validate(broken)).contains("texel density"))


func test_mesh_uvs_are_complete_upright_and_match_saved_model() -> void:
	var mesh := UV.mesh(UV.cabinet_faces())
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(vertices.size(), 24)
	assert_eq(uv.size(), vertices.size())
	assert_eq(arrays[Mesh.ARRAY_TANGENT].size(), vertices.size() * 4)
	assert_eq(arrays[Mesh.ARRAY_INDEX].size(), 36)
	for point: Vector2 in uv:
		assert_between(point.x, 0.0, 1.0)
		assert_between(point.y, 0.0, 1.0)
	assert_lt(uv[0].y, uv[3].y, "Top of front face maps to top of image")
	assert_gt(vertices[0].y, vertices[3].y)
	var model := MODEL.instantiate() as Node3D
	var stored := (model.get_node("Cabinet") as MeshInstance3D).mesh.surface_get_arrays(0)
	assert_eq(stored[Mesh.ARRAY_TEX_UV], uv)
	assert_eq(stored[Mesh.ARRAY_VERTEX], vertices)
	var collision := model.get_node("Collision/Shape") as CollisionShape3D
	assert_eq((collision.shape as BoxShape3D).size, Vector3(0.6, 2.5, 1))
	model.free()


func test_albedo_processing_extrudes_edges_without_contaminating_other_islands() -> void:
	var source := UV.template(UV.cabinet_faces())
	var processed := UV.prepare_albedo(source, UV.cabinet_faces())
	assert_eq(processed.get_size(), Vector2i(128, 128))
	assert_eq(processed.get_pixel(2, 4), source.get_pixel(4, 4))
	assert_eq(processed.get_pixel(35, 4), source.get_pixel(33, 4))
	assert_ne(processed.get_pixel(35, 4), processed.get_pixel(36, 4))
	assert_eq(processed.get_pixel(120, 120), Color("222831"))
