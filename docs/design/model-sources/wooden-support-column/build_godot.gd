extends SceneTree
## Bake the Blockbench export into one shared mesh in metres.


func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(
		(
			document.append_from_file(
				"res://assets/room_kits/wooden_support_column/wooden_support_column.gltf", state
			)
			== OK
		)
	)
	var root := document.generate_scene(state)
	var instances := root.find_children("*", "MeshInstance3D", true, false)
	assert(instances.size() == 1)
	var instance := instances[0] as MeshInstance3D
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(instance.mesh, 0, instance.transform)
	surface.index()
	var mesh := surface.commit()
	assert(mesh.get_surface_count() == 1)
	assert(mesh.get_faces().size() == 108 * 3)
	assert(mesh.get_aabb().position.is_equal_approx(Vector3(-0.5, 0, -0.5)))
	assert(mesh.get_aabb().size.is_equal_approx(Vector3(1, 5, 1)))
	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for uv: Vector2 in uvs:
		assert(uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1)
	var texture := Image.new()
	assert(
		(
			texture.load(
				ProjectSettings.globalize_path(
					"res://assets/room_kits/wooden_support_column/wooden_support_column_albedo.png"
				)
			)
			== OK
		)
	)
	assert(texture.get_size() == Vector2i(32, 128))
	mesh.surface_set_material(0, null)
	assert(
		(
			ResourceSaver.save(
				mesh, "res://assets/room_kits/wooden_support_column/wooden_support_column.res"
			)
			== OK
		)
	)
	print("COLUMN VERIFIED: 1 x 5 x 1 m; 108 triangles; one surface; UVs in bounds")
	root.free()
	quit()
