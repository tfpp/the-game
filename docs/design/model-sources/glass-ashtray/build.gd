extends SceneTree
## Closed eight-sided glass bowl, with open interior and a thick continuous rim.

var _tool: SurfaceTool


func _initialize() -> void:
	_tool = SurfaceTool.new()
	_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[Vector2] = [
		Vector2(.065, 0), Vector2(.075, .026), Vector2(.057, .026), Vector2(.045, .006)
	]
	var charts: Array[Rect2] = [Rect2(2, 2, 28, 10), Rect2(16, 26, 14, 4), Rect2(2, 16, 28, 6)]
	for band: int in 3:
		for side: int in 8:
			var a := TAU * side / 8.0
			var b := TAU * (side + 1) / 8.0
			var p: Array[Vector3] = [
				_point(rings[band], a),
				_point(rings[band], b),
				_point(rings[band + 1], b),
				_point(rings[band + 1], a)
			]
			var chart := charts[band]
			var left := (chart.position.x + .5 + (chart.size.x - 1) * side / 8.0) / 32
			var right := (chart.position.x + .5 + (chart.size.x - 1) * (side + 1) / 8.0) / 32
			var low := (chart.position.y + .5) / 32
			var high := (chart.end.y - .5) / 32
			var uv: Array[Vector2] = [
				Vector2(left, low), Vector2(right, low), Vector2(right, high), Vector2(left, high)
			]
			var normal := (
				Vector3.UP
				if band == 1
				else Vector3(cos((a + b) / 2), 0, sin((a + b) / 2)) * (-1 if band == 2 else 1)
			)
			_triangle([p[0], p[1], p[2]], [uv[0], uv[1], uv[2]], normal)
			_triangle([p[0], p[2], p[3]], [uv[0], uv[2], uv[3]], normal)
	for floor_index: int in [0, 3]:
		for side: int in 8:
			var ring := rings[floor_index]
			var normal := Vector3.DOWN if floor_index == 0 else Vector3.UP
			_triangle(
				[
					Vector3(0, ring.y, 0),
					_point(ring, TAU * side / 8.0),
					_point(ring, TAU * (side + 1) / 8.0)
				],
				[Vector2(.22, .88), Vector2(.12, .84), Vector2(.32, .90)],
				normal
			)
	_tool.index()
	var mesh := _tool.commit()
	assert(mesh.get_faces().size() == 64 * 3)
	assert(mesh.get_aabb().size.is_equal_approx(Vector3(.15, .026, .15)))
	assert(
		ResourceSaver.save(mesh, "res://assets/casino_props/glass_ashtray/glass_ashtray.res") == OK
	)
	quit()


func _point(ring: Vector2, angle: float) -> Vector3:
	return Vector3(cos(angle) * ring.x, ring.y, sin(angle) * ring.x)


func _triangle(points: Array[Vector3], uvs: Array[Vector2], expected: Vector3) -> void:
	var normal := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	if normal.dot(expected) < 0:
		points.reverse()
		uvs.reverse()
		normal = -normal
	for index: int in 3:
		_tool.set_normal(normal)
		_tool.set_uv(uvs[index])
		_tool.add_vertex(points[index])
