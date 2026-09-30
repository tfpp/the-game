extends RefCounted
## Shared semantic islands, visibility budgets and rotated MaxRects atlas packing.

const SIZE := 128
const PADDING := 2


static func definition(kind: String) -> Dictionary:
	var faces: Array[Dictionary] = []
	match kind:
		"crate":
			add_prism(
				faces,
				"WOOD",
				[Vector2(-.5, 0), Vector2(.5, 0), Vector2(.5, 1), Vector2(-.5, 1)],
				.5
			)
		"barrel":
			add_cylinder(faces, "DRUM", .43, 1.2)
		"car":
			_car(faces)
		"wheel":
			add_cylinder(faces, "TYRE", .29, .18)
	var layout := faces.duplicate()
	if kind == "car":
		add_cylinder(layout, "TYRE", .29, .18)
	elif kind == "wheel":
		var body: Array[Dictionary] = []
		_car(body)
		body.append_array(layout)
		layout = body
	var packed := pack_faces(layout, 128.0)
	packed["kind"] = kind
	packed["faces"] = faces
	return packed


static func pack_faces(faces: Array[Dictionary], max_density: float = 1024.0) -> Dictionary:
	var density := max_density
	while not _pack(faces, density):
		density -= 1.0
		assert(density > 4)
	var islands: Array[Dictionary] = []
	var seen: Dictionary[String, bool] = {}
	for face: Dictionary in faces:
		if not seen.has(face["island"]):
			seen[face["island"]] = true
			var island := face.duplicate()
			island["source_face"] = face["name"]
			island["name"] = face["island"]
			islands.append(island)
	var area := 0
	for island: Dictionary in islands:
		var rect: Rect2i = island["rect"]
		area += rect.size.x * rect.size.y
	return {
		"density": density, "faces": faces, "islands": islands, "occupied_fraction": area / 16384.0
	}


static func _car(faces: Array[Dictionary]) -> void:
	add_prism(
		faces,
		"BODY",
		[
			Vector2(-2, .3),
			Vector2(2, .3),
			Vector2(2, .75),
			Vector2(1.2, .85),
			Vector2(.65, 1.45),
			Vector2(-.55, 1.45),
			Vector2(-1.1, .85),
			Vector2(-2, .75)
		],
		.75
	)


static func add_prism(
	faces: Array[Dictionary], id: String, profile: Array[Vector2], half_width: float
) -> void:
	# Profile is counterclockwise in (z,y). End faces have opposite winding.
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for point: Vector2 in profile:
		left.push_front(Vector3(-half_width, point.y, point.x))
		right.append(Vector3(half_width, point.y, point.x))
	add_face(faces, id + "_LEFT", left)
	add_face(faces, id + "_RIGHT", right)
	for index: int in profile.size():
		var a := profile[index]
		var b := profile[(index + 1) % profile.size()]
		add_face(
			faces,
			id + "_%d" % index,
			[
				Vector3(-half_width, b.y, b.x),
				Vector3(half_width, b.y, b.x),
				Vector3(half_width, a.y, a.x),
				Vector3(-half_width, a.y, a.x)
			]
		)


static func add_cylinder(
	faces: Array[Dictionary], id: String, radius: float, height: float
) -> void:
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for index: int in 8:
		var angle := index * TAU / 8
		top.append(Vector3(cos(angle) * radius, height, sin(angle) * radius))
		bottom.push_front(Vector3(cos(angle) * radius, 0, sin(angle) * radius))
	add_face(faces, id + "_TOP", top)
	add_face(faces, id + "_BOTTOM", bottom)
	for index: int in 8:
		var a := top[index]
		var b := top[(index + 1) % 8]
		add_face(faces, id + "_%d" % index, [b, a, Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z)])


static func add_face(faces: Array[Dictionary], id: String, points: Array[Vector3]) -> void:
	var area := Vector3.ZERO
	for index: int in points.size():
		area += points[index].cross(points[(index + 1) % points.size()])
	var normal := -area.normalized()
	var across := (points[1] - points[0]).normalized()
	var longest := 0.0
	for index: int in points.size():
		var edge := points[(index + 1) % points.size()] - points[index]
		if edge.length() > longest:
			longest = edge.length()
			across = edge.normalized()
	if absf(normal.x) > .99:
		across = Vector3.BACK if normal.x < 0 else Vector3.FORWARD
	var down := across.cross(normal).normalized()
	var projected := PackedVector2Array()
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	for point: Vector3 in points:
		var relative := point - points[0]
		var uv := Vector2(relative.dot(across), relative.dot(down))
		projected.append(uv)
		bounds = bounds.expand(uv)
	for index: int in projected.size():
		projected[index] -= bounds.position
	faces.append(
		{
			"name": id,
			"points": PackedVector3Array(points),
			"normal": normal,
			"uv_m": projected,
			"size_m": bounds.size
		}
	)


static func _pack(faces: Array[Dictionary], density: float) -> bool:
	var groups: Dictionary[String, Dictionary] = {}
	for face: Dictionary in faces:
		var id: String = face["name"]
		var island := id
		var weight := 1.0
		if id.begins_with("WOOD"):
			island = "WOOD_FACE"
		elif id.begins_with("DRUM"):
			island = "DRUM_CAP" if id.ends_with("TOP") or id.ends_with("BOTTOM") else "DRUM_SIDE"
		elif id.begins_with("TYRE"):
			island = "HUB" if id.ends_with("TOP") or id.ends_with("BOTTOM") else "TREAD"
			weight = 2.0
		elif id == "BODY_RIGHT":
			island = "BODY_LEFT"
			face["flip_x"] = true
		elif id == "BODY_3" or id == "BODY_5":
			island = "GLASS"
		elif id == "BODY_0":
			weight = .2
		island = face.get("reuse_key", island)
		weight = face.get("importance", weight)
		face["island"] = island
		face["weight"] = weight
		if not groups.has(island):
			var extent: Vector2 = face["size_m"] * density * weight
			groups[island] = {"key": island, "size": Vector2i(ceili(extent.x), ceili(extent.y))}
		else:
			var extent: Vector2 = face["size_m"] * density * weight
			var size: Vector2i = groups[island]["size"]
			groups[island]["size"] = Vector2i(
				maxi(size.x, ceili(extent.x)), maxi(size.y, ceili(extent.y))
			)
	var ordered: Array = groups.values()
	ordered.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var area_a: int = a["size"].x * a["size"].y
			var area_b: int = b["size"].x * b["size"].y
			return a["key"] < b["key"] if area_a == area_b else area_a > area_b
	)
	var free: Array[Rect2i] = [Rect2i(0, 0, SIZE, SIZE)]
	for group: Dictionary in ordered:
		var best := Rect2i()
		var score := Vector2i(10000, 10000)
		var rotated := false
		for space: Rect2i in free:
			for turn: int in 2:
				var size: Vector2i = group["size"]
				if turn == 1:
					size = Vector2i(size.y, size.x)
				size += Vector2i.ONE * PADDING * 2
				if size.x > space.size.x or size.y > space.size.y:
					continue
				var remaining := space.size - size
				var candidate := Vector2i(
					mini(remaining.x, remaining.y), maxi(remaining.x, remaining.y)
				)
				if candidate.x < score.x or (candidate.x == score.x and candidate.y < score.y):
					score = candidate
					best = Rect2i(space.position, size)
					rotated = turn == 1
		if best.size == Vector2i.ZERO:
			return false
		group["rect"] = best.grow(-PADDING)
		group["rotated"] = rotated
		var split: Array[Rect2i] = []
		for space: Rect2i in free:
			if not space.intersects(best):
				split.append(space)
				continue
			if best.position.x > space.position.x:
				split.append(
					Rect2i(
						space.position, Vector2i(best.position.x - space.position.x, space.size.y)
					)
				)
			if best.end.x < space.end.x:
				split.append(
					Rect2i(
						Vector2i(best.end.x, space.position.y),
						Vector2i(space.end.x - best.end.x, space.size.y)
					)
				)
			if best.position.y > space.position.y:
				split.append(
					Rect2i(
						space.position, Vector2i(space.size.x, best.position.y - space.position.y)
					)
				)
			if best.end.y < space.end.y:
				split.append(
					Rect2i(
						Vector2i(space.position.x, best.end.y),
						Vector2i(space.size.x, space.end.y - best.end.y)
					)
				)
		free.clear()
		for index: int in split.size():
			var contained := false
			for other: int in split.size():
				if (
					index != other
					and split[other].encloses(split[index])
					and (split[other] != split[index] or other < index)
				):
					contained = true
					break
			if not contained:
				free.append(split[index])
	for face: Dictionary in faces:
		var group: Dictionary = groups[face["island"]]
		face["rect"] = group["rect"]
		face["rotated"] = group["rotated"]
	return true


static func mesh(data: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for face: Dictionary in data["faces"]:
		var points: PackedVector3Array = face["points"]
		var projected: PackedVector2Array = face["uv_m"]
		var base := vertices.size()
		for index: int in points.size():
			vertices.append(points[index])
			normals.append(face["normal"])
			var coordinate := projected[index]
			var extent: Vector2 = face["size_m"]
			if face.get("flip_x", false):
				coordinate.x = extent.x - coordinate.x
			if face["rotated"]:
				coordinate = Vector2(extent.y - coordinate.y, coordinate.x)
			uv.append(
				(
					(Vector2(face["rect"].position) + coordinate * data["density"] * face["weight"])
					/ SIZE
				)
			)
		var triangles := Geometry2D.triangulate_polygon(projected)
		assert(not triangles.is_empty())
		for index: int in range(0, triangles.size(), 3):
			# Godot expects clockwise geometry. Projection basis is clockwise.
			indices.append_array(
				PackedInt32Array(
					[
						base + triangles[index],
						base + triangles[index + 1],
						base + triangles[index + 2]
					]
				)
			)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
