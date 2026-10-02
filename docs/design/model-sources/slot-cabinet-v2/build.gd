extends SceneTree
## Authoritative indexed cabinet, recessed hardware and moving lever geometry.

const OUTPUT := "res://assets/slot_machine/cabinet_v2/"
const CHARTS := {
	"wood": Rect2(2, 2, 54, 60),
	"metal": Rect2(60, 2, 28, 60),
	"enamel": Rect2(92, 2, 34, 60),
	"marquee": Rect2(2, 66, 64, 16),
	"paytable": Rect2(2, 86, 64, 24),
	"dark": Rect2(70, 66, 24, 44),
	"hardware": Rect2(98, 66, 28, 44),
	"knob": Rect2(2, 114, 64, 12),
}
var _tool: SurfaceTool
var _triangles := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_start()
	# Side panels follow one continuous stepped cabinet silhouette.
	var outline := PackedVector2Array(
		[
			Vector2(-.56, .24),
			Vector2(.49, .24),
			Vector2(.56, 1.18),
			Vector2(.48, 1.30),
			Vector2(.48, 2.16),
			Vector2(.52, 2.26),
			Vector2(.49, 2.71),
			Vector2(.40, 2.77),
			Vector2(-.56, 2.77)
		]
	)
	for x: float in [-1.06, .99]:
		_side(outline, x, x + .07)
	_box(Vector3(0, 1.5, -.535), Vector3(1.98, 2.5, .05), "wood")
	_box(Vector3(0, .15, -.025), Vector3(2.16, .30, 1.17), "enamel")
	_box(Vector3(0, 2.745, -.005), Vector3(2.16, .09, 1.13), "metal")
	_box(Vector3(0, 2.45, .46), Vector3(1.98, .50, .08), "marquee")
	_frame(Rect2(-1.0, 2.19, 2.0, .51), Rect2(-.92, 2.28, 1.84, .35), .56, .50, "metal")
	_box(Vector3(0, 2.45, .53), Vector3(1.84, .35, .03), "marquee")
	# A recessed backing and open bezel keep the animated drum surfaces unobstructed.
	_box(Vector3(0, 1.73, .15), Vector3(1.96, .95, .06), "dark")
	_frame(Rect2(-1.0, 1.22, 2.0, 1.0), Rect2(-.88, 1.32, 1.76, .83), .665, .48, "metal")
	for x: float in [-.29, .29]:
		_box(Vector3(x, 1.735, .54), Vector3(.045, .83, .21), "metal")
	_box(Vector3(0, 1.165, .505), Vector3(2.0, .11, .18), "enamel")
	_box(Vector3(0, .725, .465), Vector3(1.98, .78, .07), "wood")
	_frame(Rect2(-.85, .84, 1.34, .21), Rect2(-.79, .88, 1.22, .13), .552, .503, "metal")
	_box(Vector3(-.18, .945, .512), Vector3(1.22, .13, .012), "dark")
	_box(Vector3(0, .66, .503), Vector3(1.73, .26, .016), "paytable")
	# A real coin throat: rim and inward walls around a dark recessed aperture.
	_frame(Rect2(.62, .82, .21, .28), Rect2(.695, .88, .045, .16), .585, .555, "hardware")
	_box(Vector3(.7175, .96, .548), Vector3(.045, .16, .01), "dark")
	# Payout chute and folded metal tray meet the lower front, not floating plates.
	_frame(Rect2(-.71, .31, 1.42, .21), Rect2(-.63, .35, 1.26, .13), .555, .485, "metal")
	_box(Vector3(0, .415, .52), Vector3(1.26, .13, .01), "dark")
	_box(Vector3(0, .285, .66), Vector3(1.44, .05, .40), "metal")
	_box(Vector3(0, .345, .845), Vector3(1.44, .12, .035), "metal")
	for x: float in [-.70, .70]:
		_box(Vector3(x, .345, .665), Vector3(.035, .12, .36), "metal")
	# Fixed socket runs through the right wall to the moving lever's pivot.
	_profile(
		Vector3(1.055, 1.23, 0),
		[Vector2(0, .105), Vector2(.06, .105), Vector2(.085, .06)],
		"metal",
		true
	)
	_save("cabinet.res")
	_start()
	# Shaft and faceted bakelite knob share one continuous profile and UV atlas.
	_profile(
		Vector3.ZERO,
		[Vector2(0, .045), Vector2(.045, .052), Vector2(.53, .032), Vector2(.56, .032)],
		"metal"
	)
	_profile(
		Vector3.ZERO,
		[
			Vector2(.55, .04),
			Vector2(.59, .095),
			Vector2(.67, .115),
			Vector2(.75, .075),
			Vector2(.77, .025)
		],
		"knob"
	)
	_save("lever.res")
	quit()


func _start() -> void:
	_tool = SurfaceTool.new()
	_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangles = 0


func _uv(material: String, value: Vector2) -> Vector2:
	var chart: Rect2 = CHARTS[material]
	return (chart.position + Vector2(.5, .5) + value * (chart.size - Vector2.ONE)) / 128.0


func _triangle(
	points: Array[Vector3], uvs: Array[Vector2], outward: Vector3, material: String
) -> void:
	if (points[2] - points[0]).cross(points[1] - points[0]).dot(outward) < 0:
		points.reverse()
		uvs.reverse()
	var normal := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	assert(normal.is_finite() and normal.length() > .99)
	for index: int in 3:
		_tool.set_normal(normal)
		_tool.set_uv(_uv(material, uvs[index]))
		_tool.add_vertex(points[index])
	_triangles += 1


func _quad(points: Array[Vector3], outward: Vector3, material: String) -> void:
	_triangle(
		[points[0], points[1], points[2]],
		[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE],
		outward,
		material
	)
	_triangle(
		[points[0], points[2], points[3]],
		[Vector2.ZERO, Vector2.ONE, Vector2.DOWN],
		outward,
		material
	)


func _box(center: Vector3, size: Vector3, material: String) -> void:
	var corners: Array[Vector3] = []
	for value: Vector3 in [
		Vector3(-1, -1, -1),
		Vector3(1, -1, -1),
		Vector3(1, 1, -1),
		Vector3(-1, 1, -1),
		Vector3(-1, -1, 1),
		Vector3(1, -1, 1),
		Vector3(1, 1, 1),
		Vector3(-1, 1, 1)
	]:
		corners.append(center + value * size * .5)
	for face: Array in [
		[0, 1, 2, 3], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [0, 1, 5, 4], [3, 7, 6, 2]
	]:
		var points: Array[Vector3] = []
		for index: int in face:
			points.append(corners[index])
		_quad(points, (points[0] + points[2]) * .5 - center, material)


func _ring(rect: Rect2, z: float) -> Array[Vector3]:
	return [
		Vector3(rect.position.x, rect.position.y, z),
		Vector3(rect.end.x, rect.position.y, z),
		Vector3(rect.end.x, rect.end.y, z),
		Vector3(rect.position.x, rect.end.y, z)
	]


func _frame(outer: Rect2, inner: Rect2, front: float, back: float, material: String) -> void:
	var a := _ring(outer, front - .018)
	var b := _ring(inner, front)
	var c := _ring(outer, back)
	var d := _ring(inner, back)
	var middle := Vector3(outer.get_center().x, outer.get_center().y, front)
	for index: int in 4:
		var next := (index + 1) % 4
		_quad([a[index], a[next], b[next], b[index]], Vector3.BACK, material)
		_quad([a[index], c[index], c[next], a[next]], (a[index] + a[next]) * .5 - middle, material)
		_quad([b[index], b[next], d[next], d[index]], middle - (b[index] + b[next]) * .5, material)
		_quad([c[index], d[index], d[next], c[next]], Vector3.FORWARD, material)


func _side(outline: PackedVector2Array, left: float, right: float) -> void:
	var indices := Geometry2D.triangulate_polygon(outline)
	for x: float in [left, right]:
		for index: int in range(0, indices.size(), 3):
			var points: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for offset: int in 3:
				var p := outline[indices[index + offset]]
				points.append(Vector3(x, p.y, p.x))
				uvs.append(Vector2((p.x + .56) / 1.12, (p.y - .24) / 2.53))
			_triangle(points, uvs, Vector3.LEFT if x == left else Vector3.RIGHT, "wood")
	for index: int in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		_quad(
			[
				Vector3(left, a.y, a.x),
				Vector3(right, a.y, a.x),
				Vector3(right, b.y, b.x),
				Vector3(left, b.y, b.x)
			],
			Vector3(0, a.x - b.x, b.y - a.y),
			"wood"
		)


func _profile(center: Vector3, rings: Array, material: String, along_x: bool = false) -> void:
	for row: int in range(rings.size() - 1):
		for side: int in 8:
			var points: Array[Vector3] = []
			for pair: Vector2i in [
				Vector2i(row, side),
				Vector2i(row, side + 1),
				Vector2i(row + 1, side + 1),
				Vector2i(row + 1, side)
			]:
				var ring: Vector2 = rings[pair.x]
				var angle := TAU * pair.y / 8.0
				var point := Vector3(cos(angle) * ring.y, ring.x, sin(angle) * ring.y)
				if along_x:
					point = Vector3(point.y, point.x, point.z)
				points.append(center + point)
			var outward := (points[0] + points[2]) * .5 - center
			outward.x = 0 if along_x else outward.x
			outward.y = outward.y if along_x else 0
			_quad(points, outward, material)
	for end: int in [0, rings.size() - 1]:
		var ring: Vector2 = rings[end]
		for side: int in 8:
			var normal := Vector3.DOWN if end == 0 else Vector3.UP
			var points: Array[Vector3] = [Vector3(0, ring.x, 0)]
			for angle: float in [TAU * side / 8.0, TAU * (side + 1) / 8.0]:
				points.append(Vector3(cos(angle) * ring.y, ring.x, sin(angle) * ring.y))
			if along_x:
				normal = Vector3(normal.y, 0, 0)
				for index: int in 3:
					points[index] = Vector3(points[index].y, points[index].x, points[index].z)
			for index: int in 3:
				points[index] += center
			_triangle(points, [Vector2(.5, .5), Vector2(.2, .2), Vector2(.8, .2)], normal, material)


func _save(file: String) -> void:
	_tool.index()
	var mesh := _tool.commit()
	assert(ResourceSaver.save(mesh, OUTPUT + file) == OK)
	print("SLOT_EXPORT: ", file, " triangles=", _triangles, " bounds=", mesh.get_aabb())
