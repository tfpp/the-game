extends SceneTree
## Rebuild geometry/UV guides; optional painting path updates the diffuse atlas.

const MODEL := preload("res://features/holdables/model_tools/m1911_model.gd")
const ANIMATIONS := preload("res://features/holdables/model_tools/m1911_animations.gd")
const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const ASSET := "res://assets/holdables/models/m1911"
const SOURCE := "res://../docs/design/model-sources/m1911"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSET))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SOURCE))
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://features/holdables/animations")
	)
	ResourceSaver.save(ANIMATIONS.library(), "res://features/holdables/animations/m1911.tres")
	if "--animations-only" in OS.get_cmdline_user_args():
		quit()
		return
	var definition := MODEL.definition()
	var faces: Array[Dictionary] = definition["faces"]
	var islands: Array[Dictionary] = definition["islands"]
	var guide := UV.template(islands)
	guide.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	guide.save_png(SOURCE + "/uv_template.png")
	var manifest: Dictionary = {
		"atlas": 128, "padding": 2, "density": definition["density"], "islands": [], "parts": []
	}
	var mask := Image.create(128, 128, false, Image.FORMAT_RGB8)
	mask.fill(Color.BLACK)
	for island: Dictionary in islands:
		var rect: Rect2i = island["rect"]
		var key: String = island["name"]
		var paintable := key.begins_with("FRAME") or key.begins_with("SLIDE")
		manifest["islands"].append(
			{
				"name": key,
				"rect_px": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"rotated": island["rotated"],
				"paintable": paintable
			}
		)
		if paintable:
			mask.fill_rect(rect, Color.WHITE)
	UV.prepare_albedo(mask, islands).save_png(ASSET + "/skin_mask.png")
	var checker := UV.prepare_albedo(UV.template(islands, true), islands)
	checker.save_png(ASSET + "/uv_checker.png")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var painting := (
			ProjectSettings.globalize_path("res://../" + args[0])
			if args[0].is_relative_path()
			else args[0]
		)
		UV.prepare_albedo(Image.load_from_file(painting), islands).save_png(ASSET + "/albedo.png")
	elif not FileAccess.file_exists(ASSET + "/albedo.png"):
		checker.save_png(ASSET + "/albedo.png")
	var triangle_count := 0
	for part: String in MODEL.PIVOTS:
		var part_faces: Array[Dictionary] = []
		for face: Dictionary in faces:
			if face["part"] == part:
				part_faces.append(face)
		var mesh := PROP.mesh({"faces": part_faces, "density": definition["density"]})
		_validate(mesh)
		ResourceSaver.save(mesh, ASSET + "/" + part.to_snake_case() + ".res")
		triangle_count += mesh.get_faces().size() / 3
		manifest["parts"].append(
			{
				"name": part,
				"triangles": mesh.get_faces().size() / 3,
				"pivot": str(MODEL.PIVOTS[part]),
				"bounds": str(mesh.get_aabb())
			}
		)
	manifest["triangles"] = triangle_count
	var file := FileAccess.open(SOURCE + "/uv_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	print(
		"M1911 BUILD: ",
		triangle_count,
		" triangles, five moving mesh parts, named padded 128px atlas; validation passed"
	)
	quit()


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
