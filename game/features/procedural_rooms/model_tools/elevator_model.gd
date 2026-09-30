extends RefCounted
## Shared cab/door/button atlas. Repeated walls, both door leaves and trim reuse islands.

const Prop := preload("res://features/procedural_rooms/model_tools/prop_model.gd")


static func definition() -> Dictionary:
	var faces: Array[Dictionary] = []
	_quad(
		faces,
		"cab",
		"WOOD",
		[
			Vector3(-1.5, 3, -1.5),
			Vector3(1.5, 3, -1.5),
			Vector3(1.5, 0, -1.5),
			Vector3(-1.5, 0, -1.5)
		]
	)
	_quad(
		faces,
		"cab",
		"WOOD",
		[
			Vector3(-1.5, 3, 1.5),
			Vector3(-1.5, 3, -1.5),
			Vector3(-1.5, 0, -1.5),
			Vector3(-1.5, 0, 1.5)
		]
	)
	_quad(
		faces,
		"cab",
		"WOOD",
		[Vector3(1.5, 3, -1.5), Vector3(1.5, 3, 1.5), Vector3(1.5, 0, 1.5), Vector3(1.5, 0, -1.5)]
	)
	_quad(
		faces,
		"cab",
		"FLOOR",
		[
			Vector3(-1.5, 0, -1.5),
			Vector3(1.5, 0, -1.5),
			Vector3(1.5, 0, 1.5),
			Vector3(-1.5, 0, 1.5)
		],
		.75
	)
	_quad(
		faces,
		"cab",
		"CEILING",
		[
			Vector3(-1.5, 3, 1.5),
			Vector3(1.5, 3, 1.5),
			Vector3(1.5, 3, -1.5),
			Vector3(-1.5, 3, -1.5)
		],
		.6
	)
	for y: float in [.18, 1.05, 2.85]:
		_box(faces, "cab", "BRASS", Vector3(2.92, .06, .08), Vector3(0, y, -1.44))
		for side: float in [-1, 1]:
			_box(faces, "cab", "BRASS", Vector3(.08, .06, 2.92), Vector3(side * 1.44, y, 0))
	_box(faces, "cab", "STEEL", Vector3(3, .04, .22), Vector3(0, .02, 1.17))
	_box(faces, "cab", "BRASS", Vector3(.9, .12, .9), Vector3(0, 2.93, 0))
	_quad(
		faces,
		"cab",
		"LIGHT",
		[
			Vector3(-.4, 2.86, .4),
			Vector3(.4, 2.86, .4),
			Vector3(.4, 2.86, -.4),
			Vector3(-.4, 2.86, -.4)
		],
		.2
	)
	for side: float in [-1, 1]:
		_box(faces, "frame", "BRASS", Vector3(.16, 3.15, .24), Vector3(side * 1.58, 1.575, 0))
	_box(faces, "frame", "BRASS", Vector3(3.32, .16, .24), Vector3(0, 3.08, 0))
	_box(faces, "cab", "STEEL", Vector3(1.0, .32, .06), Vector3(0, 2.65, -1.39))
	for z: float in [-.07, .07]:
		var points: Array[Vector3] = [
			Vector3(-.745, 2.98, z),
			Vector3(.745, 2.98, z),
			Vector3(.745, 0, z),
			Vector3(-.745, 0, z)
		]
		if z > 0:
			points = [points[1], points[0], points[3], points[2]]
		_quad(faces, "leaf", "DOOR", points, 1.25)
	for y: float in [0, 2.98]:
		var points: Array[Vector3] = [
			Vector3(-.745, y, -.07),
			Vector3(.745, y, -.07),
			Vector3(.745, y, .07),
			Vector3(-.745, y, .07)
		]
		if y == 0:
			points = [points[1], points[0], points[3], points[2]]
		_quad(faces, "leaf", "STEEL", points, .1)
	for side: float in [-1, 1]:
		_box(faces, "leaf", "STEEL", Vector3(.025, 2.98, .14), Vector3(side * .7325, 1.49, 0))
	_box(faces, "button", "STEEL", Vector3(.1, .5, .35), Vector3(.27, 1.4, 0))
	_quad(
		faces,
		"button",
		"CONTROL",
		[
			Vector3(.215, 1.65, -.175),
			Vector3(.215, 1.65, .175),
			Vector3(.215, 1.15, .175),
			Vector3(.215, 1.15, -.175)
		],
		2.0
	)
	# Keep the painted UV layout while trimming physical faces to the closed door's inner plane.
	for face: Dictionary in faces:
		if face["part"] != "cab":
			continue
		var points: PackedVector3Array = face["points"]
		for index: int in points.size():
			points[index].z = minf(points[index].z, 1.28)
		face["points"] = points
	var data := Prop.pack_faces(faces, 64)
	return data


static func part(data: Dictionary, id: String) -> ArrayMesh:
	var subset: Array[Dictionary] = []
	for face: Dictionary in data["faces"]:
		if face["part"] == id:
			subset.append(face)
	var value := data.duplicate()
	value["faces"] = subset
	return Prop.mesh(value)


static func _quad(
	faces: Array[Dictionary],
	part_id: String,
	island: String,
	points: Array[Vector3],
	importance: float = 1.0
) -> void:
	Prop.add_face(faces, "%s_%d" % [part_id, faces.size()], points)
	var face: Dictionary = faces.back()
	face["part"] = part_id
	face["reuse_key"] = island
	face["importance"] = importance
	# Explicit upright coordinates: across the top edge, then down, including mirrored walls.
	var across := points[1] - points[0]
	var down := points[3] - points[0]
	face["size_m"] = Vector2(across.length(), down.length())
	face["uv_m"] = PackedVector2Array(
		[
			Vector2.ZERO,
			Vector2(across.length(), 0),
			Vector2(across.length(), down.length()),
			Vector2(0, down.length())
		]
	)


static func _box(
	faces: Array[Dictionary], part_id: String, island: String, size: Vector3, center: Vector3
) -> void:
	var raw: Array[Dictionary] = []
	Prop.add_prism(
		raw,
		part_id,
		[
			Vector2(-size.z / 2, -size.y / 2),
			Vector2(size.z / 2, -size.y / 2),
			Vector2(size.z / 2, size.y / 2),
			Vector2(-size.z / 2, size.y / 2)
		],
		size.x / 2
	)
	for face: Dictionary in raw:
		var points: PackedVector3Array = face["points"]
		for index: int in points.size():
			points[index] += center
		face["points"] = points
		face["part"] = part_id
		face["reuse_key"] = island
		face["importance"] = .3
		face["size_m"] = Vector2.ONE * .5
		face["uv_m"] = PackedVector2Array(
			[Vector2.ZERO, Vector2(.5, 0), Vector2(.5, .5), Vector2(0, .5)]
		)
		faces.append(face)
