extends SceneTree
## Bake the authored full-wall mesh and a cropped upper-hall variant without UV stretching.

const OUTPUT := "res://assets/room_kits/beige_stucco_wall_full/"


func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(OUTPUT + "beige_stucco_wall_full.gltf", state) == OK)
	var model := document.generate_scene(state)
	var parts := model.find_children("*", "MeshInstance3D", true, false)
	assert(parts.size() == 1)
	var part := parts[0] as MeshInstance3D
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(part.mesh, 0, part.transform)
	tool.index()
	var mesh := tool.commit()
	assert(mesh.get_aabb().position.is_equal_approx(Vector3(-0.5, 0, -0.1)))
	assert(mesh.get_aabb().size.is_equal_approx(Vector3(1, 5, 0.2)))
	assert(mesh.get_faces().size() == 36)
	mesh.surface_set_material(0, null)
	assert(ResourceSaver.save(mesh, OUTPUT + "beige_stucco_wall_full.res") == OK)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index: int in vertices.size():
		# Crop 1.25 m (30 atlas pixels) from the top of vertical islands.
		if vertices[index].y > 0 and absf(normals[index].y) < 0.1:
			uvs[index].y += 30.0 / 128.0
		vertices[index].y *= 0.75
		assert(uvs[index].x >= 0 and uvs[index].x <= 1)
		assert(uvs[index].y >= 0 and uvs[index].y <= 1)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var upper := ArrayMesh.new()
	upper.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assert(upper.get_aabb().size.is_equal_approx(Vector3(1, 3.75, 0.2)))
	assert(ResourceSaver.save(upper, OUTPUT + "beige_stucco_wall_upper.res") == OK)
	print("STUCCO VERIFIED: 5 m full wall and 3.75 m upper wall; 12 triangles each")
	model.free()
	quit()
