extends Node3D
## Portable visual export; the native kit retains sockets, collision and the controller.

const LAYOUT := preload("res://features/street_district/layout.gd")
const OBJECTS := preload("res://features/street_district/street_objects.tscn")


func _ready() -> void:
	_run()


func _run() -> void:
	var parent := Node3D.new()
	add_child(parent)
	var district := LAYOUT.build(parent)
	district.add_child(OBJECTS.instantiate())
	var visual := Node3D.new()
	visual.name = "SocketStreetDistrict"
	add_child(visual)
	var index := 0
	for source: MeshInstance3D in district.find_children("*", "MeshInstance3D", true, false):
		var node := MeshInstance3D.new()
		node.name = "%s_%d" % [source.name, index]
		index += 1
		visual.add_child(node)
		node.transform = source.global_transform
		node.mesh = _mesh_with_uv(source)
		var material := source.material_override as StandardMaterial3D
		if material != null:
			var copy := material.duplicate() as StandardMaterial3D
			copy.uv1_triplanar = false
			copy.uv1_world_triplanar = false
			copy.uv1_scale = Vector3.ONE
			node.material_override = copy
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if not args.is_empty() else "user://street-export"
	DirAccess.make_dir_recursive_absolute(folder)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(visual, state) == OK)
	assert(document.write_to_filesystem(state, folder + "/street_district.glb") == OK)
	var joins: Array[Dictionary] = []
	for join: Dictionary in district.get_meta("joins"):
		var socket := join["from"] as ProceduralSocketAttachment
		joins.append(
			{
				"id": socket.join_id,
				"position":
				[socket.global_position.x, socket.global_position.y, socket.global_position.z],
				"width": socket.profile.width,
				"height": socket.profile.height
			}
		)
	var manifest := {"modules": 29, "joins": joins, "enterable_buildings": 2, "interior_rooms": 4}
	var file := FileAccess.open(folder + "/resolved_layout.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("STREET_VISUAL_EXPORT: ", folder)
	parent.free()
	visual.free()
	get_tree().quit()


func _mesh_with_uv(source: MeshInstance3D) -> Mesh:
	var arrays := source.mesh.surface_get_arrays(0)
	var existing: Variant = arrays[Mesh.ARRAY_TEX_UV]
	if existing is PackedVector2Array and not existing.is_empty():
		var material := source.material_override as StandardMaterial3D
		if (
			material == null
			or (material.uv1_scale == Vector3.ONE and material.uv1_offset == Vector3.ZERO)
		):
			return source.mesh
		var baked: PackedVector2Array = existing.duplicate()
		for i: int in baked.size():
			baked[i] = (
				baked[i] * Vector2(material.uv1_scale.x, material.uv1_scale.y)
				+ Vector2(material.uv1_offset.x, material.uv1_offset.y)
			)
		arrays[Mesh.ARRAY_TEX_UV] = baked
		var mapped := ArrayMesh.new()
		mapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mapped
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in range(0, indices.size(), 3):
		var a := positions[indices[i]]
		var b := positions[indices[i + 1]]
		var c := positions[indices[i + 2]]
		var normal := (c - a).cross(b - a).normalized()
		var axis := normal.abs().max_axis_index()
		for point: Vector3 in [a, b, c]:
			vertices.append(point)
			normals.append(normal)
			var world := source.to_global(point)
			var uv := Vector2(world.x, world.z)
			if axis == 0:
				uv = Vector2(world.z, -world.y)
			elif axis == 2:
				uv = Vector2(world.x, -world.y)
			uvs.append(uv * .5)
	var data: Array = []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_NORMAL] = normals
	data[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	return mesh
