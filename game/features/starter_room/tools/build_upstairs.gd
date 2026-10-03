extends SceneTree
## Explicit offline recipe; saved GridMaps remain editable and never rebuild on load.

const CASINO := preload("res://features/casino_hub/gridmap/casino_tiles.tres")
const CONCRETE := preload("res://features/starter_room/garage_tiles.tres")
const FLOOR := preload("res://features/procedural_rooms/materials/garage_floor.tres")
const STEEL := preload("res://features/procedural_rooms/materials/garage_rail.tres")


func _initialize() -> void:
	var garage := _garage_library()
	ResourceSaver.save(
		garage, "res://features/starter_room/upstairs_tiles.tres", ResourceSaver.FLAG_CHANGE_PATH
	)
	garage = load("res://features/starter_room/upstairs_tiles.tres") as MeshLibrary
	var area := Node3D.new()
	area.name = "Upstairs"
	var deck := _grid(area, "Deck", CONCRETE)
	for x: int in range(-8, -2):
		for z: int in range(-9, -4):
			deck.set_cell_item(Vector3i(x, 10, z), 0)
	var stairs := _grid(area, "Stairs", garage)
	stairs.position = Vector3(-5, 0, 0)
	stairs.rotation.y = PI
	for flight: int in 2:
		for x: int in 2:
			stairs.set_cell_item(Vector3i(x, flight * 5, flight * 2), 15)
	var slope := _grid(area, "StairRails", garage, true)
	slope.position = stairs.position
	slope.rotation.y = PI
	for x: int in [0, 2]:
		for flight: int in 2:
			slope.set_cell_item(Vector3i(x, flight * 5, flight * 2), 16)
	var rails := _grid(area, "Rails", garage, true)
	var turn := rails.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for z: int in [-8, -6]:
		rails.set_cell_item(Vector3i(-2, 10, z), 9, turn)
	# Southern rail stops at the two-metre stair mouth (-7 .. -5).
	rails.set_cell_item(Vector3i(-5, 10, -4), 9)
	for edge: int in [-8, -3]:
		var short := _grid(area, "ShortRail%s" % absi(edge), garage, true)
		short.position = Vector3(edge, 0, -4)
		short.scale.x = .5
		short.set_cell_item(Vector3i(0, 10, 0), 9)
	var posts := _grid(area, "Posts", garage, true)
	for point: Vector3i in [
		Vector3i(-2, 10, -8),
		Vector3i(-2, 10, -6),
		Vector3i(-2, 10, -4),
		Vector3i(-5, 10, -4),
		Vector3i(-7, 10, -4)
	]:
		posts.set_cell_item(point, 10)
	var scene := PackedScene.new()
	scene.pack(area)
	ResourceSaver.save(scene, "res://features/starter_room/upstairs.tscn")
	area.free()
	quit()


## Keep the proven walking proxy and cell contract, but not the casino finishes.
func _garage_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	for id: int in [9, 10, 15, 16]:
		library.create_item(id)
		library.set_item_shapes(id, CASINO.get_item_shapes(id))
		library.set_item_mesh_transform(id, CASINO.get_item_mesh_transform(id))
	var stairs := SurfaceTool.new()
	stairs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var source := CASINO.get_item_mesh(15)
	for surface: int in source.get_surface_count():
		stairs.append_from(source, surface, Transform3D.IDENTITY)
	stairs.index()
	var concrete := stairs.commit()
	concrete.surface_set_material(0, FLOOR)
	library.set_item_mesh(15, concrete)
	library.set_item_name(15, "GarageConcreteStairs")
	library.set_item_mesh(9, _guard(false))
	library.set_item_name(9, "GarageSteelGuard")
	library.set_item_mesh(16, _guard(true))
	library.set_item_name(16, "GarageSteelStairGuard")
	var post := SurfaceTool.new()
	post.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(post, Vector3(.09, 1.105, .09), Vector3(0, .5525, 0))
	var post_mesh := post.commit()
	post_mesh.surface_set_material(0, STEEL)
	library.set_item_mesh(10, post_mesh)
	library.set_item_name(10, "GarageSteelPost")
	return library


func _guard(sloped: bool) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y: float in [.54, 1.065]:
		_box(tool, Vector3(2, .08, .08), Vector3(1, y, 0))
	for x: float in [.04, 1.96]:
		_box(tool, Vector3(.08, 1.025, .08), Vector3(x, .5125, 0))
	tool.index()
	var mesh := tool.commit()
	if sloped:
		var slope := Basis(Vector3(0, .625, 1), Vector3.UP, Vector3.LEFT)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var normal_basis := slope.inverse().transposed()
		for i: int in vertices.size():
			vertices[i] = slope * vertices[i]
			normals[i] = (normal_basis * normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, STEEL)
	return mesh


func _box(tool: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	tool.append_from(box, 0, Transform3D(Basis.IDENTITY, at))


func _grid(parent: Node3D, title: String, library: MeshLibrary, exact := false) -> GridMap:
	var grid := GridMap.new()
	grid.name = title
	grid.mesh_library = library
	grid.cell_size = Vector3(1, .25, 1)
	grid.cell_center_y = false
	grid.cell_center_x = not exact
	grid.cell_center_z = not exact
	parent.add_child(grid)
	grid.owner = parent
	return grid
