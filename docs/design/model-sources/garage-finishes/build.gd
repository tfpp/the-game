extends SceneTree
## Mesh-first shutter, window frame and open cleaning cupboard; one 128px atlas.
const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const OUT := "res://assets/starter_room/"
const AUTHOR := "res://../docs/design/model-sources/garage-finishes/"
const CHARTS: Array[Rect2i] = [
	Rect2i(4, 4, 90, 72),
	Rect2i(100, 4, 24, 68),
	Rect2i(4, 82, 54, 42),
	Rect2i(64, 82, 34, 24),
	Rect2i(104, 82, 20, 22),
	Rect2i(64, 112, 14, 12),
	Rect2i(84, 112, 14, 12)
]
const NAMES: Array[String] = ["shutter", "window_frame", "broom_cupboard"]
var _parts: Array[Array] = [[], [], []]


func _initialize() -> void:
	_shutter()
	_window()
	_cupboard()
	for i: int in NAMES.size():
		_save(i, "garage_" + NAMES[i] + ".res")
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	image.fill(Color("454b4e"))
	for i: int in CHARTS.size():
		image.fill_rect(CHARTS[i], Color("a6afa8") if i % 2 == 0 else Color("7c8d94"))
	image.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	image.save_png(AUTHOR + "uv-template.png")
	if not OS.get_cmdline_user_args().is_empty():
		image = Image.load_from_file(OS.get_cmdline_user_args()[0])
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		var source := image.duplicate() as Image
		for chart: Rect2i in CHARTS:
			for y: int in range(chart.position.y - 2, chart.end.y + 2):
				for x: int in range(chart.position.x - 2, chart.end.x + 2):
					image.set_pixel(
						x,
						y,
						source.get_pixel(
							clampi(x, chart.position.x, chart.end.x - 1),
							clampi(y, chart.position.y, chart.end.y - 1)
						)
					)
		image.save_png(OUT + "garage_finishes.png")
	quit()


func _shutter() -> void:
	var profile: Array[Vector2] = [Vector2(-.05, 0), Vector2(.055, 0)]
	for i: int in 20:
		var y := float(i) * .16
		profile.append_array(
			[Vector2(.085, y + .035), Vector2(.085, y + .125), Vector2(.055, y + .16)]
		)
	profile.append(Vector2(-.05, 3.2))
	var faces: Array[Dictionary] = []
	PROP.add_prism(faces, "SHUTTER", profile, 2.25)
	for face: Dictionary in faces:
		var poly: Array[Dictionary] = []
		for point: Vector3 in face["points"]:
			poly.append(
				{
					"p": point,
					"n": face["normal"],
					"uv": _uv(0, Vector2((point.x + 2.25) / 4.5, 1 - point.y / 3.2))
				}
			)
		_parts[0].append(poly)
	for x: float in [-2.35, 2.35]:
		_box(0, Vector3(x, 1.64, -.015), Vector3(.2, 3.28, .23), 1)
		_box(0, Vector3(x, 1.64, .115), Vector3(.13, 3.28, .035), 3)
	_box(0, Vector3(0, 3.38, -.01), Vector3(4.95, .3, .32), 1)
	_box(0, Vector3(0, .035, .085), Vector3(4.5, .07, .07), 4)
	# A continuous U pull has hand clearance and ends anchored in the panel skin.
	for x: float in [-.32, .32]:
		_box(0, Vector3(x, .55, .13), Vector3(.055, .055, .14), 1)
	_box(0, Vector3(0, .55, .2), Vector3(.695, .055, .055), 1)
	_box(0, Vector3(.55, .85, .09), Vector3(.16, .2, .025), 4)
	_box(0, Vector3(0, 3.56, -.01), Vector3(4.8, .055, .35), 3)


func _window() -> void:
	for x: float in [-1.52, 1.52]:
		_box(1, Vector3(x, 2.25, 0), Vector3(.1, 2.15, .18), 1)
	for y: float in [1.23, 3.27]:
		_box(1, Vector3(0, y, 0), Vector3(3.14, .1, .18), 1)
	_box(1, Vector3(0, 1.17, .08), Vector3(3.24, .1, .38), 3)
	_box(1, Vector3(0, 2.25, .045), Vector3(.045, 1.99, .065), 1)
	_box(1, Vector3(0, 2.3, .045), Vector3(2.95, .045, .065), 1)
	# Depth returns join the real 200mm wall cutout.
	for x: float in [-1.485, 1.485]:
		_box(1, Vector3(x, 2.25, -.06), Vector3(.04, 1.97, .2), 3)


func _cupboard() -> void:
	_box(2, Vector3(0, 1.15, -.28), Vector3(1.3, 2.3, .055), 3)
	for x: float in [-.62, .62]:
		_box(2, Vector3(x, 1.15, 0), Vector3(.06, 2.3, .6), 2)
	for y: float in [.03, 2.27]:
		_box(2, Vector3(0, y, 0), Vector3(1.3, .06, .6), 2)
	_box(2, Vector3(0, 1.15, 0), Vector3(.045, 2.24, .55), 3)
	_box(2, Vector3(0, 1.98, 0), Vector3(1.18, .04, .55), 3)
	# Right leaf closed; left leaf ajar, with the same physical hinge geometry.
	_box(2, Vector3(.315, 1.15, .315), Vector3(.57, 2.18, .055), 2)
	_box(2, Vector3(.075, 1.15, .37), Vector3(.035, .16, .055), 1)
	var basis := Basis(Vector3.UP, -1.05)
	var hinge := Vector3(-.6, 0, .315)
	_box(2, hinge + basis * Vector3(.285, 1.15, 0), Vector3(.57, 2.18, .055), 2, basis)
	_box(2, hinge + basis * Vector3(.51, 1.15, .05), Vector3(.035, .16, .055), 1, basis)
	for y: float in [.28, 1.95]:
		_box(2, Vector3(-.6, y, .315), Vector3(.08, .12, .09), 1)
	# Broom head rests on the base; handle meets the head, with a restrained lean.
	_box(2, Vector3(-.34, .14, -.12), Vector3(.34, .13, .12), 6)
	_box(2, Vector3(-.34, .235, -.12), Vector3(.35, .06, .13), 5)
	var start := Vector3(-.34, .25, -.12)
	var end := Vector3(-.38, 1.89, -.18)
	_cylinder(2, start, .018, start.distance_to(end), (end - start).normalized(), 5)
	# Open bucket, tapered wall and connected bail, tucked beside a small mop.
	_bucket(Vector3(-.22, .06, .1))
	_cylinder(2, Vector3(-.08, .2, -.18), .014, 1.67, Vector3.UP, 5)
	_box(2, Vector3(-.08, .125, -.18), Vector3(.12, .13, .09), 3)
	# Cleaning bottles stand on the upper shelf rather than float over it.
	for x: float in [-.38, -.12, .29]:
		_box(2, Vector3(x, 2.09, -.04), Vector3(.12, .18, .13), 2)
		_box(2, Vector3(x, 2.195, -.04), Vector3(.05, .035, .05), 1)


func _bucket(at: Vector3) -> void:
	var faces: Array[Dictionary] = []
	for i: int in 8:
		var a := float(i) * TAU / 8
		var b := float(i + 1) * TAU / 8
		var bottom_a := Vector3(cos(a) * .11, 0, sin(a) * .11)
		var bottom_b := Vector3(cos(b) * .11, 0, sin(b) * .11)
		var top_a := Vector3(cos(a) * .145, .26, sin(a) * .145)
		var top_b := Vector3(cos(b) * .145, .26, sin(b) * .145)
		var polygons: Array[PackedVector3Array] = [
			PackedVector3Array([bottom_b, bottom_a, top_a, top_b]),
			PackedVector3Array([top_b * .9, top_a * .9, bottom_a * .9, bottom_b * .9]),
			PackedVector3Array([top_b, top_a, top_a * .9, top_b * .9])
		]
		for points: PackedVector3Array in polygons:
			var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
			faces.append({"points": Transform3D(Basis.IDENTITY, at) * points, "normal": normal})
	_append(faces, 2, 3)
	_cylinder(2, at, .11, .015, Vector3.UP, 3)
	for x: float in [-.145, .145]:
		_beam(2, at + Vector3(x, .21, 0), at + Vector3(x, .41, 0), .015, 1)
	_box(2, at + Vector3(0, .41, 0), Vector3(.305, .02, .02), 1)


func _uv(chart: int, relative: Vector2) -> Vector2:
	var rect := CHARTS[chart]
	return (
		(Vector2(rect.position) + Vector2(.5, .5) + relative * Vector2(rect.size - Vector2i.ONE))
		/ 128
	)


func _beam(part: int, start: Vector3, end: Vector3, width: float, chart: int) -> void:
	var direction := (end - start).normalized()
	_box(
		part,
		(start + end) / 2,
		Vector3(width, start.distance_to(end), width),
		chart,
		Basis(Quaternion(Vector3.UP, direction))
	)


func _cylinder(
	part: int, at: Vector3, radius: float, length: float, direction: Vector3, chart: int
) -> void:
	var faces: Array[Dictionary] = []
	PROP.add_cylinder(faces, "WORKSHOP", radius, length)
	var transform := Transform3D(Basis(Quaternion(Vector3.UP, direction)), at)
	for face: Dictionary in faces:
		face["points"] = transform * (face["points"] as PackedVector3Array)
		face["normal"] = transform.basis * (face["normal"] as Vector3)
	_append(faces, part, chart)


func _append(faces: Array[Dictionary], part: int, chart: int) -> void:
	for face: Dictionary in faces:
		var poly: Array[Dictionary] = []
		var points: PackedVector3Array = face["points"]
		var rect := CHARTS[chart]
		for i: int in points.size():
			var relative := Vector2(float(i % 2), float(i / 2 % 2))
			poly.append(
				{
					"p": points[i],
					"n": face["normal"],
					"uv":
					(
						(
							Vector2(rect.position)
							+ Vector2(.5, .5)
							+ relative * Vector2(rect.size - Vector2i.ONE)
						)
						/ 128
					)
				}
			)
		_parts[part].append(poly)


func _box(
	part: int, center: Vector3, size: Vector3, chart: int, basis: Basis = Basis.IDENTITY
) -> void:
	var faces: Array[Dictionary] = []
	PROP.add_prism(
		faces,
		"WORKSHOP",
		[
			Vector2(-size.z / 2, -size.y / 2),
			Vector2(size.z / 2, -size.y / 2),
			Vector2(size.z / 2, size.y / 2),
			Vector2(-size.z / 2, size.y / 2)
		],
		size.x / 2
	)
	for face: Dictionary in faces:
		var poly: Array[Dictionary] = []
		var rect := CHARTS[chart]
		var source: PackedVector3Array = face["points"]
		var projected: PackedVector2Array = face["uv_m"]
		for i: int in source.size():
			var relative := projected[i] / (face["size_m"] as Vector2)
			# Long post faces use top-to-bottom chart orientation.
			if chart == 1:
				var normal: Vector3 = face["normal"]
				var horizontal := (source[i].x + size.x / 2) / size.x
				if absf(normal.x) > .99:
					horizontal = (source[i].z + size.z / 2) / size.z
				relative = Vector2(horizontal, clampf((size.y / 2 - source[i].y) / size.y, 0, 1))
			if chart == -1 and (face["normal"] as Vector3).z > .99:
				relative = Vector2(
					(source[i].x + size.x / 2) / size.x, (size.y / 2 - source[i].y) / size.y
				)
			var uv := (
				(
					Vector2(rect.position)
					+ Vector2(.5, .5)
					+ relative * Vector2(rect.size - Vector2i.ONE)
				)
				/ 128
			)
			poly.append(
				{
					"p": basis * source[i] + center,
					"n": basis * (face["normal"] as Vector3),
					"uv": uv
				}
			)
		_parts[part].append(poly)


func _save(part: int, filename: String) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var shared: Dictionary[Array, int] = {}
	for poly: Array in _parts[part]:
		var flat := PackedVector2Array()
		var normal: Vector3 = poly[0]["n"]
		for vertex: Dictionary in poly:
			var point: Vector3 = vertex["p"]
			flat.append(
				(
					Vector2(point.z, point.y)
					if absf(normal.x) > .99
					else (
						Vector2(point.x, point.z)
						if absf(normal.y) > .99
						else Vector2(point.x, point.y)
					)
				)
			)
		var triangulated := Geometry2D.triangulate_polygon(flat)
		for i: int in range(0, triangulated.size(), 3):
			var triangle: Array = [
				poly[triangulated[i]], poly[triangulated[i + 1]], poly[triangulated[i + 2]]
			]
			var cross: Vector3 = (triangle[1]["p"] - triangle[0]["p"]).cross(
				triangle[2]["p"] - triangle[0]["p"]
			)
			if cross.dot(triangle[0]["n"]) > 0:
				triangle.reverse()
			for vertex: Dictionary in triangle:
				var key: Array = [vertex["p"], vertex["n"], vertex["uv"]]
				if not shared.has(key):
					shared[key] = vertices.size()
					vertices.append(vertex["p"])
					normals.append(vertex["n"])
					uv.append(vertex["uv"])
				indices.append(shared[key])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ResourceSaver.save(mesh, OUT + filename)
	print(filename, ": ", indices.size() / 3, " triangles")
