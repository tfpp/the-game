extends SceneTree
## Normalize the two authored tiles to a ceiling-centred origin in metres.


func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(
		(
			document.append_from_file(
				"res://assets/room_kits/ceiling_tiles/ceiling_tiles.gltf", state
			)
			== OK
		)
	)
	var root := document.generate_scene(state)
	var nodes := root.find_children("*", "MeshInstance3D", true, false)
	assert(nodes.size() == 2)
	for node: Node in nodes:
		var instance := node as MeshInstance3D
		var tin := instance.name == &"TinCeilingTile"
		var transform := instance.transform
		transform.origin = Vector3.ZERO
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(instance.mesh, 0, transform)
		tool.index()
		var mesh := tool.commit()
		assert(mesh.get_surface_count() == 1)
		assert(mesh.get_faces().size() == (34 if tin else 2) * 3)
		var bounds := mesh.get_aabb()
		assert(is_equal_approx(bounds.position.x, -0.5))
		assert(is_equal_approx(bounds.position.z, -0.5))
		assert(is_equal_approx(bounds.size.x, 1.0))
		assert(is_equal_approx(bounds.size.z, 1.0))
		assert(is_equal_approx(bounds.position.y + bounds.size.y, 0.0))
		assert(is_equal_approx(bounds.size.y, 0.012 if tin else 0.0))
		var arrays := mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for uv: Vector2 in uvs:
			assert(uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1)
		for normal: Vector3 in normals:
			assert(normal.y < -0.5, "Tile must face the room below")
		mesh.surface_set_material(0, null)
		var output := (
			"res://assets/room_kits/ceiling_tiles/tin_ceiling_tile.res"
			if tin
			else "res://assets/room_kits/ceiling_tiles/basic_ceiling_tile.res"
		)
		assert(ResourceSaver.save(mesh, output) == OK)
		print(
			"CEILING VERIFIED: ",
			instance.name,
			" bounds=",
			bounds,
			" triangles=",
			mesh.get_faces().size() / 3
		)
	root.free()
	quit()
