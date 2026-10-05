extends SceneTree
## Native roadside scenery and original quiet workshop sound loops.


func _initialize() -> void:
	var source := load("res://features/starter_room/alley_structure.tscn") as PackedScene
	var instance := source.instantiate()
	var library := (instance.get_node("Ground") as GridMap).mesh_library.duplicate() as MeshLibrary
	var sidewalk := BoxMesh.new()
	sidewalk.size = Vector3(1, .12, 1)
	sidewalk.material = load("res://features/procedural_rooms/materials/garage_floor.tres")
	library.create_item(3)
	library.set_item_mesh(3, sidewalk)
	library.set_item_mesh_transform(3, Transform3D(Basis.IDENTITY, Vector3(.5, -.06, .5)))
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(.72, .63, .34)
	var dash := BoxMesh.new()
	dash.size = Vector3(1, .012, .14)
	dash.material = paint
	library.create_item(4)
	library.set_item_mesh(4, dash)
	library.set_item_mesh_transform(4, Transform3D(Basis.IDENTITY, Vector3(.5, .01, .5)))
	var yard := Node3D.new()
	yard.name = "RoadView"
	var floor_grid := _grid(yard, library, "Ground")
	var back := _grid(yard, library, "Facades")
	var markings := _grid(yard, library, "RoadMarkings")
	for x: int in range(-16, 23):
		for z: int in range(-11, 5):
			floor_grid.set_cell_item(Vector3i(x, 0, z), 0 if z >= -8 and z < 2 else 3)
		for y: int in 10:
			back.set_cell_item(Vector3i(x, y, -11), 2)
		if posmod(x, 6) < 3:
			markings.set_cell_item(Vector3i(x, 0, -3), 4)
	var packed := PackedScene.new()
	packed.pack(yard)
	ResourceSaver.save(packed, "res://features/starter_room/road_structure.tscn")
	yard.free()
	instance.free()
	_sound("workshop_hum", 4.0, 0)
	_sound("workshop_radio", 12.0, 1)
	_sound("roller_motor", 2.0, 2)
	quit()


func _grid(parent: Node3D, library: MeshLibrary, title: String) -> GridMap:
	var grid := GridMap.new()
	grid.name = title
	grid.mesh_library = library
	grid.cell_size = Vector3.ONE
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	parent.add_child(grid)
	grid.owner = parent
	return grid


func _sound(title: String, seconds: float, kind: int) -> void:
	const RATE := 22050
	var data := PackedByteArray()
	data.resize(int(seconds * RATE) * 2)
	var melody := [220.0, 261.6256, 293.6648, 329.6276, 293.6648, 261.6256]
	for i: int in int(seconds * RATE):
		var t := float(i) / RATE
		var sample := sin(TAU * 100 * t) * .11 + sin(TAU * 200 * t) * .025
		if kind == 1:
			var beat := fmod(t, .5)
			var note: float = melody[int(t / .5) % melody.size()]
			sample = (sin(TAU * note * t) + .25 * sin(TAU * note * 2 * t)) * exp(-beat * 7) * .09
			sample += sin(TAU * 55 * t) * .025
		elif kind == 2:
			sample = sin(TAU * 70 * t) * .13 + sin(TAU * 140 * t) * .045
			sample *= .8 + .2 * sin(TAU * 8 * t)
		var fade := minf(1.0, minf(t, seconds - t) / .015)
		data.encode_s16(i * 2, int(clampf(sample * fade, -1, 1) * 32767))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = RATE
	audio.data = data
	audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	audio.loop_end = data.size() / 2
	ResourceSaver.save(
		audio, "res://assets/starter_room/" + title + ".res", ResourceSaver.FLAG_COMPRESS
	)
