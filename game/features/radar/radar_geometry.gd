class_name RadarGeometry
extends RefCounted
## A horizontal slice of the baked CSG, so roofs never obscure indoor passages.

var walls := PackedVector2Array()
var floors := PackedVector2Array()


func append_mesh(mesh: Mesh, transform: Transform3D, height: float) -> void:
	var faces := mesh.get_faces()
	for index: int in range(0, faces.size(), 3):
		var a := transform * faces[index]
		var b := transform * faces[index + 1]
		var c := transform * faces[index + 2]
		# Godot triangles wind clockwise. Keep upward surfaces near this storey.
		var normal := (c - a).cross(b - a).normalized()
		var top := maxf(a.y, maxf(b.y, c.y))
		var bottom := minf(a.y, minf(b.y, c.y))
		if normal.y > 0.5 and top < height and bottom > height - 4.0:
			floors.append(Vector2(a.x, a.z))
			floors.append(Vector2(b.x, b.z))
			floors.append(Vector2(c.x, c.z))
		if bottom >= height or top <= height:
			continue
		var crossings := PackedVector2Array()
		_edge(a, b, height, crossings)
		_edge(b, c, height, crossings)
		_edge(c, a, height, crossings)
		if crossings.size() == 2:
			walls.append_array(crossings)


static func _edge(a: Vector3, b: Vector3, height: float, points: PackedVector2Array) -> void:
	if (a.y <= height and b.y > height) or (b.y <= height and a.y > height):
		var point := a.lerp(b, (height - a.y) / (b.y - a.y))
		points.append(Vector2(point.x, point.z))


func floor_mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	if floors.is_empty():
		return result
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = floors
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
