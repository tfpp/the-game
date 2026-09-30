extends SceneTree

const Model := preload("res://features/procedural_rooms/model_tools/elevator_model.gd")
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const ASSETS := "res://assets/procedural_rooms/models/elevator/"
const AUTHOR := "res://../docs/design/model-sources/elevator/"


func _initialize() -> void:
	var data := Model.definition()
	var faces: Array[Dictionary] = data["islands"]
	var guide := UV.template(faces)
	guide.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	guide.save_png(ProjectSettings.globalize_path(AUTHOR + "uv_template.png"))
	UV.prepare_albedo(UV.template(faces, true), faces).save_png(ASSETS + "uv_checker.png")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var source := Image.load_from_file(args[0])
		assert(source != null)
		UV.prepare_albedo(source, faces).save_png(ASSETS + "albedo.png")
	var manifest := {
		"atlas_size": 128,
		"padding": 2,
		"density": data["density"],
		"occupied_fraction": data["occupied_fraction"],
		"islands": [],
		"parts": {},
		"face_bindings": []
	}
	for face: Dictionary in faces:
		var rect: Rect2i = face["rect"]
		manifest["islands"].append(
			{
				"name": face["name"],
				"rotated": face["rotated"],
				"rect_px": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
			}
		)
	for id: String in ["cab", "frame", "leaf", "button"]:
		var mesh := Model.part(data, id)
		ResourceSaver.save(mesh, ASSETS + id + ".tres")
		manifest["parts"][id] = {
			"triangles": mesh.get_faces().size() / 3, "bounds": str(mesh.get_aabb())
		}
		print(id, " triangles=", mesh.get_faces().size() / 3)
	for face: Dictionary in data["faces"]:
		manifest["face_bindings"].append({"part": face["part"], "island": face["island"]})
	var file := FileAccess.open(ASSETS + "uv_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	if FileAccess.file_exists(ASSETS + "albedo.png"):
		_export()
	print("ELEVATOR_BUILD PASS density=", data["density"], " occupancy=", data["occupied_fraction"])
	quit()


func _export() -> void:
	var root := Node3D.new()
	root.name = "ServiceElevator"
	var material := StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = false
	material.roughness = .88
	material.albedo_texture = ImageTexture.create_from_image(
		Image.load_from_file(ASSETS + "albedo.png")
	)
	var parts: Array[Dictionary] = [
		{"part": "cab", "name": "Cab", "at": Vector3.ZERO},
		{"part": "frame", "name": "DoorFrame", "at": Vector3(0, 0, 1.35)},
		{"part": "leaf", "name": "LeftLeaf", "at": Vector3(-.75, 0, 1.35)},
		{"part": "leaf", "name": "RightLeaf", "at": Vector3(.75, 0, 1.35)}
	]
	for part: Dictionary in parts:
		var mesh := MeshInstance3D.new()
		mesh.mesh = load(ASSETS + part["part"] + ".tres")
		mesh.material_override = material
		mesh.name = part["name"]
		mesh.position = part["at"]
		root.add_child(mesh)
		mesh.owner = root
	var panel := load("res://features/procedural_rooms/elevator_panel.tscn").instantiate() as Node3D
	panel.position = Vector3(1.45, 1.62, -.65)
	root.add_child(panel)
	panel.owner = root
	for child: Node in panel.find_children("*", "", true, false):
		child.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(root, state) == OK)
	assert(document.write_to_filesystem(state, ASSETS + "elevator.glb") == OK)
	root.free()
