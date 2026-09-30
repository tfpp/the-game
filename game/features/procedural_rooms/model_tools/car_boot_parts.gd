extends RefCounted
## Split the existing painted rear deck without repacking its shared atlas.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const PIVOT := Vector3(0, .85, 1.2)


static func meshes() -> Dictionary[String, ArrayMesh]:
	var original := PROP.definition("car")
	var body: Array[Dictionary] = []
	var lid: Array[Dictionary] = []
	var underside: Dictionary
	for face: Dictionary in original["faces"]:
		if face["name"] == "BODY_0":
			underside = face
		if face["name"] != "BODY_2":
			body.append(face)
			continue
		var top := face.duplicate(true)
		var points: PackedVector3Array = top["points"]
		for index: int in points.size():
			points[index] -= PIVOT
		top["points"] = points
		lid.append(top)
		var bottom := top.duplicate(true)
		var reverse: PackedVector3Array = bottom["points"]
		var uv: PackedVector2Array = bottom["uv_m"]
		reverse.reverse()
		for index: int in reverse.size():
			reverse[index].y -= .025
		bottom["points"] = reverse
		bottom["uv_m"] = uv
		bottom["normal"] = -top["normal"]
		lid.append(bottom)
	var interior: Array[Dictionary] = []
	PROP.add_prism(
		interior,
		"CAVITY",
		[Vector2(1.24, .38), Vector2(1.96, .38), Vector2(1.96, .72), Vector2(1.24, .82)],
		.7
	)
	var cavity: Array[Dictionary] = []
	for face: Dictionary in interior:
		if face["name"] == "CAVITY_2":
			continue
		var points: PackedVector3Array = face["points"]
		var uv: PackedVector2Array = face["uv_m"]
		points.reverse()
		var extent: Vector2 = face["size_m"]
		var rect: Rect2i = underside["rect"]
		var scale: float = original["density"] * underside["weight"]
		for index: int in uv.size():
			uv[index] = uv[index] / extent * Vector2(rect.size) / scale
		face["points"] = points
		face["uv_m"] = uv
		face["normal"] = -face["normal"]
		face["rect"] = rect
		face["rotated"] = false
		face["weight"] = underside["weight"]
		cavity.append(face)
	var data := original.duplicate()
	data["faces"] = body
	var result: Dictionary[String, ArrayMesh] = {"body": PROP.mesh(data)}
	data["faces"] = lid
	result["lid"] = PROP.mesh(data)
	data["faces"] = cavity
	result["interior"] = PROP.mesh(data)
	return result
