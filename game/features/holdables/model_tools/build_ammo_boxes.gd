extends SceneTree
## Six compact carton meshes sharing an explicitly mapped 128px packaging atlas.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const ASSET := "res://assets/holdables/models/ammo_boxes"
const SOURCE := "res://../docs/design/model-sources/ammo-boxes"
const BOXES := {
	"pistol": Vector3(.12, .045, .075),
	"smg": Vector3(.16, .055, .08),
	"m4a4": Vector3(.17, .065, .10),
	"ak47": Vector3(.18, .07, .11),
	"shotgun": Vector3(.13, .11, .10),
	"awp": Vector3(.20, .07, .11),
}


func _initialize() -> void:
	var template := Image.create(128, 128, false, Image.FORMAT_RGB8)
	template.fill(Color("202630"))
	var islands: Array[Dictionary] = []
	var manifest: Array[Dictionary] = []
	var row := 0
	for weapon: String in BOXES:
		var rects := {
			"FRONT": Rect2i(2, 2 + row * 20, 64, 16),
			"TOP": Rect2i(70, 2 + row * 20, 32, 16),
			"SIDE": Rect2i(106, 2 + row * 20, 20, 16)
		}
		for role: String in rects:
			var rect: Rect2i = rects[role]
			template.fill_rect(rect, Color.from_hsv(float(row) / 6, .4, .7))
			islands.append({"name": weapon + "_" + role, "rect": rect, "rotated": false})
			manifest.append(
				{
					"name": weapon + "_" + role,
					"rect_px": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
				}
			)
		_build(weapon, BOXES[weapon], rects)
		row += 1
	var guide := template.duplicate()
	guide.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	guide.save_png(SOURCE + "/uv_template.png")
	var file := FileAccess.open(SOURCE + "/uv_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		UV.prepare_albedo(Image.load_from_file(args[0]), islands).save_png(ASSET + "/albedo.png")
	elif not FileAccess.file_exists(ASSET + "/albedo.png"):
		UV.prepare_albedo(template, islands).save_png(ASSET + "/albedo.png")
	if args.size() > 1:
		var panel := Image.load_from_file(args[1])
		panel.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		panel.save_png("res://assets/pawn_shop/ui/trade_panel.png")
	quit()


func _build(weapon: String, size: Vector3, rects: Dictionary) -> void:
	var faces: Array[Dictionary] = []
	var z := size.z * .5
	var y := size.y * .5
	var cut := .002
	PROP.add_prism(
		faces,
		"CARTON",
		[
			Vector2(-z + cut, -y),
			Vector2(z - cut, -y),
			Vector2(z, -y + cut),
			Vector2(z, y - cut),
			Vector2(z - cut, y),
			Vector2(-z + cut, y),
			Vector2(-z, y - cut),
			Vector2(-z, -y + cut)
		],
		size.x * .5
	)
	# Connected folded lid lip, proud of the front by one millimetre.
	PROP.add_prism(
		faces,
		"LIP",
		[
			Vector2(z, y - .009),
			Vector2(z + .001, y - .009),
			Vector2(z + .001, y - .003),
			Vector2(z, y - .003)
		],
		size.x * .48
	)
	for face: Dictionary in faces:
		var normal: Vector3 = face["normal"]
		var role := "FRONT" if absf(normal.z) > .95 else "TOP" if normal.y > .95 else "SIDE"
		if str(face["name"]).begins_with("LIP"):
			role = "SIDE"
		var rect: Rect2i = rects[role]
		var extent: Vector2 = face["size_m"]
		var projected: PackedVector2Array = face["uv_m"]
		for index: int in projected.size():
			projected[index] = (
				Vector2(.5, .5) + projected[index] / extent * Vector2(rect.size - Vector2i.ONE)
			)
		face["uv_m"] = projected
		face["size_m"] = Vector2(rect.size)
		face["flip_x"] = role == "FRONT" and normal.z < 0.0
		face["rect"] = rect
		face["rotated"] = false
		face["weight"] = 1.0
	var mesh := PROP.mesh({"faces": faces, "density": 1.0})
	# Mirror the rear's vertical UV after triangulation so label orientation
	# cannot change the polygon winding used to build its physical face.
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var rear_rect: Rect2i = rects["FRONT"]
	for index: int in coordinates.size():
		if normals[index].z < -.95:
			coordinates[index].y = (
				float(2 * rear_rect.position.y + rear_rect.size.y) / 128.0 - coordinates[index].y
			)
	arrays[Mesh.ARRAY_TEX_UV] = coordinates
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_validate(mesh)
	ResourceSaver.save(mesh, ASSET + "/" + weapon + ".res")
	var scene := Node3D.new()
	scene.name = "AmmoBox"
	var model := MeshInstance3D.new()
	model.name = "Carton"
	model.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = (
		load(ASSET + "/albedo.png")
		if FileAccess.file_exists(ASSET + "/albedo.png.import")
		else null
	)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = 1.0
	model.material_override = material
	scene.add_child(model)
	model.owner = scene
	var grip := Marker3D.new()
	grip.name = "Grip"
	scene.add_child(grip)
	grip.owner = scene
	var packed := PackedScene.new()
	packed.pack(scene)
	ResourceSaver.save(packed, "res://features/holdables/items/ammo_" + weapon + "_view.tscn")
	scene.free()
	print(weapon, " AMMO BOX: ", mesh.get_faces().size() / 3, " triangles, size=", size)


func _validate(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index: int in vertices.size():
		assert(vertices[index].is_finite() and coordinates[index].is_finite())
		assert(absf(normals[index].length() - 1.0) < .001)
		assert(
			(
				coordinates[index].x >= 0
				and coordinates[index].y >= 0
				and coordinates[index].x <= 1
				and coordinates[index].y <= 1
			)
		)
	var triangles := mesh.get_faces()
	for index: int in range(0, triangles.size(), 3):
		assert(
			(
				(
					(triangles[index + 1] - triangles[index])
					. cross(triangles[index + 2] - triangles[index])
					. length()
				)
				> .00000001
			)
		)
