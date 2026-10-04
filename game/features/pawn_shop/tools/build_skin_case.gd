extends SceneTree
## Authoritative native mesh/UV builder. Optional argument: painted atlas source.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const ASSET := "res://assets/pawn_shop/models/skin_case"
const SOURCE := "res://../docs/design/model-sources/prawn-skin-case"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSET))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SOURCE))
	var faces: Array[Dictionary] = []
	_shell(faces, "BODY", 0.34, 0.30, 0.025, 0.455)
	_shell(faces, "GASKET", 0.335, 0.295, 0.455, 0.47)
	_shell(faces, "LID", 0.35, 0.31, 0.47, 0.60)
	for x: float in [-0.24, 0.0, 0.24]:
		_box(faces, "RIB", Vector3(x, 0.609, 0), Vector3(0.045, 0.018, 0.53))
	for x: float in [-0.235, 0.235]:
		_box(faces, "LATCH", Vector3(x, 0.465, 0.316), Vector3(0.065, 0.16, 0.026))
		_box(faces, "HINGE", Vector3(x, 0.466, -0.311), Vector3(0.085, 0.09, 0.02))
	_handle(faces)
	var definition := PROP.pack_faces(faces, 160.0)
	var islands: Array[Dictionary] = definition["islands"]
	var template := UV.template(islands)
	template.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	template.save_png(SOURCE + "/uv_template.png")
	var manifest: Array[Dictionary] = []
	for island: Dictionary in islands:
		var rect: Rect2i = island["rect"]
		manifest.append(
			{
				"name": island["name"],
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"rotated": island["rotated"]
			}
		)
	var file := FileAccess.open(SOURCE + "/uv_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	var mesh := PROP.mesh(definition)
	ResourceSaver.save(mesh, ASSET + "/mesh.res")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var painting := Image.load_from_file(args[0])
		UV.prepare_albedo(painting, islands).save_png(ASSET + "/albedo.png")
	print(
		(
			"SKIN_CASE: %d triangles; one surface; 0.70 x 0.593 x 0.656 m"
			% (mesh.get_faces().size() / 3)
		)
	)
	quit()


func _shell(
	faces: Array[Dictionary], id: String, width: float, depth: float, low: float, high: float
) -> void:
	var bevel := 0.035
	var outline: Array[Vector2] = [
		Vector2(-width + bevel, -depth),
		Vector2(width - bevel, -depth),
		Vector2(width, -depth + bevel),
		Vector2(width, depth - bevel),
		Vector2(width - bevel, depth),
		Vector2(-width + bevel, depth),
		Vector2(-width, depth - bevel),
		Vector2(-width, -depth + bevel),
	]
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for point: Vector2 in outline:
		top.append(Vector3(point.x, high, point.y))
		bottom.push_front(Vector3(point.x, low, point.y))
	if id == "LID":
		_face(faces, id + "_TOP", top, id + "_TOP", 1.3)
	if id == "BODY":
		_face(faces, id + "_BOTTOM", bottom, "YELLOW_SMALL", 0.3)
	for index: int in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		var key := id + "_FRONT" if index == 4 else id + "_SIDE"
		if id == "GASKET":
			key = "DARK_HARDWARE"
		_face(
			faces,
			id + "_%d" % index,
			[
				Vector3(a.x, low, a.y),
				Vector3(b.x, low, b.y),
				Vector3(b.x, high, b.y),
				Vector3(a.x, high, a.y)
			],
			key,
			1.4 if index == 4 else 0.8
		)


func _box(faces: Array[Dictionary], id: String, center: Vector3, size: Vector3) -> void:
	var parts: Array[Dictionary] = []
	PROP.add_prism(
		parts,
		id,
		[
			Vector2(-size.z / 2, -size.y / 2),
			Vector2(size.z / 2, -size.y / 2),
			Vector2(size.z / 2, size.y / 2),
			Vector2(-size.z / 2, size.y / 2)
		],
		size.x / 2
	)
	for part: Dictionary in parts:
		var points: PackedVector3Array = part["points"]
		var shifted: Array[Vector3] = []
		for point: Vector3 in points:
			shifted.append(point + center)
		_face(faces, part["name"], shifted, "YELLOW_SMALL" if id == "RIB" else "DARK_HARDWARE", 0.8)


func _handle(faces: Array[Dictionary]) -> void:
	# Continuous U profile, with open hand clearance and ends seated on the shell.
	var profile: Array[Vector2] = [
		Vector2(-0.13, 0.415),
		Vector2(-0.13, 0.32),
		Vector2(0.13, 0.32),
		Vector2(0.13, 0.415),
		Vector2(0.10, 0.415),
		Vector2(0.10, 0.35),
		Vector2(-0.10, 0.35),
		Vector2(-0.10, 0.415)
	]
	var front: Array[Vector3] = []
	var rear: Array[Vector3] = []
	for point: Vector2 in profile:
		front.push_front(Vector3(point.x, point.y, 0.346))
		rear.append(Vector3(point.x, point.y, 0.300))
	_face(faces, "HANDLE_FRONT", front, "DARK_HARDWARE", 0.8)
	_face(faces, "HANDLE_REAR", rear, "DARK_HARDWARE", 0.8)
	for index: int in profile.size():
		var a := profile[index]
		var b := profile[(index + 1) % profile.size()]
		_face(
			faces,
			"HANDLE_%d" % index,
			[
				Vector3(a.x, a.y, 0.300),
				Vector3(b.x, b.y, 0.300),
				Vector3(b.x, b.y, 0.346),
				Vector3(a.x, a.y, 0.346)
			],
			"DARK_HARDWARE",
			0.8
		)


func _face(
	faces: Array[Dictionary], id: String, points: Array[Vector3], reuse: String, weight: float
) -> void:
	for index: int in points.size():
		points[index].y -= 0.025
	PROP.add_face(faces, id, points)
	if id == "BODY_4":
		# Keep the front prawn upright despite the shell's clockwise face basis.
		var coordinates: PackedVector2Array = faces[-1]["uv_m"]
		var extent: Vector2 = faces[-1]["size_m"]
		for index: int in coordinates.size():
			coordinates[index] = extent - coordinates[index]
		faces[-1]["uv_m"] = coordinates
	faces[-1]["reuse_key"] = reuse
	faces[-1]["importance"] = weight
