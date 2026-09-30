extends RefCounted
## Emit only inward structural faces. A canonical vertex pool spans all modules.
## Split every face boundary at neighboring vertices to eliminate edge T-junctions.

const SNAP := 0.00001
const FLOOR := preload("res://features/procedural_rooms/materials/floor.tres")
const WALL := preload("res://features/procedural_rooms/materials/wall.tres")
const GREY := preload("res://features/procedural_rooms/materials/grey.tres")
const ROOF := preload("res://features/procedural_rooms/materials/ceiling.tres")


static func face(
	root: Node3D,
	points: PackedVector3Array,
	normal: Vector3,
	material: String,
	solid: bool = true,
	visible: bool = true,
	cap: Node3D = null
) -> void:
	var faces: Array = root.get_meta("shell_faces", [])
	faces.append(
		{
			"points": points,
			"normal": normal,
			"material": material,
			"solid": solid,
			"visible": visible,
			"cap_socket": cap.get_parent() if cap != null else null
		}
	)
	root.set_meta("shell_faces", faces)


static func rebuild(world: Node3D) -> void:
	var old := world.get_node_or_null("Structure")
	if old != null:
		old.free()
	var structure := Node3D.new()
	structure.name = "Structure"
	world.add_child(structure)
	var vertices := PackedVector3Array()
	var lookup: Dictionary[Vector3, int] = {}
	var faces: Array[Dictionary] = []
	for module: Node in world.find_children("*", "Node3D", true, false):
		if not module.has_meta("shell_faces"):
			continue
		for source: Dictionary in module.get_meta("shell_faces"):
			var socket: Node = source["cap_socket"]
			if socket != null and socket.get("cap") == null:
				continue
			var points := PackedVector3Array()
			for point: Vector3 in source["points"]:
				var canonical := world.to_local((module as Node3D).to_global(point)).snapped(
					Vector3.ONE * SNAP
				)
				points.append(canonical)
				_index(canonical, vertices, lookup)
			var value := source.duplicate()
			value["points"] = points
			value["normal"] = (
				world.global_basis.inverse() * (module as Node3D).global_basis * source["normal"]
			)
			faces.append(value)
	var boundary_vertices := vertices.duplicate()
	var groups: Dictionary[String, PackedInt32Array] = {}
	var collision := PackedVector3Array()
	var seen: Dictionary[String, bool] = {}
	for value: Dictionary in faces:
		var points: PackedVector3Array = value["points"]
		var ring := _split_edges(points, boundary_vertices)
		if (points[2] - points[0]).cross(points[1] - points[0]).dot(value["normal"]) < 0:
			ring.reverse()
		var center := Vector3.ZERO
		for point: Vector3 in points:
			center += point / points.size()
		var middle := _index(center.snapped(Vector3.ONE * SNAP), vertices, lookup)
		var ids: Array[int] = []
		for point: Vector3 in ring:
			ids.append(_index(point, vertices, lookup))
		for index: int in ids.size():
			var triangle := PackedInt32Array([middle, ids[index], ids[(index + 1) % ids.size()]])
			var ordered: Array[int] = [triangle[0], triangle[1], triangle[2]]
			ordered.sort()
			var key := str(ordered)
			if seen.has(key):
				continue
			seen[key] = true
			if value["visible"]:
				var group: String = value["material"]
				if not groups.has(group):
					groups[group] = PackedInt32Array()
				groups[group].append_array(triangle)
			if value["solid"]:
				for vertex: int in triangle:
					collision.append(vertices[vertex])
	for group: String in groups:
		_surface(structure, group, vertices, groups[group])
	var body := StaticBody3D.new()
	body.name = "ShellCollision"
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision)
	collider.shape = shape
	body.add_child(collider)
	structure.add_child(body)
	structure.set_meta("vertex_pool", vertices)
	structure.set_meta("groups", groups)
	structure.set_meta("face_count", faces.size())


static func _index(
	point: Vector3, vertices: PackedVector3Array, lookup: Dictionary[Vector3, int]
) -> int:
	if not lookup.has(point):
		lookup[point] = vertices.size()
		vertices.append(point)
	return lookup[point]


static func _split_edges(
	points: PackedVector3Array, pool: PackedVector3Array
) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for index: int in points.size():
		var start := points[index]
		var end := points[(index + 1) % points.size()]
		var edge := end - start
		var hits: Array[Vector3] = [start]
		for point: Vector3 in pool:
			var t := (point - start).dot(edge) / edge.length_squared()
			if t > SNAP and t < 1.0 - SNAP and (start + edge * t).distance_to(point) < SNAP:
				hits.append(point)
		hits.sort_custom(
			func(a: Vector3, b: Vector3) -> bool:
				return start.distance_squared_to(a) < start.distance_squared_to(b)
		)
		ring.append_array(PackedVector3Array(hits))
	return ring


static func _surface(
	root: Node3D, group: String, vertices: PackedVector3Array, indices: PackedInt32Array
) -> void:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for index: int in range(0, indices.size(), 3):
		var a := vertices[indices[index]]
		var b := vertices[indices[index + 1]]
		var c := vertices[indices[index + 2]]
		var normal := (c - a).cross(b - a).normalized()
		for offset: int in 3:
			normals[indices[index + offset]] += normal
	for index: int in normals.size():
		normals[index] = normals[index].normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = group.capitalize()
	node.mesh = mesh
	node.material_override = {"floor": FLOOR, "wall": WALL, "grey": GREY, "roof": ROOF}[group]
	root.add_child(node)
	if group == "roof":
		node.add_to_group(&"lab_roofs")
