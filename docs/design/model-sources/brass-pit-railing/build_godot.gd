extends SceneTree
## Import the authored Blockbench meshes, baking all export transforms into metres.


func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(
		(
			document.append_from_file(
				"res://assets/room_kits/brass_pit_railing/brass_pit_railing.gltf", state
			)
			== OK
		)
	)
	var root := document.generate_scene(state)
	var expected := {"BrassRailSpan": 56, "BrassRailPost": 104}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(instance.mesh, 0, instance.transform)
		tool.index()
		var mesh := tool.commit()
		mesh.surface_set_material(0, null)
		assert(mesh.get_faces().size() / 3 == expected[str(instance.name)])
		assert(mesh.get_surface_count() == 1)
		var path := (
			"res://assets/room_kits/brass_pit_railing/rail_span.res"
			if instance.name == &"BrassRailSpan"
			else "res://assets/room_kits/brass_pit_railing/rail_post.res"
		)
		assert(ResourceSaver.save(mesh, path) == OK)
		print(
			"RAILING: ",
			instance.name,
			" ",
			mesh.get_aabb(),
			" triangles=",
			mesh.get_faces().size() / 3
		)
	root.free()
	quit()
