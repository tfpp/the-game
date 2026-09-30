extends SceneTree
## Build native meshes, UV guides and GLBs. Args: optional model kind and source atlas.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const BOOT := preload("res://features/procedural_rooms/model_tools/car_boot_parts.gd")
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var repack := args.has("--repack")
	args.erase("--repack")
	var kinds: Array[String] = ["crate", "barrel", "car", "wheel"]
	if not args.is_empty():
		kinds = [args[0]]
	for kind: String in kinds:
		var data := PROP.definition(kind)
		var path := "res://assets/procedural_rooms/models/" + kind
		var author := ProjectSettings.globalize_path(
			"res://../docs/design/model-sources/props/" + kind
		)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		DirAccess.make_dir_recursive_absolute(author)
		var faces: Array[Dictionary] = data["islands"]
		var template := UV.template(faces)
		template.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
		template.save_png(author + "/uv_template.png")
		var checker := UV.prepare_albedo(UV.template(faces, true), faces)
		checker.save_png(path + "/uv_checker.png")
		if args.size() > 1:
			var source := Image.load_from_file(args[1])
			assert(source != null and source.get_width() == source.get_height())
			UV.prepare_albedo(source, faces).save_png(path + "/albedo.png")
		elif repack or not FileAccess.file_exists(path + "/albedo.png"):
			_repack_art(data).save_png(path + "/albedo.png")
		var manifest: Dictionary = {
			"kind": kind,
			"layout_version": 2,
			"occupied_fraction": data["occupied_fraction"],
			"atlas_size": 128,
			"padding": 2,
			"pixels_per_metre": data["density"],
			"pivot": "floor_center",
			"islands": []
		}
		for face: Dictionary in faces:
			var rect: Rect2i = face["rect"]
			manifest["islands"].append(
				{
					"name": face["name"],
					"source_face": face["source_face"],
					"rotated": face["rotated"],
					"density_multiplier": face["weight"],
					"rect_px": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
				}
			)
		manifest["face_bindings"] = []
		for face: Dictionary in data["faces"]:
			manifest["face_bindings"].append(
				{
					"face": face["name"],
					"island": face["island"],
					"flip_x": face.get("flip_x", false)
				}
			)
		var file := FileAccess.open(path + "/uv_manifest.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest, "  ") + "\n")
		file.close()
		var mesh := PROP.mesh(data)
		ResourceSaver.save(mesh, path + "/mesh.tres")
		if kind == "car":
			ResourceSaver.save(mesh.create_convex_shape(), path + "/collision.tres")
		var model := Node3D.new()
		model.name = kind.capitalize()
		var visual := MeshInstance3D.new()
		visual.name = "Visual"
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		var texture_path := (
			"res://assets/procedural_rooms/models/car/albedo.png"
			if kind == "wheel"
			else path + "/albedo.png"
		)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.texture_repeat = false
		material.roughness = .95
		material.albedo_texture = ImageTexture.create_from_image(
			Image.load_from_file(ProjectSettings.globalize_path(texture_path))
		)
		visual.material_override = material
		model.add_child(visual)
		visual.owner = model
		if kind == "car":
			var parts := BOOT.meshes()
			for part: String in parts:
				ResourceSaver.save(parts[part], path + "/boot_" + part + ".tres")
			visual.mesh = parts["body"]
			for part: String in ["lid", "interior"]:
				var piece := MeshInstance3D.new()
				piece.name = "BootLid" if part == "lid" else "BootInterior"
				piece.mesh = parts[part]
				piece.material_override = material
				if part == "lid":
					piece.position = BOOT.PIVOT
				model.add_child(piece)
				piece.owner = model
			_add_wheels(model, material)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_scene(model, state) == OK)
		assert(document.write_to_filesystem(state, path + "/" + kind + ".glb") == OK)
		model.free()
		print(
			"PROP_BUILD PASS ",
			kind,
			" density=",
			data["density"],
			" triangles=",
			mesh.get_faces().size() / 3
		)
	quit()


func _add_wheels(model: Node3D, material: Material) -> void:
	var mesh := PROP.mesh(PROP.definition("wheel"))
	for side: int in [-1, 1]:
		for z: float in [-1.25, 1.25]:
			var wheel := MeshInstance3D.new()
			wheel.name = "Wheel%s_%s" % [side, z]
			wheel.mesh = mesh
			wheel.material_override = material
			wheel.position = Vector3(-.69 if side < 0 else .87, .29, z)
			wheel.rotation.z = PI / 2
			model.add_child(wheel)
			wheel.owner = model


func _repack_art(data: Dictionary) -> Image:
	# Resample the retained painting per island; this changes layout, not the artwork.
	var atlas := Image.create(128, 128, false, Image.FORMAT_RGB8)
	atlas.fill(Color("222831"))
	var sources: Dictionary[String, Image] = {}
	var layouts: Dictionary[String, Dictionary] = {}
	for island: Dictionary in data["islands"]:
		var source_face: String = island["source_face"]
		var kind: String = data["kind"]
		if source_face.begins_with("TYRE"):
			kind = "wheel"
		elif source_face.begins_with("BODY"):
			kind = "car"
		if not sources.has(kind):
			var folder := ProjectSettings.globalize_path(
				"res://../docs/design/model-sources/props/" + kind
			)
			sources[kind] = Image.load_from_file(folder + "/generated_albedo_source.png")
			layouts[kind] = JSON.parse_string(
				FileAccess.get_file_as_string(folder + "/painting_layout_v1.json")
			)
		var source: Image = sources[kind]
		var scale := source.get_width() / 128.0
		for old: Dictionary in layouts[kind]["islands"]:
			if old["name"] != source_face:
				continue
			var coordinates: Array = old["rect_px"]
			var region := Rect2i(
				roundi(coordinates[0] * scale),
				roundi(coordinates[1] * scale),
				roundi(coordinates[2] * scale),
				roundi(coordinates[3] * scale)
			)
			var painting := source.get_region(region)
			if island["rotated"]:
				painting.rotate_90(CLOCKWISE)
			var rect: Rect2i = island["rect"]
			painting.resize(rect.size.x, rect.size.y, Image.INTERPOLATE_LANCZOS)
			painting.convert(Image.FORMAT_RGB8)
			atlas.blit_rect(painting, Rect2i(Vector2i.ZERO, painting.get_size()), rect.position)
			break
	return UV.prepare_albedo(atlas, data["islands"])
