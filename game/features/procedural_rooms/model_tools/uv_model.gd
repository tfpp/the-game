extends RefCounted
## Named planar islands: geometry, UV1, template and manifest share one definition.

const ATLAS_SIZE := 128
const PADDING := 2
const PIXELS_PER_METRE := 30.0


static func cabinet_faces() -> Array[Dictionary]:
	return [
		_face(
			"FRONT",
			Rect2i(4, 4, 30, 75),
			[Vector3(.3, 2.5, .5), Vector3(.3, 2.5, -.5), Vector3(.3, 0, -.5), Vector3(.3, 0, .5)],
			Vector3.RIGHT
		),
		_face(
			"BACK",
			Rect2i(38, 4, 30, 75),
			[
				Vector3(-.3, 2.5, -.5),
				Vector3(-.3, 2.5, .5),
				Vector3(-.3, 0, .5),
				Vector3(-.3, 0, -.5)
			],
			Vector3.LEFT
		),
		_face(
			"LEFT",
			Rect2i(72, 4, 18, 75),
			[Vector3(-.3, 2.5, .5), Vector3(.3, 2.5, .5), Vector3(.3, 0, .5), Vector3(-.3, 0, .5)],
			Vector3.BACK
		),
		_face(
			"RIGHT",
			Rect2i(94, 4, 18, 75),
			[
				Vector3(.3, 2.5, -.5),
				Vector3(-.3, 2.5, -.5),
				Vector3(-.3, 0, -.5),
				Vector3(.3, 0, -.5)
			],
			Vector3.FORWARD
		),
		_face(
			"TOP",
			Rect2i(4, 87, 30, 18),
			[
				Vector3(-.3, 2.5, .5),
				Vector3(-.3, 2.5, -.5),
				Vector3(.3, 2.5, -.5),
				Vector3(.3, 2.5, .5)
			],
			Vector3.UP
		),
		_face(
			"BOTTOM",
			Rect2i(38, 87, 30, 18),
			[Vector3(.3, 0, .5), Vector3(.3, 0, -.5), Vector3(-.3, 0, -.5), Vector3(-.3, 0, .5)],
			Vector3.DOWN
		)
	]


static func _face(id: String, rect: Rect2i, points: Array, normal: Vector3) -> Dictionary:
	return {"name": id, "rect": rect, "points": PackedVector3Array(points), "normal": normal}


static func validate(faces: Array[Dictionary]) -> Array[String]:
	var errors: Array[String] = []
	var names: Dictionary[String, bool] = {}
	var occupied: Array[Rect2i] = []
	var bounds := Rect2i(0, 0, ATLAS_SIZE, ATLAS_SIZE)
	for face: Dictionary in faces:
		var id: String = face["name"]
		var rect: Rect2i = face["rect"]
		var points: PackedVector3Array = face["points"]
		if names.has(id):
			errors.append(id + ": duplicate island")
		names[id] = true
		var padded := rect.grow(PADDING)
		if rect.size.x <= 0 or rect.size.y <= 0 or not bounds.encloses(padded):
			errors.append(id + ": island or padding outside atlas")
		for other: Rect2i in occupied:
			if padded.intersects(other):
				errors.append(id + ": overlapping padded islands")
		occupied.append(padded)
		if points.size() != 4:
			errors.append(id + ": expected a planar quad")
			continue
		var across := points[1] - points[0]
		var down := points[3] - points[0]
		if across.length() < 0.0001 or down.length() < 0.0001:
			errors.append(id + ": degenerate geometry")
			continue
		if (
			absf(across.normalized().dot(down.normalized())) > 0.0001
			or (points[2] - points[0] - across - down).length() > 0.0001
		):
			errors.append(id + ": nonrectangular face needs a dedicated unwrap")
		if across.cross(down).normalized().dot(-face["normal"]) < 0.999:
			errors.append(id + ": winding disagrees with normal")
		if (
			absf(rect.size.x / across.length() - PIXELS_PER_METRE) > 0.01
			or absf(rect.size.y / down.length() - PIXELS_PER_METRE) > 0.01
		):
			errors.append(id + ": inconsistent texel density")
	return errors


static func mesh(faces: Array[Dictionary]) -> ArrayMesh:
	assert(validate(faces).is_empty(), str(validate(faces)))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	for face: Dictionary in faces:
		var points: PackedVector3Array = face["points"]
		var rect := Rect2(face["rect"])
		var corners: Array[Vector2] = [
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y)
		]
		var normal: Vector3 = face["normal"]
		var tangent := (points[1] - points[0]).normalized()
		var bitangent := (points[3] - points[0]).normalized()
		var handedness := 1.0 if normal.cross(tangent).dot(bitangent) > 0 else -1.0
		var base := vertices.size()
		for index: int in 4:
			vertices.append(points[index])
			normals.append(normal)
			uv.append(corners[index] / ATLAS_SIZE)
			tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, handedness]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


static func template(faces: Array[Dictionary], checker: bool = false) -> Image:
	var result := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGB8)
	result.fill(Color("222831"))
	var colors: Array[Color] = [
		Color("b77a63"),
		Color("728bb0"),
		Color("8f9d6a"),
		Color("b8a76d"),
		Color("8a79a8"),
		Color("699f9b")
	]
	for index: int in faces.size():
		var rect: Rect2i = faces[index]["rect"]
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var color := colors[index % colors.size()]
				if checker:
					color = Color("eeeeee") if (x / 3 + y / 3) % 2 == 0 else Color("333333")
				result.set_pixel(x, y, color)
	return result


static func prepare_albedo(source: Image, faces: Array[Dictionary]) -> Image:
	# Resampling and edge extrusion are asset processing, not a second artwork pass.
	var scaled := source.duplicate() as Image
	scaled.convert(Image.FORMAT_RGB8)
	scaled.resize(ATLAS_SIZE, ATLAS_SIZE, Image.INTERPOLATE_LANCZOS)
	var result := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGB8)
	result.fill(Color("222831"))
	for face: Dictionary in faces:
		var rect: Rect2i = face["rect"]
		var padded := rect.grow(PADDING)
		for y: int in range(padded.position.y, padded.end.y):
			for x: int in range(padded.position.x, padded.end.x):
				result.set_pixel(
					x,
					y,
					scaled.get_pixel(
						clampi(x, rect.position.x, rect.end.x - 1),
						clampi(y, rect.position.y, rect.end.y - 1)
					)
				)
	return result
