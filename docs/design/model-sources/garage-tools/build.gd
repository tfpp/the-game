extends SceneTree
## Workshop equipment uses the approved lift enamel/steel atlas and indexed geometry.
const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const OUT := "res://assets/starter_room/"
const AUTHOR := "res://../docs/design/model-sources/garage-tools/"
const CHARTS: Array[Rect2i] = [
	Rect2i(4, 4, 28, 120),
	Rect2i(40, 4, 80, 32),
	Rect2i(40, 44, 40, 52),
	Rect2i(86, 44, 34, 34),
	Rect2i(86, 84, 34, 28),
	Rect2i(40, 106, 40, 16)
]
const NAMES: Array[String] = [
	"workbench", "tool_chest", "compressor", "wheel_rack", "floor_jack", "creeper", "bay_markings"
]
var _parts: Array[Array] = [[], [], [], [], [], [], []]


func _initialize() -> void:
	_workbench()
	_chest()
	_compressor()
	_rack()
	_jack()
	_creeper()
	for x: float in [-2.6, 2.6]:
		_box(6, Vector3(x, .012, 0), Vector3(.06, .015, 7), 5)
	for z: float in [-3.5, 3.5]:
		_box(6, Vector3(0, .012, z), Vector3(5.2, .015, .06), 5)
	for i: int in NAMES.size():
		_save(i, "garage_" + NAMES[i] + ".res")
	var template := Image.create(128, 128, false, Image.FORMAT_RGB8)
	template.fill(Color("34383a"))
	for chart: Rect2i in CHARTS:
		template.fill_rect(chart, Color("a8b0a6"))
	template.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	template.save_png(AUTHOR + "uv-template.png")
	quit()


func _workbench() -> void:
	# Continuous steel worktop, welded frame, drawer banks and lower storage shelf.
	_box(0, Vector3(0, .97, 0), Vector3(4.4, .1, .85), 1)
	_box(0, Vector3(0, .87, .38), Vector3(4.25, .13, .07), 2)
	for x: float in [-2.05, 0, 2.05]:
		for z: float in [-.32, .32]:
			_box(0, Vector3(x, .46, z), Vector3(.09, .92, .09), 2)
	_box(0, Vector3(0, .22, 0), Vector3(4.2, .06, .65), 1)
	for x: float in [-1.48, 1.48]:
		_box(0, Vector3(x, .64, 0), Vector3(1.15, .54, .62), 0)
		for y: float in [.47, .64, .81]:
			_box(0, Vector3(x, y, .323), Vector3(1.05, .145, .03), 0)
			_box(0, Vector3(x, y + .025, .351), Vector3(.66, .025, .025), 1)
	# Backboard meets the worktop; tools hang in front with visible clips.
	_box(0, Vector3(0, 1.55, -.385), Vector3(4.35, 1.06, .075), 2)
	for x: float in [-1.65, -.95, -.25, .45]:
		_spanner(0, Vector3(x, 1.53, -.31))
		_box(0, Vector3(x, 1.88, -.31), Vector3(.07, .045, .07), 1)
	# Screwdrivers: contrasting rubber grips, steel shafts, actual shelf below.
	_box(0, Vector3(1.45, 1.34, -.25), Vector3(.85, .06, .2), 1)
	for x: float in [1.15, 1.4, 1.65]:
		_box(0, Vector3(x, 1.58, -.2), Vector3(.065, .2, .065), 4)
		_box(0, Vector3(x, 1.42, -.2), Vector3(.018, .16, .018), 1)
	# A mounted vise, with parallel jaws and a continuous screw handle.
	_box(0, Vector3(-.48, 1.08, .1), Vector3(.36, .12, .3), 2)
	_box(0, Vector3(-.58, 1.2, .1), Vector3(.08, .22, .32), 1)
	_box(0, Vector3(-.32, 1.2, .1), Vector3(.08, .22, .32), 1)
	_cylinder(0, Vector3(-.72, 1.1, .1), .035, .48, Vector3.RIGHT, 1)
	_cylinder(0, Vector3(-.72, .98, .1), .02, .24, Vector3.UP, 1)
	# Socket tray with four socket heads, and a rubber-padded open working surface.
	_box(0, Vector3(.5, 1.035, .07), Vector3(.62, .03, .32), 4)
	for x: float in [.3, .44, .58, .72]:
		_cylinder(0, Vector3(x, 1.05, .08), .045, .1, Vector3.UP, 1)
	_box(0, Vector3(1.42, .43, .05), Vector3(.5, .35, .42), 2)


func _spanner(part: int, at: Vector3) -> void:
	_box(part, at, Vector3(.045, .46, .025), 1)
	for side: float in [-1, 1]:
		_box(part, at + Vector3(side * .07, .25, 0), Vector3(.045, .15, .025), 1)
	_box(part, at + Vector3(0, .2, 0), Vector3(.18, .045, .025), 1)
	_cylinder(part, at + Vector3(0, -.25, -.0125), .07, .025, Vector3.BACK, 1)


func _chest() -> void:
	_box(1, Vector3(0, .59, 0), Vector3(.8, .86, .5), 0)
	_box(1, Vector3(0, 1.035, 0), Vector3(.84, .045, .55), 4)
	for y: float in [.32, .51, .7, .89]:
		_box(1, Vector3(0, y, .265), Vector3(.72, .16, .035), 0)
		_box(1, Vector3(0, y + .03, .293), Vector3(.56, .025, .025), 1)
	for x: float in [-.3, .3]:
		for z: float in [-.18, .18]:
			_cylinder(1, Vector3(x - .04, .09, z), .09, .08, Vector3.RIGHT, 4)
	_box(1, Vector3(.48, .92, 0), Vector3(.06, .06, .38), 1)
	for z: float in [-.16, .16]:
		_box(1, Vector3(.43, .92, z), Vector3(.1, .035, .04), 1)


func _compressor() -> void:
	_cylinder(2, Vector3(0, .42, -.57), .29, 1.14, Vector3.BACK, 0)
	for z: float in [-.4, .4]:
		_box(2, Vector3(0, .17, z), Vector3(.55, .13, .16), 2)
		for x: float in [-.35, .27]:
			_cylinder(2, Vector3(x, .12, z), .12, .08, Vector3.RIGHT, 4)
	_box(2, Vector3(0, .78, -.1), Vector3(.48, .18, .62), 2)
	_cylinder(2, Vector3(0, .9, -.1), .13, .32, Vector3.BACK, 1)
	for z: float in [-.04, .06, .16]:
		_box(2, Vector3(0, .95, z), Vector3(.3, .02, .02), 2)
	_beam(2, Vector3(0, .75, -.4), Vector3(0, .45, -.42), .04, 1)
	for x: float in [-.25, .25]:
		_beam(2, Vector3(x, .48, -.55), Vector3(x, 1.1, -.55), .045, 1)
	_box(2, Vector3(0, 1.1, -.55), Vector3(.55, .055, .055), 4)
	# Coiled rubber air hose connects to the regulator; octagonal loop is low-poly.
	for i: int in 8:
		var a := float(i) * TAU / 8
		var b := float(i + 1) * TAU / 8
		_beam(
			2,
			Vector3(.35, .61 + cos(a) * .2, sin(a) * .2),
			Vector3(.35, .61 + cos(b) * .2, sin(b) * .2),
			.035,
			4
		)
	_beam(2, Vector3(.35, .81, 0), Vector3(0, .88, -.1), .035, 4)


func _rack() -> void:
	for x: float in [-1.05, 1.05]:
		for z: float in [-.28, .28]:
			_box(3, Vector3(x, .88, z), Vector3(.065, 1.76, .065), 2)
	for y: float in [.28, 1.08, 1.72]:
		for z: float in [-.28, .28]:
			_box(3, Vector3(0, y, z), Vector3(2.16, .065, .065), 1)
	for x: float in [-.7, 0, .7]:
		for y: float in [.65, 1.45]:
			_ring(3, Vector3(x, y, -.18), .32, .17, .36, 4)


func _jack() -> void:
	for x: float in [-.22, .22]:
		_box(4, Vector3(x, .18, 0), Vector3(.09, .18, 1.0), 0)
	_box(4, Vector3(0, .2, -.3), Vector3(.5, .13, .22), 0)
	_beam(4, Vector3(0, .19, -.3), Vector3(0, .4, .26), .1, 1)
	_cylinder(4, Vector3(0, .41, .27), .14, .06, Vector3.UP, 4)
	_beam(4, Vector3(0, .21, -.35), Vector3(0, 1.05, -.85), .045, 1)
	_beam(4, Vector3(0, 1.05, -.85), Vector3(0, 1.2, -.94), .06, 4)
	for x: float in [-.29, .23]:
		for z: float in [-.35, .37]:
			_cylinder(4, Vector3(x, .08, z), .08, .06, Vector3.RIGHT, 4)


func _creeper() -> void:
	_box(5, Vector3(0, .15, 0), Vector3(.58, .065, 1.3), 2)
	_box(5, Vector3(0, .21, .02), Vector3(.48, .07, 1.05), 4)
	_box(5, Vector3(0, .25, -.46), Vector3(.44, .12, .27), 4)
	for x: float in [-.31, .25]:
		for z: float in [-.48, .48]:
			_cylinder(5, Vector3(x, .055, z), .055, .06, Vector3.RIGHT, 4)


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


func _ring(part: int, at: Vector3, radius: float, hole: float, length: float, chart: int) -> void:
	var faces: Array[Dictionary] = []
	for i: int in 8:
		var a := float(i) * TAU / 8
		var b := float(i + 1) * TAU / 8
		var outer_a := Vector3(cos(a) * radius, sin(a) * radius, 0)
		var outer_b := Vector3(cos(b) * radius, sin(b) * radius, 0)
		var inner_a := Vector3(cos(a) * hole, sin(a) * hole, 0)
		var inner_b := Vector3(cos(b) * hole, sin(b) * hole, 0)
		for poly: PackedVector3Array in [
			PackedVector3Array(
				[outer_a, outer_b, outer_b + Vector3.BACK * length, outer_a + Vector3.BACK * length]
			),
			PackedVector3Array(
				[inner_b, inner_a, inner_a + Vector3.BACK * length, inner_b + Vector3.BACK * length]
			),
			PackedVector3Array([outer_b, outer_a, inner_a, inner_b]),
			PackedVector3Array(
				[
					outer_a + Vector3.BACK * length,
					outer_b + Vector3.BACK * length,
					inner_b + Vector3.BACK * length,
					inner_a + Vector3.BACK * length
				]
			)
		]:
			var normal := (poly[1] - poly[0]).cross(poly[2] - poly[0]).normalized()
			faces.append({"points": Transform3D(Basis.IDENTITY, at) * poly, "normal": normal})
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
			if chart == 0:
				var normal: Vector3 = face["normal"]
				var horizontal := (source[i].x + size.x / 2) / size.x
				if absf(normal.x) > .99:
					horizontal = (source[i].z + size.z / 2) / size.z
				relative = Vector2(horizontal, clampf((size.y / 2 - source[i].y) / size.y, 0, 1))
			if chart == 3 and (face["normal"] as Vector3).z > .99:
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
		for i: int in range(1, poly.size() - 1):
			var triangle: Array = [poly[0], poly[i], poly[i + 1]]
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
