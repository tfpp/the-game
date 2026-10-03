extends SceneTree
## Native, deterministic garage/van export. Optional argument: approved paint source.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const ASSETS := "res://assets/starter_room/"
const AUTHOR := "res://../docs/design/model-sources/operations-van/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSETS))
	var faces: Array[Dictionary] = []
	# +Z is the bonnet. Wheel arches cut into one continuous cargo shell.
	PROP.add_prism(
		faces,
		"VAN",
		[
			Vector2(-2.5, .55),
			Vector2(-2, .55),
			Vector2(-1.95, .82),
			Vector2(-1.6, .96),
			Vector2(-1.25, .82),
			Vector2(-1.2, .55),
			Vector2(1.2, .55),
			Vector2(1.25, .82),
			Vector2(1.6, .96),
			Vector2(1.95, .82),
			Vector2(2, .55),
			Vector2(2.5, .55),
			Vector2(2.5, 1.2),
			Vector2(1.65, 1.35),
			Vector2(1.1, 2.25),
			Vector2(-2.3, 2.25),
			Vector2(-2.5, 2.05)
		],
		1.0
	)
	for face: Dictionary in faces:
		if face["name"] == "VAN_16":
			# Rear projection originally points upward; keep rear door paint upright.
			var coordinates: PackedVector2Array = face["uv_m"]
			var extent: Vector2 = face["size_m"]
			for i: int in coordinates.size():
				coordinates[i].y = extent.y - coordinates[i].y
			face["uv_m"] = coordinates
		if face["name"] == "VAN_RIGHT":
			face["reuse_key"] = "VAN_LEFT"
			face["flip_x"] = true
		if face["name"] == "VAN_0" or face["name"] == "VAN_6":
			face["importance"] = .25
	var wheel: Array[Dictionary] = []
	PROP.add_cylinder(wheel, "TYRE", .38, .22)
	for x: float in [-1.1, .88]:
		for z: float in [-1.6, 1.6]:
			for source: Dictionary in wheel:
				var face := source.duplicate(true)
				var transform := Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(x, .38, z))
				face["points"] = transform * (face["points"] as PackedVector3Array)
				face["normal"] = transform.basis * (face["normal"] as Vector3)
				faces.append(face)
	var data := PROP.pack_faces(faces, 40)
	var islands: Array[Dictionary] = data["islands"]
	var template := UV.template(islands)
	template.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	template.save_png(AUTHOR + "uv-template.png")
	var manifest: Array[Dictionary] = []
	for island: Dictionary in islands:
		manifest.append(
			{"name": island["name"], "rect": str(island["rect"]), "rotated": island["rotated"]}
		)
	var file := FileAccess.open(AUTHOR + "islands.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		UV.prepare_albedo(Image.load_from_file(args[0]), islands).save_png(ASSETS + "van.png")
	var mesh := PROP.mesh(data)
	# Rear UV projection is mirrored vertically. Restore clockwise triangle winding
	# after the helper triangulates that mirrored polygon without changing its paint.
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).dot(normals[a]) > 0:
			indices[i + 1] = c
			indices[i + 2] = b
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ResourceSaver.save(mesh, ASSETS + "van.res")
	print("Van triangles: ", mesh.surface_get_array_index_len(0) / 3)
	_build_room()
	_build_shutter()
	_build_audio()
	quit()


func _build_room() -> void:
	var source := load("res://features/casino_hub/gridmap/casino_tiles.tres") as MeshLibrary
	var library := MeshLibrary.new()
	for id: int in [0, 1]:
		library.create_item(id)
		library.set_item_name(id, "ConcreteFloor" if id == 0 else "ConcreteWall")
		var mesh := source.get_item_mesh(id).duplicate() as PrimitiveMesh
		mesh.material = load(
			(
				"res://features/procedural_rooms/materials/garage_floor.tres"
				if id == 0
				else "res://features/procedural_rooms/materials/garage_wall.tres"
			)
		)
		library.set_item_mesh(id, mesh)
		library.set_item_mesh_transform(id, source.get_item_mesh_transform(id))
		library.set_item_shapes(id, source.get_item_shapes(id))
	ResourceSaver.save(library, "res://features/starter_room/garage_tiles.tres")
	var root := Node3D.new()
	root.name = "GarageInterior"
	var grid := GridMap.new()
	grid.name = "FloorCeiling"
	grid.mesh_library = library
	grid.cell_size = Vector3(1, .25, 1)
	grid.cell_center_y = false
	root.add_child(grid)
	grid.owner = root
	for x: int in range(-8, 8):
		for z: int in range(-9, 9):
			grid.set_cell_item(Vector3i(x, 0, z), 0)
			grid.set_cell_item(Vector3i(x, 20, z), 0)
	var walls := GridMap.new()
	walls.name = "Walls"
	walls.mesh_library = library
	walls.cell_size = grid.cell_size
	walls.cell_center_y = false
	root.add_child(walls)
	walls.owner = root
	var side_walls := walls.duplicate() as GridMap
	side_walls.name = "SideWalls"
	root.add_child(side_walls)
	side_walls.owner = root
	for y: int in [0, 10]:
		for x: int in range(-8, 8):
			walls.set_cell_item(Vector3i(x, y, -9), 1)
			walls.set_cell_item(
				Vector3i(x, y, 8), 1, walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
			)
		for z: int in range(-9, 9):
			side_walls.set_cell_item(
				Vector3i(-8, y, z),
				1,
				walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
			)
			side_walls.set_cell_item(
				Vector3i(7, y, z),
				1,
				walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
			)
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, "res://features/starter_room/structure.tscn")
	root.free()


func _build_shutter() -> void:
	var faces: Array[Dictionary] = []
	for i: int in 14:
		var slat: Array[Dictionary] = []
		PROP.add_prism(
			slat,
			"SLAT",
			[
				Vector2(-.04, 0),
				Vector2(.04, 0),
				Vector2(.07, .1),
				Vector2(.04, .22),
				Vector2(-.04, .22)
			],
			3.0
		)
		for face: Dictionary in slat:
			face["points"] = (
				Transform3D(Basis.IDENTITY, Vector3(0, i * .24, 0))
				* (face["points"] as PackedVector3Array)
			)
			faces.append(face)
	ResourceSaver.save(PROP.mesh(PROP.pack_faces(faces, 24)), ASSETS + "shutter.res")


func _build_audio() -> void:
	# Original deterministic PCM: starter churn, ignition, acceleration and road rumble.
	var rate := 22050
	var pcm := PackedByteArray()
	pcm.resize(rate * 2 * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 414
	var phase := 0.0
	var rumble := 0.0
	for i: int in rate * 2:
		var t := float(i) / rate
		var frequency := 28.0 if t < .55 else lerpf(45, 115, clampf((t - .55) / 1.45, 0, 1))
		phase += TAU * frequency / rate
		rumble = lerpf(rumble, rng.randf_range(-1, 1), .08)
		var pulse := .5 + .5 * sin(TAU * 12 * t) if t < .55 else 1.0
		var envelope := minf(t / .04, 1.0) * clampf((2.0 - t) / .35, 0, 1)
		var sample := envelope * (.22 * sin(phase) + .10 * sin(phase * 2) + .08 * rumble) * pulse
		pcm.encode_s16(i * 2, int(sample * 32767))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = rate
	audio.data = pcm
	audio.save_to_wav(ASSETS + "van_departure.wav")
