extends SceneTree
## Derive moving leaves from the approved painted shell, preserving its exact UVs.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const OUT := "res://assets/starter_room/"
const HINGES: Array[Vector3] = [
	Vector3(-1, .85, 1.6), Vector3(1, .85, 1.6), Vector3(-.92, .7, -2.5), Vector3(.92, .7, -2.5)
]
const AUTHOR := "res://../docs/design/model-sources/armoured-operations-van/"
const NAMES: Array[String] = ["driver", "passenger", "rear_left", "rear_right"]
var _parts: Array[Array] = [[], [], [], [], []]


func _initialize() -> void:
	var original := load("res://assets/starter_room/van.res") as ArrayMesh
	var arrays := original.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i: int in range(0, indices.size(), 3):
		var polygon: Array[Dictionary] = []
		for j: int in 3:
			var index := indices[i + j]
			polygon.append({"p": vertices[index], "n": normals[index], "uv": uvs[index]})
		var normal := normals[indices[i]]
		if absf(normal.x) > .99 and is_equal_approx(absf(vertices[indices[i]].x), 1.0):
			_carve(polygon, 0 if normal.x < 0 else 1, 2, .15, 1.6, 1, .85, 2.13)
		elif normal.z < -.99 and vertices[indices[i]].z < -2.49:
			# First split left/right, then cut out each rear leaf.
			_carve(_clip(polygon, 0, 0, false), 2, 0, -.92, 0, 1, .7, 2.03)
			_carve(_clip(polygon, 0, 0, true), 3, 0, 0, .92, 1, .7, 2.03)
		else:
			_parts[0].append(polygon)
	var detail: Array[Dictionary] = []
	# Ladder frame, crossmembers, floor, axles, differential housings and leaf springs.
	for x: float in [-.64, .64]:
		_box(detail, Vector3(x, .45, 0), Vector3(.14, .18, 4.3), "steel")
		for z: float in [-1.6, 1.6]:
			_box(detail, Vector3(x, .49, z), Vector3(.12, .07, .85), "steel")
	for z: float in [-1.9, -.7, .6, 1.9]:
		_box(detail, Vector3(0, .47, z), Vector3(1.3, .12, .12), "steel")
	for z: float in [-1.6, 1.6]:
		_cylinder(detail, Vector3(-.98, .38, z), .07, 1.96, Basis(Vector3.FORWARD, PI / 2), "steel")
		if z < 0:
			_cylinder(
				detail, Vector3(0, .38, z - .12), .18, .24, Basis(Vector3.RIGHT, PI / 2), "alloy"
			)
	_cylinder(detail, Vector3(0, .38, -1.49), .055, 2.22, Basis(Vector3.RIGHT, PI / 2), "alloy")
	_box(detail, Vector3(0, .64, -.3), Vector3(1.84, .14, 4.1), "steel")
	# Rear-wheel-drive chain: front engine -> gearbox -> shaft -> rear differential.
	_box(detail, Vector3(0, .43, 1.82), Vector3(.58, .38, .74), "alloy")
	_box(detail, Vector3(0, .39, 1.08), Vector3(.32, .28, .74), "alloy")
	_box(detail, Vector3(0, .23, 1.82), Vector3(.48, .08, .62), "steel")
	_box(detail, Vector3(-.4, .38, -.55), Vector3(.5, .28, .95), "steel")
	_tube(detail, Vector3(.22, .32, 1.75), Vector3(.72, .32, 1.3), .045, "steel")
	_cylinder(detail, Vector3(.72, .32, -2.6), .045, 3.9, Basis(Vector3.RIGHT, PI / 2), "steel")
	_box(detail, Vector3(.65, .34, -.65), Vector3(.22, .18, .65), "steel")
	# Cab floor, seats, dashboard and sealed cargo bulkhead.
	_box(detail, Vector3(0, 1.45, .1), Vector3(1.84, 1.5, .12), "steel")
	_box(detail, Vector3(0, 1.25, 1.55), Vector3(1.84, .22, .26), "steel")
	for x: float in [-.52, .52]:
		_box(detail, Vector3(x, .93, .65), Vector3(.55, .25, .55), "rubber")
		_box(detail, Vector3(x, 1.3, .37), Vector3(.55, .68, .12), "rubber")
	_cylinder(detail, Vector3(-.52, 1.39, 1.38), .17, .035, Basis(Vector3.RIGHT, PI / 2), "rubber")
	_box(detail, Vector3(-1.09, 1.3, -.6), Vector3(.1, .34, .46), "steel")
	# Armoured side plates, rear door jambs and roof rim.
	for x: float in [-1.02, 1.02]:
		_box(detail, Vector3(x, 1.42, -1.15), Vector3(.07, 1.15, 2.45), "paint")
		_box(detail, Vector3(x, .72, .6), Vector3(.18, .12, 1.3), "steel")
		_box(detail, Vector3(x, 1.38, -2.46), Vector3(.12, 1.5, .12), "steel")
		_box(detail, Vector3(x, 2.2, -.65), Vector3(.09, .1, 3.4), "paint")
	_box(detail, Vector3(0, 2.16, -.65), Vector3(1.84, .06, 3.3), "paint")
	_box(detail, Vector3(0, 2.07, -2.46), Vector3(1.94, .12, .12), "steel")
	# Bumpers and front bull bar mounted to chassis.
	for z: float in [-2.55, 2.55]:
		_box(detail, Vector3(0, .65, z), Vector3(2.18, .22, .18), "steel")
	for x: float in [-.72, .72]:
		_box(detail, Vector3(x, .92, 2.65), Vector3(.1, .65, .12), "steel")
	for y: float in [.78, 1.17]:
		_box(detail, Vector3(0, y, 2.65), Vector3(1.95, .09, .12), "steel")
	# Inner jambs finish the aperture exposed by opening a cab leaf.
	for side: float in [-1, 1]:
		_box(detail, Vector3(side * .93, 1.5, .135), Vector3(.1, 1.3, .07), "steel")
		_box(detail, Vector3(side * .93, 2.135, .66), Vector3(.1, .045, 1.05), "steel")
		var pillar: Array[Dictionary] = []
		PROP.add_prism(
			pillar,
			"steel",
			[
				Vector2(1.585, 1.425),
				Vector2(1.63, 1.425),
				Vector2(1.17, 2.17),
				Vector2(1.125, 2.17)
			],
			.05
		)
		_transform(detail, pillar, Transform3D(Basis.IDENTITY, Vector3(side * .93, 0, 0)))

	_append_faces(detail, 0)
	_save(0, "van_armoured.res", Vector3.ZERO)
	for door: int in 4:
		var hardware: Array[Dictionary] = []
		var side := -1.0 if door in [0, 2] else 1.0
		if door < 2:
			_parts[door + 1].clear()
			_cab_door(hardware, side)

		else:
			_box(hardware, Vector3(side * .47, 1.36, -2.44), Vector3(.89, 1.32, .08), "paint")
			_box(hardware, Vector3(side * .22, 1.34, -2.57), Vector3(.06, 1.15, .06), "steel")
			_box(hardware, Vector3(side * .4, 1.33, -2.59), Vector3(.32, .07, .07), "steel")
			for y: float in [.85, 1.85]:
				_box(hardware, Vector3(side * .89, y, -2.56), Vector3(.16, .09, .1), "steel")
		_append_faces(hardware, door + 1)
		_save(door + 1, "van_" + NAMES[door] + ".res", HINGES[door])
		if door < 2:
			var shape := ConvexPolygonShape3D.new()
			var cage := PackedVector3Array()
			for x: float in [side * 1.005, side * .945]:
				for point: Vector2 in _cab_outline():
					cage.append(Vector3(x, point.y, point.x) - HINGES[door])
			shape.points = cage
			ResourceSaver.save(shape, OUT + "van_" + NAMES[door] + "_collision.tres")
	_template()
	if not OS.get_cmdline_user_args().is_empty():
		var image := Image.load_from_file(OS.get_cmdline_user_args()[0])
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		var unpadded := image.duplicate() as Image
		for rect: Rect2i in _cab_charts():
			for y: int in range(rect.position.y - 2, rect.end.y + 2):
				for x: int in range(rect.position.x - 2, rect.end.x + 2):
					image.set_pixel(
						x,
						y,
						unpadded.get_pixel(
							clampi(x, rect.position.x, rect.end.x - 1),
							clampi(y, rect.position.y, rect.end.y - 1)
						)
					)
		image.save_png(OUT + "van_cab.png")
	quit()


func _cab_outline() -> Array[Vector2]:
	return [
		Vector2(.175, .875),
		Vector2(1.575, .875),
		Vector2(1.575, 1.455),
		Vector2(1.174, 2.11),
		Vector2(.175, 2.11)
	]


func _cab_door(faces: Array[Dictionary], side: float) -> void:
	# The front edge follows the windshield rake, rather than a rectangular post.
	var outline := _cab_outline()
	var window: Array[Vector2] = [
		Vector2(.29, 1.62), Vector2(1.352, 1.62), Vector2(1.092, 2.012), Vector2(.29, 2.012)
	]
	# Four continuous frame sections; both skins and perimeter returns are authored.
	_profile(faces, [outline[0], outline[1], outline[2], window[1], window[0]], side, "doorpaint")
	_profile(faces, [outline[2], outline[3], window[2], window[1]], side, "doorpaint")
	_profile(faces, [outline[3], outline[4], window[3], window[2]], side, "doorpaint")
	_profile(faces, [outline[4], outline[0], window[0], window[3]], side, "doorpaint")
	# Inset gasket and glazing follow the same sloped frame profile.
	var glass: Array[Vector2] = [
		Vector2(.317, 1.647), Vector2(1.302, 1.647), Vector2(1.074, 1.985), Vector2(.317, 1.985)
	]
	for i: int in 4:
		_planar(
			faces,
			[window[i], window[(i + 1) % 4], glass[(i + 1) % 4], glass[i]],
			side * 1.003,
			"gasket"
		)
		_planar(
			faces,
			[window[i], window[(i + 1) % 4], glass[(i + 1) % 4], glass[i]],
			side * .943,
			"gasket"
		)
	_planar(faces, glass, side * .975, "glass")
	glass.reverse()
	_planar(faces, glass, side * .97, "glass")
	# Door-mounted mirrors stay attached in every open pose.
	_box(faces, Vector3(side * 1.13, 1.57, 1.365), Vector3(.26, .045, .06), "doorsteel")
	_box(faces, Vector3(side * 1.245, 1.65, 1.365), Vector3(.075, .2, .2), "gasket")
	# Recessed latch bed, small pull handle and two compact hinge knuckles.
	_box(faces, Vector3(side * 1.013, 1.37, .365), Vector3(.018, .115, .245), "gasket")
	_box(faces, Vector3(side * 1.036, 1.37, .365), Vector3(.04, .035, .175), "doorsteel")
	for y: float in [1.02, 1.34]:
		_box(faces, Vector3(side * 1.027, y, 1.558), Vector3(.05, .095, .075), "doorsteel")
	_box(faces, Vector3(side * .924, 1.27, .63), Vector3(.045, .055, .48), "gasket")
	_box(faces, Vector3(side * .93, 1.07, .77), Vector3(.035, .13, .68), "interior")


func _profile(
	faces: Array[Dictionary], profile: Array[Vector2], side: float, paint: String
) -> void:
	_planar(faces, profile, side * 1.005, paint)
	var reversed := profile.duplicate()
	reversed.reverse()
	_planar(faces, reversed, side * .945, "interior")
	for i: int in profile.size():
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		PROP.add_face(
			faces,
			"dooredge",
			[
				Vector3(side * 1.005, a.y, a.x),
				Vector3(side * .945, a.y, a.x),
				Vector3(side * .945, b.y, b.x),
				Vector3(side * 1.005, b.y, b.x)
			]
		)


func _planar(faces: Array[Dictionary], profile: Array[Vector2], x: float, paint: String) -> void:
	var points: Array[Vector3] = []
	for point: Vector2 in profile:
		points.append(Vector3(x, point.y, point.x))
	PROP.add_face(faces, paint, points)
	# Profiles face +X; reverse the left exterior (and its inner skin).
	if x < 0:
		var face: Dictionary = faces.back()
		face["normal"] = -(face["normal"] as Vector3)


func _cab_charts() -> Array[Rect2i]:
	return [
		Rect2i(4, 4, 58, 64),
		Rect2i(68, 4, 56, 64),
		Rect2i(4, 74, 58, 30),
		Rect2i(68, 74, 24, 24),
		Rect2i(100, 74, 24, 24),
		Rect2i(4, 110, 58, 14)
	]


func _template() -> void:
	var template := Image.create(128, 128, false, Image.FORMAT_RGB8)
	template.fill(Color("34383a"))
	for rect: Rect2i in _cab_charts():
		template.fill_rect(rect, Color("9eaba2"))
	template.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	template.save_png(AUTHOR + "cab-uv-template.png")


func _carve(
	poly: Array[Dictionary],
	door: int,
	axis: int,
	low: float,
	high: float,
	vertical: int,
	bottom: float,
	top: float
) -> void:
	var inside := poly
	for plane: Vector3 in [
		Vector3(axis, low, 1),
		Vector3(axis, high, -1),
		Vector3(vertical, bottom, 1),
		Vector3(vertical, top, -1)
	]:
		var outside := _clip(inside, int(plane.x), plane.y, plane.z < 0)
		if outside.size() >= 3:
			_parts[0].append(outside)
		inside = _clip(inside, int(plane.x), plane.y, plane.z > 0)
	if inside.size() >= 3:
		_parts[door + 1].append(inside)


func _clip(poly: Array[Dictionary], axis: int, value: float, above: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if poly.is_empty():
		return result
	var previous: Dictionary = poly.back()
	for current: Dictionary in poly:
		var a: float = (previous["p"] as Vector3)[axis] - value
		var b: float = (current["p"] as Vector3)[axis] - value
		var a_in := a >= 0 if above else a <= 0
		var b_in := b >= 0 if above else b <= 0
		if a_in != b_in:
			var t := a / (a - b)
			result.append(
				{
					"p": (previous["p"] as Vector3).lerp(current["p"], t),
					"n": current["n"],
					"uv": (previous["uv"] as Vector2).lerp(current["uv"], t)
				}
			)
		if b_in:
			result.append(current)
		previous = current
	return result


func _box(faces: Array[Dictionary], center: Vector3, size: Vector3, paint: String) -> void:
	var local: Array[Dictionary] = []
	PROP.add_prism(
		local,
		paint,
		[
			Vector2(-size.z / 2, -size.y / 2),
			Vector2(size.z / 2, -size.y / 2),
			Vector2(size.z / 2, size.y / 2),
			Vector2(-size.z / 2, size.y / 2)
		],
		size.x / 2
	)
	_transform(faces, local, Transform3D(Basis.IDENTITY, center))


func _cylinder(
	faces: Array[Dictionary],
	center: Vector3,
	radius: float,
	length: float,
	basis: Basis,
	paint: String
) -> void:
	var local: Array[Dictionary] = []
	PROP.add_cylinder(local, paint, radius, length)
	_transform(faces, local, Transform3D(basis, center))


func _tube(
	faces: Array[Dictionary], start: Vector3, end: Vector3, radius: float, paint: String
) -> void:
	var direction := (end - start).normalized()
	_cylinder(
		faces,
		start,
		radius,
		start.distance_to(end),
		Basis(Quaternion(Vector3.UP, direction)),
		paint
	)


func _transform(faces: Array[Dictionary], local: Array[Dictionary], transform: Transform3D) -> void:
	for face: Dictionary in local:
		face["points"] = transform * (face["points"] as PackedVector3Array)
		face["normal"] = transform.basis * (face["normal"] as Vector3)
		faces.append(face)


func _append_faces(faces: Array[Dictionary], part: int) -> void:
	for face: Dictionary in faces:
		# Intentional solid swatches from the approved atlas: no repaint or new texture.
		var uv := Vector2(123.5, 123.5) / 128
		if (face["name"] as String).begins_with("alloy"):
			uv = Vector2(89.5, 75.5) / 128
		if (face["name"] as String).begins_with("paint"):
			uv = Vector2(18.5, 121.5) / 128
		elif (face["name"] as String).begins_with("rubber"):
			uv = Vector2(123.5, 123.5) / 128
		var poly: Array[Dictionary] = []
		for point: Vector3 in face["points"]:
			var mapped := uv
			var id: String = face["name"]
			if id == "doorpaint" or id.begins_with("interior"):
				var origin := Vector2(4.5, 4.5) if id == "doorpaint" else Vector2(68.5, 4.5)
				var extent := Vector2(57, 63) if id == "doorpaint" else Vector2(55, 63)
				mapped = (
					(origin + Vector2((point.z - .175) / 1.4, (2.11 - point.y) / 1.235) * extent)
					/ 128
				)
			elif id == "glass":
				mapped = (
					(
						Vector2(4.5, 74.5)
						+ (
							Vector2((point.z - .317) / .985, (1.985 - point.y) / .338)
							* Vector2(57, 29)
						)
					)
					/ 128
				)
			elif id.begins_with("doorsteel"):
				mapped = Vector2(80.5, 86.5) / 128
			elif id.begins_with("gasket"):
				mapped = Vector2(112.5, 86.5) / 128
			elif id == "dooredge":
				mapped = Vector2(30.5, 117.5) / 128
			poly.append({"p": point, "n": face["normal"], "uv": mapped})
		_parts[part].append(poly)


func _save(part: int, filename: String, pivot: Vector3) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var shared: Dictionary[Array, int] = {}
	for poly: Array in _parts[part]:
		for i: int in range(1, poly.size() - 1):
			var triangle: Array[Dictionary] = [poly[0], poly[i], poly[i + 1]]
			var cross: Vector3 = ((triangle[1]["p"] as Vector3) - triangle[0]["p"]).cross(
				(triangle[2]["p"] as Vector3) - triangle[0]["p"]
			)
			if cross.length() < .000001:
				continue
			if cross.dot(triangle[0]["n"]) > 0:
				triangle.reverse()
			for vertex: Dictionary in triangle:
				var key: Array = [vertex["p"], vertex["n"], vertex["uv"]]
				if not shared.has(key):
					shared[key] = vertices.size()
					vertices.append(vertex["p"] - pivot)
					normals.append(vertex["n"])
					uvs.append(vertex["uv"])
				indices.append(shared[key])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ResourceSaver.save(mesh, OUT + filename)
	print(filename, ": ", indices.size() / 3, " triangles")
