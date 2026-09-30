extends SceneTree
## Builds all meshes and guides; args: optional kind and square painted atlas.

const MODELS := preload("res://features/holdables/model_tools/loot_models.gd")
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const MESH := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const ASSET_PATHS := {
	"dumpster": "res://assets/slum_alley/models/dumpster",
	"scrap": "res://assets/holdables/models/scrap",
	"wallet": "res://assets/holdables/models/wallet"
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var kinds: Array[String] = ["dumpster", "scrap", "wallet"]
	if not args.is_empty():
		kinds = [args[0]]
	for kind: String in kinds:
		var data := MODELS.definition(kind)
		var path: String = ASSET_PATHS[kind]
		var author := ProjectSettings.globalize_path(
			"res://../docs/design/model-sources/loot/" + kind
		)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		DirAccess.make_dir_recursive_absolute(author)
		var islands: Array[Dictionary] = data["islands"]
		var guide := UV.template(islands)
		guide.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
		guide.save_png(author + "/uv_template.png")
		var checker := UV.prepare_albedo(UV.template(islands, true), islands)
		checker.save_png(path + "/uv_checker.png")
		if args.size() == 2:
			var source := Image.load_from_file(args[1])
			assert(source != null and source.get_width() == source.get_height())
			UV.prepare_albedo(source, islands).save_png(path + "/albedo.png")
		elif not FileAccess.file_exists(path + "/albedo.png"):
			checker.save_png(path + "/albedo.png")
		var mesh := MESH.mesh(data)
		ResourceSaver.save(mesh, path + "/mesh.tres")
		if kind == "dumpster":
			var parts := MODELS.dumpster_parts(data)
			for part: String in parts:
				ResourceSaver.save(parts[part], path + "/" + part + ".tres")
		_export(path, mesh, kind)
		var manifest: Dictionary = {
			"model": kind,
			"atlas_size": 128,
			"padding": 2,
			"pixels_per_metre": data["density"],
			"occupied_fraction": data["occupied_fraction"],
			"islands": []
		}
		for island: Dictionary in islands:
			var rect: Rect2i = island["rect"]
			manifest["islands"].append(
				{
					"name": island["name"],
					"rect_px": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
					"rotated": island["rotated"]
				}
			)
		var file := FileAccess.open(path + "/uv_manifest.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest, "  ") + "\n")
		file.close()
		print(
			"LOOT_MODEL_BUILD PASS ",
			kind,
			" density=",
			data["density"],
			" used=",
			data["occupied_fraction"]
		)
	quit()


func _export(path: String, mesh: ArrayMesh, kind: String) -> void:
	var model := Node3D.new()
	model.name = kind.capitalize()
	var visual := MeshInstance3D.new()
	visual.name = "Model"
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(
		Image.load_from_file(ProjectSettings.globalize_path(path + "/albedo.png"))
	)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = false
	material.roughness = .95
	visual.material_override = material
	model.add_child(visual)
	visual.owner = model
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(model, state) == OK)
	assert(document.write_to_filesystem(state, path + "/" + kind + ".glb") == OK)
	model.free()
