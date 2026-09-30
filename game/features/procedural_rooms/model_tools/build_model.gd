extends SceneTree
## Rebuild the sample model and its UV contract; optional argument is generated artwork.

const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const FONT := preload("res://features/procedural_rooms/tools/build_dev_textures.gd").FONT
const DIRECTORY := "res://assets/procedural_rooms/models/service_cabinet"
const AUTHORING := "res://../docs/design/model-sources/service-cabinet"


func _initialize() -> void:
	var faces := UV.cabinet_faces()
	var errors := UV.validate(faces)
	if not errors.is_empty():
		printerr(errors)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUTHORING))
	var checker := UV.prepare_albedo(UV.template(faces, true), faces)
	assert(checker.save_png(DIRECTORY + "/uv_checker.png") == OK)
	var guide := UV.template(faces)
	guide.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	for face: Dictionary in faces:
		var rect: Rect2i = face["rect"]
		var at := rect.position * 8 + Vector2i(12, 12)
		_label(guide, face["name"], at)
		for index: int in rect.size.x * 8:
			guide.set_pixel(rect.position.x * 8 + index, rect.position.y * 8, Color.WHITE)
			guide.set_pixel(rect.position.x * 8 + index, rect.end.y * 8 - 1, Color.WHITE)
		for index: int in rect.size.y * 8:
			guide.set_pixel(rect.position.x * 8, rect.position.y * 8 + index, Color.WHITE)
			guide.set_pixel(rect.end.x * 8 - 1, rect.position.y * 8 + index, Color.WHITE)
	assert(guide.save_png(ProjectSettings.globalize_path(AUTHORING + "/uv_template.png")) == OK)
	var manifest: Dictionary = {
		"model": "service_cabinet",
		"atlas_size": 128,
		"generation_size": 1024,
		"padding": 2,
		"pixels_per_metre": 30,
		"front_normal": [1, 0, 0],
		"pivot": "floor_center",
		"bounds_m": [0.6, 2.5, 1.0],
		"islands": []
	}
	for face: Dictionary in faces:
		var rect: Rect2i = face["rect"]
		manifest["islands"].append(
			{
				"name": face["name"],
				"rect_px": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"uv_top_left": [rect.position.x / 128.0, rect.position.y / 128.0],
				"normal": [face["normal"].x, face["normal"].y, face["normal"].z]
			}
		)
	var file := FileAccess.open(DIRECTORY + "/uv_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	var mesh := UV.mesh(faces)
	assert(ResourceSaver.save(mesh, DIRECTORY + "/mesh.tres") == OK)
	var args := OS.get_cmdline_user_args()
	var albedo_path := DIRECTORY + "/albedo.png"
	if args.size() == 1:
		var source := Image.load_from_file(ProjectSettings.globalize_path(args[0]))
		if source == null or source.get_width() != source.get_height():
			printerr("Artwork must be a square atlas matching uv_template.png")
			quit(1)
			return
		assert(UV.prepare_albedo(source, faces).save_png(albedo_path) == OK)
	elif not FileAccess.file_exists(albedo_path):
		assert(checker.save_png(albedo_path) == OK)
	var model := Node3D.new()
	model.name = "ServiceCabinet"
	var visual := MeshInstance3D.new()
	visual.name = "Cabinet"
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	var albedo := Image.load_from_file(ProjectSettings.globalize_path(albedo_path))
	if albedo.get_width() > 128 or albedo.get_height() > 128:
		printerr("Runtime textures must be 128x128 or smaller")
		model.free()
		quit(1)
		return
	material.albedo_texture = ImageTexture.create_from_image(albedo)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = false
	material.roughness = 0.9
	visual.material_override = material
	model.add_child(visual)
	visual.owner = model
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(model, state) == OK)
	assert(document.write_to_filesystem(state, DIRECTORY + "/service_cabinet.glb") == OK)
	model.free()
	print("MODEL_BUILD PASS: geometry + six named UV islands + template + manifest + GLB")
	quit()


func _label(image: Image, text: String, at: Vector2i) -> void:
	for character: int in text.length():
		var bits: String = FONT.get(text[character], FONT[" "])
		for row: int in 5:
			for column: int in 3:
				if bits[row * 3 + column] == "1":
					image.fill_rect(
						Rect2i(at + Vector2i(character * 16 + column * 4, row * 4), Vector2i(4, 4)),
						Color.WHITE
					)
