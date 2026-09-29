extends SceneTree
## Capture the built hotel corners and both elevation connections with a real renderer.
## godot --path game -s res://tests/features/world_builder/visual_probe.gd -- OUTPUT_DIR

const Layout := preload("res://features/world_builder/layout.gd")
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://features/hotel_annex/hotel.json")
	)
	var layout := Layout.compile(spec)
	assert(layout["errors"].is_empty(), str(layout["errors"]))
	var feature := (
		(load("res://features/hotel_annex/feature.tscn") as PackedScene).instantiate() as Node3D
	)
	root.add_child(feature)
	var world := feature.get_node("Hotel") as Node3D
	world.call("load_room", 60000)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8394a3")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.5
	world.add_child(environment)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.current = true
	root.size = Vector2i(1280, 720)
	await process_frame
	await _capture(args[0], "corner", Vector3(1.4, 1.7, 3), Vector3(0, 1.7, 0))
	await _capture(args[0], "room", Vector3(9, 2.0, 7), Vector3(2, 2, 2))
	for flight: Dictionary in layout["flights"]:
		print("FLIGHT: ", flight)
		var axis: Vector2 = flight["axis"]
		var start: Vector2 = flight["start"]
		var from := start - axis * 1.5
		var to := start + axis * (float(flight["length"]) + 1.5)
		await _capture(
			args[0],
			flight["kind"] + str(int(flight["high"] * 10)),
			Vector3(from.x, flight["low"] + 1.65, from.y),
			Vector3(to.x, flight["high"] + 1.0, to.y)
		)
	var door := world.get_node("RoomDoors/UpperStudyDoor") as Node3D
	await _capture(
		args[0],
		"locked-door",
		door.position + Vector3(-3, 1.65, 0),
		door.position + Vector3(0, 1.4, 0)
	)
	door.set("net_state", 1)
	await _capture(
		args[0],
		"open-door",
		door.position + Vector3(-3, 1.65, 0),
		door.position + Vector3(1, 1.4, 0)
	)
	await _capture(args[0], "study-key", Vector3(-16, 1.6, 10.5), Vector3(-16, 1.1, 13))
	quit()


func _capture(folder: String, label: String, from: Vector3, to: Vector3) -> void:
	_camera.position = from
	_camera.look_at((_camera.get_parent() as Node3D).to_global(to))
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
	assert(error == OK)
