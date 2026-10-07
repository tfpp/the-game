extends RefCounted
## Bake static car surfaces by material. Door paths and animations remain intact.


static func bake(train: Node3D) -> void:
	for car: Node in train.get_children():
		if not car.name.begins_with("Car"):
			continue
		var batches: Dictionary[Material, SurfaceTool] = {}
		for node: Node in car.get_children():
			if node is MeshInstance3D:
				var instance := node as MeshInstance3D
				_append(batches, instance.mesh, instance.transform, instance.material_override)
				node.free()
			elif node is GridMap:
				var grid := node as GridMap
				for cell: Vector3i in grid.get_used_cells():
					var item := grid.get_cell_item(cell)
					var pose := Transform3D(grid.get_cell_item_basis(cell), grid.map_to_local(cell))
					_append(
						batches,
						grid.mesh_library.get_item_mesh(item),
						grid.transform * pose * grid.mesh_library.get_item_mesh_transform(item)
					)
				node.free()
		for material: Material in batches:
			var mesh := batches[material].commit()
			mesh.surface_set_material(0, material)
			var instance := MeshInstance3D.new()
			instance.name = "Static%d" % car.get_child_count()
			instance.mesh = mesh
			car.add_child(instance)
		_doors(car)


static func _doors(car: Node) -> void:
	var groups: Dictionary[Mesh, Array] = {}
	for child: Node in car.get_children():
		if not child is AnimatableBody3D:
			continue
		var visual := child.get_node_or_null("Visual") as MeshInstance3D
		if visual == null:
			continue
		if not groups.has(visual.mesh):
			groups[visual.mesh] = []
		groups[visual.mesh].append(visual)
	for mesh: Mesh in groups:
		var batch := MultiMeshInstance3D.new()
		batch.set_script(load("res://features/metro/door_batch.gd"))
		batch.name = "DoorBatch%d" % car.get_child_count()
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = mesh
		batch.multimesh.instance_count = groups[mesh].size()
		car.add_child(batch)
		var paths: Array[NodePath] = []
		var poses: Array[Transform3D] = []
		var index := 0
		for visual: MeshInstance3D in groups[mesh]:
			var door := visual.get_parent() as Node3D
			paths.append(batch.get_path_to(door))
			poses.append(visual.transform)
			batch.material_override = visual.material_override
			batch.multimesh.set_instance_transform(index, door.transform * visual.transform)
			index += 1
			visual.free()
		batch.set("door_paths", paths)
		batch.set("visual_transforms", poses)


static func _append(
	batches: Dictionary[Material, SurfaceTool],
	mesh: Mesh,
	pose: Transform3D,
	override: Material = null
) -> void:
	for surface: int in mesh.get_surface_count():
		var material := override if override != null else mesh.surface_get_material(surface)
		if not batches.has(material):
			var builder := SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[material] = builder
		batches[material].append_from(mesh, surface, pose)
