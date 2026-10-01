extends SceneTree
## Bake the fixed 8 × 5 × 4 m module. Door leaves, buttons and lighting stay separate.

const BAY := preload("res://features/elevator/gridmap/bay.tscn")
const PATH := "res://features/elevator/gridmap/elevator_library.tres"


func _initialize() -> void:
	var bay := BAY.instantiate() as Node3D
	var builders: Dictionary[Material, SurfaceTool] = {}
	_append(bay, Transform3D.IDENTITY, builders)
	var mesh := ArrayMesh.new()
	for material: Material in builders:
		builders[material].index()
		builders[material].set_material(material)
		builders[material].commit(mesh)
	var library := MeshLibrary.new()
	library.create_item(0)
	library.set_item_name(0, "ElevatorBay")
	library.set_item_mesh(0, mesh)
	var shapes: Array = []
	for node: Node in bay.get_node("Body").get_children():
		var collider := node as CollisionShape3D
		shapes.append(collider.shape)
		shapes.append(collider.transform)
	library.set_item_shapes(0, shapes)
	assert(ResourceSaver.save(library, PATH) == OK)
	print(
		"ELEVATOR_BAY: ", mesh.get_faces().size() / 3, " triangles; ", shapes.size() / 2, " shapes"
	)
	bay.free()
	quit()


func _append(
	node: Node3D, parent: Transform3D, builders: Dictionary[Material, SurfaceTool]
) -> void:
	var transform := parent * node.transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface: int in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface)
			if not builders.has(material):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				builders[material] = tool
			builders[material].append_from(instance.mesh, surface, transform)
	for child: Node in node.get_children():
		if child is Node3D:
			_append(child as Node3D, transform, builders)
