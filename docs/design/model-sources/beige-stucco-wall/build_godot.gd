extends SceneTree
## Convert the Blockbench export and check quarter-wall dimensions and mapping.


func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(
		(
			document.append_from_file(
				"res://assets/room_kits/beige_stucco_wall/beige_stucco_wall.gltf", state
			)
			== OK
		)
	)
	var root := document.generate_scene(state)
	var instances := root.find_children("*", "MeshInstance3D", true, false)
	assert(instances.size() == 1)
	var instance := instances[0] as MeshInstance3D
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(instance.mesh, 0, instance.transform)
	tool.index()
	var mesh := tool.commit()
	assert(mesh.get_surface_count() == 1)
	assert(mesh.get_faces().size() == 36)
	assert(mesh.get_aabb().position.is_equal_approx(Vector3(-0.5, 0, -0.1)))
	assert(mesh.get_aabb().size.is_equal_approx(Vector3(1, 1.25, 0.2)))
	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for uv: Vector2 in uvs:
		assert(uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1)
	mesh.surface_set_material(0, null)
	assert(
		(
			ResourceSaver.save(
				mesh, "res://assets/room_kits/beige_stucco_wall/beige_stucco_wall.res"
			)
			== OK
		)
	)
	print("STUCCO VERIFIED: 1 x 1.25 x 0.2 m; 12 triangles; one surface; UVs in bounds")
	root.free()
	quit()
