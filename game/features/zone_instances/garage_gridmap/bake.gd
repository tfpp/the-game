extends Node
## Offline conversion of the authored garage shell into five saved level tiles.
## Runtime actors and their RPC paths do not belong in this static scene.

const LAYOUT := preload("res://features/procedural_rooms/world_layout.gd")
const OUTPUT := "res://features/zone_instances/garage_gridmap/"
const MATERIALS := {
	"Floor": preload("res://features/procedural_rooms/materials/garage_floor.tres"),
	"Wall": preload("res://features/procedural_rooms/materials/garage_wall.tres"),
	"Roof": preload("res://features/procedural_rooms/materials/garage_ceiling.tres"),
	"Grey": preload("res://features/procedural_rooms/materials/garage_rail.tres"),
	"Wet": preload("res://features/procedural_rooms/materials/garage_puddle.tres")
}


func _ready() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var source := Node3D.new()
	get_tree().root.add_child(source)
	var world := LAYOUT.build(source, 73021, [], false)
	var structure := world.get_node("Structure") as Node3D
	var collision := structure.get_node("ShellCollision").get_child(0) as CollisionShape3D
	var faces := (collision.shape as ConcavePolygonShape3D).get_faces()
	var library := MeshLibrary.new()
	for floor_index: int in 5:
		var mesh := ArrayMesh.new()
		for node: Node in structure.get_children():
			if node is MeshInstance3D:
				_add_surface(mesh, node as MeshInstance3D, floor_index)
		var shape := ConcavePolygonShape3D.new()
		var selected := PackedVector3Array()
		var origin := Vector3(0, floor_index * 4.0, 0)
		for index: int in range(0, faces.size(), 3):
			if _level(faces[index], faces[index + 1], faces[index + 2]) != floor_index:
				continue
			for corner: int in 3:
				selected.append(faces[index + corner] - origin)
		shape.set_faces(selected)
		shape.backface_collision = true
		library.create_item(floor_index)
		library.set_item_name(floor_index, "Garage B%d" % (5 - floor_index))
		library.set_item_mesh(floor_index, mesh)
		library.set_item_shapes(floor_index, [shape, Transform3D.IDENTITY])
	if ResourceSaver.save(library, OUTPUT + "garage_levels.tres") != OK:
		push_error("Cannot save garage MeshLibrary")
		source.free()
		get_tree().quit(1)
		return
	library.take_over_path(OUTPUT + "garage_levels.tres")
	var collision_library := MeshLibrary.new()
	for item: int in library.get_item_list():
		collision_library.create_item(item)
		collision_library.set_item_name(item, library.get_item_name(item))
		var shapes := library.get_item_shapes(item)
		collision_library.set_item_shapes(item, [(shapes[0] as Shape3D).duplicate(), shapes[1]])
	var result := ResourceSaver.save(collision_library, OUTPUT + "collision_levels.tres")
	if result == OK:
		collision_library.take_over_path(OUTPUT + "collision_levels.tres")
		result = _save_scene(collision_library, "collision.tscn")
	if result == OK:
		result = _save_scene(library, "static.tscn")
	source.free()
	print("Garage GridMap bake: five level tiles, %d collision triangles" % (faces.size() / 3))
	get_tree().quit(0 if result == OK else 1)


func _save_scene(library: MeshLibrary, filename: String) -> Error:
	var scene := Node3D.new()
	scene.name = "GarageStatic"
	var grid := GridMap.new()
	grid.name = "Levels"
	grid.mesh_library = library
	grid.cell_size = Vector3(1, 4, 1)
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	grid.cell_octant_size = 1
	scene.add_child(grid)
	grid.owner = scene
	for floor_index: int in 5:
		grid.set_cell_item(Vector3i(0, floor_index, 0), floor_index)
	var packed := PackedScene.new()
	var result := packed.pack(scene)
	if result == OK:
		result = ResourceSaver.save(packed, OUTPUT + filename)
	scene.free()
	return result


func _add_surface(target: ArrayMesh, source: MeshInstance3D, floor_index: int) -> void:
	var input := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = input[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = input[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = input[Mesh.ARRAY_INDEX]
	var selected_vertices := PackedVector3Array()
	var selected_normals := PackedVector3Array()
	var selected_indices := PackedInt32Array()
	var remap: Dictionary[int, int] = {}
	var origin := Vector3(0, floor_index * 4.0, 0)
	for index: int in range(0, indices.size(), 3):
		if (
			_level(
				vertices[indices[index]], vertices[indices[index + 1]], vertices[indices[index + 2]]
			)
			!= floor_index
		):
			continue
		for corner: int in 3:
			var old := indices[index + corner]
			if not remap.has(old):
				remap[old] = selected_vertices.size()
				selected_vertices.append(vertices[old] - origin)
				selected_normals.append(normals[old])
			selected_indices.append(remap[old])
	if selected_indices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = selected_vertices
	arrays[Mesh.ARRAY_NORMAL] = selected_normals
	arrays[Mesh.ARRAY_INDEX] = selected_indices
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := (
		(MATERIALS[str(source.name)] as StandardMaterial3D).duplicate() as StandardMaterial3D
	)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	target.surface_set_material(target.get_surface_count() - 1, material)


func _level(a: Vector3, b: Vector3, c: Vector3) -> int:
	return clampi(floori((a.y + b.y + c.y) / 12.0), 0, 4)
