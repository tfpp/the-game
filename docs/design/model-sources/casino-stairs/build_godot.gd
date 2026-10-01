extends SceneTree


func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(
		(
			document.append_from_file(
				"res://assets/room_kits/casino_stairs/casino_stair_module.gltf", state
			)
			== OK
		)
	)
	var model := document.generate_scene(state)
	var parts := model.find_children("*", "MeshInstance3D", true, false)
	assert(parts.size() == 1)
	var part := parts[0] as MeshInstance3D
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(part.mesh, 0, part.transform)
	tool.index()
	var mesh := tool.commit()
	assert(mesh.get_faces().size() == 132)
	assert(mesh.get_aabb().size.is_equal_approx(Vector3(1, 1.25, 2)))
	mesh.surface_set_material(0, null)
	assert(
		(
			ResourceSaver.save(mesh, "res://assets/room_kits/casino_stairs/casino_stair_module.res")
			== OK
		)
	)
	model.free()
	quit()
