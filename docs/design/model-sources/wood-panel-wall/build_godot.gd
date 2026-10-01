extends SceneTree
## Convert the Blockbench glTF into a single reusable Godot mesh (metres).
## Run from the repository root: godot --headless --path game -s ../docs/design/model-sources/wood-panel-wall/build_godot.gd

func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file("res://assets/room_kits/wood_panel_wall/wood_panel_wall.gltf", state)
	assert(error == OK, "Could not read Blockbench export")
	var root := document.generate_scene(state)
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 1, "Expected one mesh")
	var instance := meshes[0] as MeshInstance3D
	var mesh := instance.mesh as ArrayMesh
	assert(instance.transform.is_equal_approx(Transform3D.IDENTITY), "Export must bake scale")
	assert(mesh.get_surface_count() == 1, "Expected one material surface")
	var bounds := mesh.get_aabb()
	assert(bounds.position.is_equal_approx(Vector3(-0.5, 0, -0.1)))
	assert(bounds.size.is_equal_approx(Vector3(1, 2.5, 0.2)))
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert(indices.size() == 312, "Expected 104 triangles")
	mesh.surface_set_material(0, null)
	error = ResourceSaver.save(mesh, "res://assets/room_kits/wood_panel_wall/wood_panel_wall.res")
	assert(error == OK)
	print("Wood wall verified: 1 x 2.5 x 0.2 m; 104 triangles; one mesh surface; identity transform")
	root.free()
	quit()
