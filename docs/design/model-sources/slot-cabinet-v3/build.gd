extends SceneTree
## Upright casino cabinet. Geometry follows the retained three-view reference.

const OUTPUT := "res://assets/slot_machine/cabinet_v3/"
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
var _transform := Transform3D.IDENTITY
var _tool: SurfaceTool
var _triangles := 0


func _initialize() -> void:
	_start()
	# A narrow metal housing: top box, raked reel face, projecting deck and belly.
	var side := PackedVector2Array(
		[
			Vector2(-.50, .10),
			Vector2(.47, .10),
			Vector2(.50, .40),
			Vector2(.47, 1.03),
			Vector2(.73, 1.22),
			Vector2(.73, 1.34),
			Vector2(.48, 1.52),
			Vector2(.30, 2.03),
			Vector2(.30, 2.69),
			Vector2(.22, 2.77),
			Vector2(-.50, 2.77)
		]
	)
	_side(side, -.66, -.60)
	_side(side, .60, .66)
	_box(Vector3(0, 1.43, -.475), Vector3(1.2, 2.65, .05), "dark")
	_bevel_box(Vector3(0, .07, 0), Vector3(1.38, .14, 1.06), .04, "dark")
	_bevel_box(Vector3(0, 2.40, -.11), Vector3(1.32, .76, .82), .07, "dark")
	_frame(Rect2(-.66, 2.015, 1.32, .755), Rect2(-.60, 2.07, 1.20, .635), .343, .28, "metal")
	# Recessed, raked glass/reel assembly; transform the surround as a single unit.
	var before := _transform
	_transform = Transform3D(Basis(Vector3.RIGHT, -.30), Vector3(0, 1.735, .40))
	_frame(Rect2(-.66, -.31, 1.32, .62), Rect2(-.605, -.26, 1.21, .52), 0, -.06, "metal")
	_box(Vector3(0, 0, -.24), Vector3(1.21, .53, .06), "dark")
	# Three compact rectangular windows within a black front fascia.
	for x: float in [-.36, 0, .36]:
		_frame(
			Rect2(x - .164, -.21, .328, .42),
			Rect2(x - .145, -.19, .29, .38),
			.008,
			-.02,
			"hardware"
		)
	_transform = before
	# Sloped control deck, joined to the raked face and lower cabinet.
	_transform = Transform3D(Basis(Vector3.RIGHT, -.58), Vector3(0, 1.345, .615))
	_bevel_box(Vector3.ZERO, Vector3(1.32, .24, .11), .035, "metal")
	_box(Vector3(0, 0, .057), Vector3(1.21, .16, .008), "dark")
	for i: int in 5:
		var x := -.48 + i * .23
		_bevel_box(Vector3(x, 0, .078), Vector3(.15, .11, .043), .012, "metal")
	_transform = before
	_bevel_box(Vector3(0, 1.185, .642), Vector3(1.33, .14, .19), .025, "metal")
	_box(Vector3(0, 1.19, .742), Vector3(1.20, .076, .016), "dark")
	# Belly lightbox and separate cast coin tray underneath.
	_box(Vector3(0, .88, .435), Vector3(1.22, .5, .09), "dark")
	_frame(Rect2(-.65, .61, 1.30, .55), Rect2(-.60, .66, 1.20, .45), .52, .46, "metal")
	_frame(Rect2(-.64, .34, 1.28, .245), Rect2(-.585, .395, 1.17, .135), .61, .44, "metal")
	_box(Vector3(0, .46, .438), Vector3(1.17, .135, .015), "dark")
	_box(Vector3(0, .34, .57), Vector3(1.25, .035, .35), "metal")
	_bevel_box(Vector3(0, .375, .74), Vector3(1.28, .105, .045), .025, "metal")
	for x: float in [-.62, .62]:
		_box(Vector3(x, .40, .60), Vector3(.035, .14, .28), "metal")
	_frame(Rect2(-.63, .12, 1.26, .18), Rect2(-.60, .135, 1.20, .15), .50, .47, "dark")
	# Bill validator on the right of the deck front, inset and properly framed.
	_frame(Rect2(.34, 1.145, .25, .105), Rect2(.365, 1.17, .20, .04), .766, .744, "metal")
	_box(Vector3(.465, 1.19, .743), Vector3(.20, .04, .006), "dark")
	# Lever hinge, rear access seam and vents.
	_profile(
		Vector3(.655, 1.48, .18),
		[Vector2(0, .082), Vector2(.09, .082), Vector2(.105, .05)],
		"metal",
		true
	)
	_box(Vector3(0, 1.45, -.507), Vector3(1.06, 2.28, .012), "enamel")
	for y: float in [.65, .72, .79, 2.3, 2.37, 2.44]:
		_box(Vector3(0, y, -.516), Vector3(.72, .018, .006), "dark")
	for y: float in [.58, 1.93]:
		_box(Vector3(-.54, y, -.519), Vector3(.035, .11, .035), "metal")
	_profile(Vector3(.51, .21, .50), [Vector2(0, .028), Vector2(.014, .028)], "metal", false, true)
	_box(Vector3(.51, .21, .518), Vector3(.004, .018, .004), "dark")
	# Beacon is a two-tier cylinder, with real hardware between both lenses.
	for y: float in [2.77, 2.87, 2.985]:
		_profile(Vector3(0, y, -.10), [Vector2(0, .075), Vector2(.018, .075)], "metal")
	_save("cabinet.res")
	# Exact, padded UV chart for the two luminous artwork panels.
	var guide := Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	guide.fill(Color("282422"))
	guide.fill_rect(Rect2i(16, 16, 992, 576), Color("79171b"))
	guide.fill_rect(Rect2i(16, 624, 992, 384), Color("571419"))
	guide.save_png("../docs/design/model-sources/slot-cabinet-v3/glass-uv-template.png")
	quit()


func _start() -> void:
	_tool = SurfaceTool.new()
	_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangles = 0


func _uv(material: String, value: Vector2) -> Vector2:
	var chart: Rect2 = CHARTS[material]
	if material == "metal":
		value.x = .38 + value.x * .24
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
		_tool.set_normal(_transform.basis * normal)
		_tool.set_uv(_uv(material, uvs[index]))
		_tool.add_vertex(_transform * points[index])
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
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var r := minf(.08, minf(h * .18, w * .12))
	return [
		Vector3(x + r, y, z),
		Vector3(x + w - r, y, z),
		Vector3(x + w, y + r, z),
		Vector3(x + w, y + h - r, z),
		Vector3(x + w - r, y + h, z),
		Vector3(x + r, y + h, z),
		Vector3(x, y + h - r, z),
		Vector3(x, y + r, z)
	]


func _frame(outer: Rect2, inner: Rect2, front: float, back: float, material: String) -> void:
	var a := _ring(outer, front - .018)
	var b := _ring(inner, front)
	var c := _ring(outer, back)
	var d := _ring(inner, back)
	var middle := Vector3(outer.get_center().x, outer.get_center().y, front)
	for index: int in 8:
		var next := (index + 1) % 8
		_quad([a[index], a[next], b[next], b[index]], Vector3.BACK, material)
		_quad([a[index], c[index], c[next], a[next]], (a[index] + a[next]) * .5 - middle, material)
		_quad([b[index], b[next], d[next], d[index]], middle - (b[index] + b[next]) * .5, material)
		_quad([c[index], d[index], d[next], c[next]], Vector3.FORWARD, material)


func _side(outline: PackedVector2Array, left: float, right: float, finish: String = "dark") -> void:
	var indices := Geometry2D.triangulate_polygon(outline)
	for x: float in [left, right]:
		for index: int in range(0, indices.size(), 3):
			var points: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for offset: int in 3:
				var p := outline[indices[index + offset]]
				points.append(Vector3(x, p.y, p.x))
				uvs.append(Vector2((p.x + .56) / 1.12, (p.y - .24) / 2.53))
			_triangle(points, uvs, Vector3.LEFT if x == left else Vector3.RIGHT, finish)
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
			finish
		)


func _profile(
	center: Vector3, rings: Array, material: String, along_x: bool = false, along_z: bool = false
) -> void:
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
				if along_z:
					point = Vector3(point.x, point.z, point.y)
				points.append(center + point)
			var outward := (points[0] + points[2]) * .5 - center
			outward.x = 0 if along_x else outward.x
			outward.y = outward.y if along_x or along_z else 0
			if along_z:
				outward.z = 0
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
			if along_z:
				normal = Vector3(normal.x, 0, normal.y)
				for index: int in 3:
					points[index] = Vector3(points[index].x, points[index].z, points[index].y)
			for index: int in 3:
				points[index] += center
			_triangle(points, [Vector2(.5, .5), Vector2(.2, .2), Vector2(.8, .2)], normal, material)


func _save(file: String) -> void:
	_tool.index()
	var mesh := _tool.commit()
	assert(ResourceSaver.save(mesh, OUTPUT + file) == OK)
	print("SLOT_EXPORT: ", file, " triangles=", _triangles, " bounds=", mesh.get_aabb())


func _bevel_box(center: Vector3, size: Vector3, bevel: float, material: String) -> void:
	var x := size.x * .5
	var y := size.y * .5
	var outline: Array[Vector2] = [
		Vector2(-x + bevel, -y),
		Vector2(x - bevel, -y),
		Vector2(x, -y + bevel),
		Vector2(x, y - bevel),
		Vector2(x - bevel, y),
		Vector2(-x + bevel, y),
		Vector2(-x, y - bevel),
		Vector2(-x, -y + bevel)
	]
	for i: int in 8:
		var a := outline[i]
		var b := outline[(i + 1) % 8]
		var front_a := center + Vector3(a.x, a.y, size.z * .5)
		var front_b := center + Vector3(b.x, b.y, size.z * .5)
		var back_a := front_a - Vector3(0, 0, size.z)
		var back_b := front_b - Vector3(0, 0, size.z)
		_quad([front_a, front_b, back_b, back_a], Vector3(a.x + b.x, a.y + b.y, 0), material)
		_triangle(
			[center + Vector3(0, 0, size.z * .5), front_a, front_b],
			[Vector2(.5, .5), (a / size.x) + Vector2(.5, .5), (b / size.x) + Vector2(.5, .5)],
			Vector3.BACK,
			material
		)
		_triangle(
			[center - Vector3(0, 0, size.z * .5), back_a, back_b],
			[Vector2(.5, .5), Vector2.ZERO, Vector2.ONE],
			Vector3.FORWARD,
			material
		)
