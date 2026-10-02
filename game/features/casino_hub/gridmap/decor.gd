extends RefCounted
## Reuse the original salon's framed canvas and imported fixtures in a decor-only library.

const FINISHES := preload("res://features/casino_hub/model_materials.gd")
const SALON_PATH := "res://features/casino_hub/salon.tscn"
const SCONCE := preload("res://features/casino_hub/models/brass_sconce.tscn")
const CHANDELIER := preload("res://features/casino_hub/models/brass_chandelier.tscn")
const PAINTING := 0
const WALL_LIGHT := 1
const PENDANT := 2


static func library() -> MeshLibrary:
	var result := MeshLibrary.new()
	var painting := _painting()
	var sconce := SCONCE.instantiate() as Node3D
	var chandelier := CHANDELIER.instantiate() as Node3D
	for node: Node3D in [painting, sconce, chandelier]:
		FINISHES.apply_finishes(node)
	var nodes: Array[Node3D] = [painting, sconce, chandelier]
	var names: Array[String] = ["FramedLandscape", "BrassSconce", "BrassChandelier"]
	for id: int in nodes.size():
		result.create_item(id)
		result.set_item_name(id, names[id])
		var mesh := _merge(nodes[id])
		result.set_item_mesh(id, mesh)
		var offset := Vector3(0, 0, 0.18)
		if id == PENDANT:
			offset = Vector3(0, -mesh.get_aabb().end.y, 0)
		result.set_item_mesh_transform(id, Transform3D(Basis.IDENTITY, offset))
		print("DECOR_TILE: ", names[id], " ", mesh.get_aabb())
		nodes[id].free()
	return result


static func _painting() -> Node3D:
	var result := Node3D.new()
	var state := (load(SALON_PATH) as PackedScene).get_state()
	var anchor := Vector3(-7, 4.55, -11.73)
	for index: int in state.get_node_count():
		var name := str(state.get_node_name(index))
		if (
			name != "GalleryPainting0"
			and not name.begins_with("GalleryFrameSide0_")
			and not name.begins_with("GalleryFrameTop0_")
		):
			continue
		var part := MeshInstance3D.new()
		for property: int in state.get_node_property_count(index):
			var key := state.get_node_property_name(index, property)
			if key == &"mesh":
				part.mesh = state.get_node_property_value(index, property) as Mesh
			elif key == &"position":
				part.position = state.get_node_property_value(index, property) - anchor
		result.add_child(part)
	return result


static func _merge(root: Node3D) -> ArrayMesh:
	var builders: Dictionary[Material, SurfaceTool] = {}
	_append(root, Transform3D.IDENTITY, builders)
	var result := ArrayMesh.new()
	for material: Material in builders:
		builders[material].index()
		builders[material].set_material(material)
		builders[material].commit(result)
	return result


static func _append(
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


static func populate(grid: GridMap) -> void:
	grid.clear()
	for x: int in [-16, -5, 5, 16]:
		_place(grid, WALL_LIGHT, Vector3i(x, 12, -20), 0)
	for x: int in [-16, -8, 16]:
		_place(grid, WALL_LIGHT, Vector3i(x, 12, 20), PI)
	for z: int in [-12, 0, 12]:
		_place(grid, WALL_LIGHT, Vector3i(-24, 12, z), PI / 2)
		_place(grid, WALL_LIGHT, Vector3i(24, 12, z), -PI / 2)
	for x: int in [-12, -4, 12]:
		_place(grid, PAINTING, Vector3i(x, 12, -20), 0)
		_place(grid, PAINTING, Vector3i(x, 12, 20), PI)
	for z: int in [-8, 4, 16]:
		_place(grid, PAINTING, Vector3i(-24, 12, z), PI / 2)
		_place(grid, PAINTING, Vector3i(24, 12, z), -PI / 2)
	for x: int in [7, 29]:
		_place(grid, WALL_LIGHT, Vector3i(x, 12, 20), 0)
	for x: int in [8, 28]:
		_place(grid, WALL_LIGHT, Vector3i(x, 12, 38), PI)
	for x: int in [13, 23]:
		_place(grid, PAINTING, Vector3i(x, 12, 38), PI)
	for z: int in [24]:
		_place(grid, WALL_LIGHT, Vector3i(-16, 12, z), PI / 2)
	for x: int in [-8]:
		_place(grid, WALL_LIGHT, Vector3i(x, 12, 30), PI)
	_place(grid, PAINTING, Vector3i(-9, 12, 30), PI)
	_place(grid, WALL_LIGHT, Vector3i(-2, 12, 21), PI / 2)
	_place(grid, WALL_LIGHT, Vector3i(2, 12, 29), -PI / 2)
	for x: int in [-6, 6]:
		for z: int in [-4, 4]:
			_place(grid, PENDANT, Vector3i(x, 20, z), 0)
	_place(grid, PENDANT, Vector3i(-7, 20, -10), 0)
	_place(grid, PENDANT, Vector3i(0, 20, 18), 0)
	for x: int in [10, 22]:
		_place(grid, PENDANT, Vector3i(x, 20, 28), 0)


static func _place(grid: GridMap, item: int, cell: Vector3i, yaw: float) -> void:
	grid.set_cell_item(cell, item, grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, yaw)))
