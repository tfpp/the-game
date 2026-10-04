extends SceneTree
# gdlint: disable=max-line-length
## Build native four-part views, UV paint guides and editable animation libraries.

const MODEL := preload("res://features/holdables/model_tools/rifle_model.gd")
const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const TRACK := preload("res://features/holdables/model_tools/m1911_animations.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for kind: String in ["mp5", "m4a4", "ak47"]:
		if "--animations-only" in args:
			ResourceSaver.save(
				_animations(kind), "res://features/holdables/animations/" + kind + ".tres"
			)
			continue
		_build(kind, args[1] if args.size() > 1 and args[0] == kind else "")
	quit()


func _build(kind: String, painting: String) -> void:
	if not painting.is_empty() and painting.is_relative_path():
		painting = ProjectSettings.globalize_path("res://../" + painting)
	var asset := "res://assets/holdables/models/" + kind
	var source := "res://../docs/design/model-sources/" + kind
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(asset))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source))
	var data := MODEL.definition(kind)
	var faces: Array[Dictionary] = data["faces"]
	var islands: Array[Dictionary] = data["islands"]
	var template := UV.template(islands)
	template.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	template.save_png(source + "/uv_template.png")
	var manifest: Dictionary = {"atlas": 128, "padding": 2, "islands": [], "parts": []}
	var mask := Image.create(128, 128, false, Image.FORMAT_RGB8)
	mask.fill(Color.BLACK)
	for island: Dictionary in islands:
		var key: String = island["name"]
		var rect: Rect2i = island["rect"]
		var paintable := (
			key.begins_with("RECEIVER")
			or key.begins_with("MAGAZINE")
			or key.begins_with("HANDGUARD")
			or key.begins_with("STOCK")
		)
		if kind == "ak47" and (key.begins_with("HANDGUARD") or key.begins_with("STOCK")):
			paintable = false
		if paintable:
			mask.fill_rect(rect, Color.WHITE)
		manifest["islands"].append(
			{
				"name": key,
				"rect_px": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"rotated": island["rotated"],
				"paintable": paintable
			}
		)
	UV.prepare_albedo(mask, islands).save_png(asset + "/skin_mask.png")
	UV.prepare_albedo(UV.template(islands, true), islands).save_png(asset + "/uv_checker.png")
	if not painting.is_empty():
		UV.prepare_albedo(Image.load_from_file(painting), islands).save_png(asset + "/albedo.png")
	elif not FileAccess.file_exists(asset + "/albedo.png"):
		UV.prepare_albedo(UV.template(islands, true), islands).save_png(asset + "/albedo.png")
	var total := 0
	for part: String in MODEL.PARTS:
		var selected: Array[Dictionary] = []
		for face: Dictionary in faces:
			if face["part"] == part:
				selected.append(face)
		var mesh := PROP.mesh({"faces": selected, "density": data["density"]})
		_validate(mesh)
		ResourceSaver.save(mesh, asset + "/" + part.to_snake_case() + ".res")
		var count := mesh.get_faces().size() / 3
		total += count
		manifest["parts"].append({"name": part, "triangles": count})
	manifest["triangles"] = total
	var file := FileAccess.open(source + "/uv_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	ResourceSaver.save(_animations(kind), "res://features/holdables/animations/" + kind + ".tres")
	_scene(kind, asset)
	print(kind.to_upper(), " BUILD: ", total, " triangles, four moving parts, padded 128px atlas")


static func _animations(kind: String) -> AnimationLibrary:
	var result := AnimationLibrary.new()
	var fire := Animation.new()
	fire.length = .12
	TRACK._track(
		fire,
		"Pose/Bolt:position",
		[0.0, .018, .065, .11],
		[Vector3.ZERO, Vector3(0, 0, .035), Vector3(0, 0, .035), Vector3.ZERO]
	)
	result.add_animation(&"fire", fire)
	var reload := Animation.new()
	reload.length = 2.25
	TRACK._track(
		reload,
		"Pose:position",
		[0.0, .25, 1.85, 2.25],
		[Vector3.ZERO, Vector3(-.10, .15, -.04), Vector3(-.10, .15, -.04), Vector3.ZERO]
	)
	TRACK._track(
		reload,
		"Pose:rotation",
		[0.0, .25, 1.8, 2.25],
		[Vector3.ZERO, Vector3(.08, 0, -.30), Vector3(.08, 0, -.30), Vector3.ZERO]
	)
	TRACK._track(
		reload,
		"Pose/Magazine:position",
		[0.0, .25, .60, .95, 1.45, 1.70, 2.25],
		[
			Vector3.ZERO,
			Vector3.ZERO,
			Vector3(-.035, -.12, .02),
			Vector3(-.055, -.16, .025),
			Vector3(-.025, -.085, .01),
			Vector3.ZERO,
			Vector3.ZERO
		]
	)
	var support := _support(kind)
	TRACK._track(
		reload,
		"Pose/SupportGrip:position",
		[0.0, .25, .6, .95, 1.45, 1.7, 1.9, 2.25],
		[
			support,
			Vector3(.015, -.04, -.08),
			Vector3(.005, -.12, -.08),
			Vector3(-.015, -.16, -.09),
			Vector3(.012, -.085, -.08),
			Vector3(.015, -.04, -.08),
			Vector3(-.025, .07, -.22) if kind == "mp5" else Vector3(.04, .07, -.05),
			support
		]
	)
	TRACK._track(
		reload,
		"Pose/ChargingHandle:position",
		[0.0, 1.72, 1.92, 2.08, 2.25],
		[Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, .075), Vector3.ZERO, Vector3.ZERO]
	)
	TRACK._track(
		reload,
		"Pose/Bolt:position",
		[0.0, 1.72, 1.92, 2.08, 2.25],
		[Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, .06), Vector3.ZERO, Vector3.ZERO]
	)
	result.add_animation(&"reload", reload)
	var hold := Quaternion.IDENTITY
	var grasp := TRACK.magazine_hand_rotation()
	TRACK._rotation_track(
		reload,
		[0.0, .25, .45, 1.45, 1.7, 1.85, 2.08, 2.25],
		[hold, hold, grasp, grasp, hold, grasp, grasp, hold]
	)
	var reset := Animation.new()
	reset.length = .01
	for path: String in [
		"Pose:position",
		"Pose:rotation",
		"Pose/Bolt:position",
		"Pose/Magazine:position",
		"Pose/ChargingHandle:position"
	]:
		TRACK._track(reset, path, [0.0], [Vector3.ZERO])
	TRACK._track(reset, "Pose/SupportGrip:position", [0.0], [support])
	TRACK._rotation_track(reset, [0.0], [hold])
	result.add_animation(&"RESET", reset)
	return result


static func _support(kind: String) -> Vector3:
	return Vector3(-.018, .025, -.225 if kind == "mp5" else -.255)


static func _scene(kind: String, asset: String) -> void:
	var id := "smg" if kind == "mp5" else kind
	var content := "[gd_scene format=3]\n\n"
	for part: String in MODEL.PARTS:
		content += (
			'[ext_resource type="ArrayMesh" path="%s/%s.res" id="%s"]\n'
			% [asset, part.to_snake_case(), part]
		)
	content += '[ext_resource type="Texture2D" path="%s/albedo.png" id="paint"]\n' % asset
	content += '[ext_resource type="Texture2D" path="%s/skin_mask.png" id="mask"]\n' % asset
	content += '[ext_resource type="Script" path="res://features/holdables/rifle_view.gd" id="script"]\n'
	content += (
		'[ext_resource type="AnimationLibrary" path="res://features/holdables/animations/%s.tres" id="animations"]\n\n'
		% kind
	)
	content += '[sub_resource type="StandardMaterial3D" id="material"]\nalbedo_texture = ExtResource("paint")\ntexture_filter = 2\nroughness = 0.9\nspecular_mode = 2\n\n'
	content += (
		'[node name="RifleView" type="Node3D"]\nscript = ExtResource("script")\nweapon_id = "%s"\n\n'
		% id
	)
	content += (
		'[node name="Grip" type="Marker3D" parent="."]\n\n[node name="SupportGrip" type="Marker3D" parent="."]\nposition = %s\n\n'
		% str(_support(kind)).replace("(", "Vector3(")
	)
	var muzzle := (
		Vector3(0, .052, -.34)
		if kind == "mp5"
		else Vector3(0, .068, -.53) if kind == "m4a4" else Vector3(0, .061, -.518)
	)
	content += (
		'[node name="Muzzle" type="Marker3D" parent="."]\nposition = %s\n\n'
		% str(muzzle).replace("(", "Vector3(")
	)
	content += (
		'[node name="Pose" type="Node3D" parent="."]\n\n[node name="RightGrip" type="Marker3D" parent="Pose"]\n\n[node name="SupportGrip" type="Marker3D" parent="Pose"]\nposition = %s\n\n'
		% str(_support(kind)).replace("(", "Vector3(")
	)
	for part: String in MODEL.PARTS:
		content += (
			'[node name="%s" type="MeshInstance3D" parent="Pose"]\nmesh = ExtResource("%s")\nmaterial_override = SubResource("material")\nmetadata/skin_mask = ExtResource("mask")\n\n'
			% [part, part]
		)
	content += '[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\nlibraries = {\n&"": ExtResource("animations")\n}\n'
	var file := FileAccess.open(
		"res://features/holdables/items/" + id + "_view.tscn", FileAccess.WRITE
	)
	file.store_string(content)
	file.close()


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
