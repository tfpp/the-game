extends Node

const LEVEL := preload("res://features/procedural_rooms/examples/world_level.tscn")
const Layout := preload("res://features/procedural_rooms/world_layout.gd")
var _camera: Camera3D
var _level: Node3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	get_tree().root.size = Vector2i(1440, 900)
	_level = LEVEL.instantiate() as Node3D
	get_tree().root.add_child(_level)
	var player := _level.get("player") as Player
	player.set_physics_process(false)
	player.set_process(false)
	_level.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Controls.playing = false
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 80
	_level.add_child(_camera)
	_camera.current = true
	await get_tree().create_timer(0.5).timeout
	await _capture(
		args[0],
		"elevator-location",
		Vector3(0, 17.7, 6),
		Vector3(0, 18, -3),
		"B1 / ELEVATOR AT THE FRONT OF THE GARAGE / ENTER THE CAB, PRESS E"
	)
	await _capture(
		args[0],
		"ground-and-sky",
		Vector3(50, 20, 65),
		Vector3(0, 9, 20),
		"GROUNDED WORLD / ASPHALT SURROUND / CONCRETE DECKS / OVERCAST SKY"
	)
	await _capture(
		args[0],
		"elevator-arrival",
		Vector3(0, 17.7, -5),
		Vector3(0, 17.5, 9),
		"B1 / ELEVATOR ARRIVAL → GARAGE"
	)
	await _capture(
		args[0],
		"garage-atrium",
		Vector3(-8, 17.7, 9),
		Vector3(14, 12.5, 27),
		"FIVE FLOORS / OPEN CENTRAL SHAFT / PARKING BAYS"
	)
	await _capture(
		args[0],
		"ramp",
		Vector3(-25, 13.7, 6),
		Vector3(-25, 17.4, 32),
		"WEST RAMP / B2 → B1 / SEAMLESS LEVEL LANDINGS"
	)
	await _capture(
		args[0],
		"stairs",
		Vector3(25, 13.7, 6),
		Vector3(25, 16.6, 18),
		"EAST STAIRS / B2 → B1 / ALTERNATE ROUTE"
	)
	await _capture(
		args[0],
		"elevator-controls",
		Vector3(-1.8, 17.7, -1),
		Vector3(0.4, 17.7, -4),
		"ELEVATOR / E TO TRAVEL / FIVE FLOOR STOPS"
	)
	await _capture(
		args[0],
		"sewer",
		Vector3(0.7, 1.7, 40),
		Vector3(0, 1.3, 53),
		"B5 / SEWER ACCESS → PUMP STATION"
	)
	await _capture(
		args[0],
		"pump-room",
		Vector3(2.7, 1.7, 58),
		Vector3(-2, 1.5, 54),
		"LOWEST FLOOR / PUMP STATION"
	)
	for roof: Node3D in get_tree().get_nodes_in_group(&"lab_roofs"):
		roof.visible = false
	await _capture(
		args[0],
		"garage-seed-a",
		Vector3(-8, 24, 8),
		Vector3(-15, 16, 23),
		"GARAGE POPULATION / SEED 73021 / ALLOWED ZONES KEEP WALKING LANES CLEAR"
	)
	Layout.repopulate(_level.get("level") as Node3D, 73022)
	await _capture(
		args[0],
		"garage-seed-b",
		Vector3(-8, 24, 8),
		Vector3(-15, 16, 23),
		"GARAGE POPULATION / SEED 73022 / SAME ROOM, DIFFERENT SETS AND ORIENTATIONS"
	)
	for label: Label3D in _level.find_children("*", "Label3D", true, false):
		label.visible = false
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 76
	await _capture(
		args[0],
		"world-overview",
		Vector3(76, 36, 77),
		Vector3(0, 9, 20),
		"WORLD CUTAWAY / FRONT: ELEVATOR / LEFT: RAMPS / RIGHT: STAIRS / REAR: SEWER"
	)
	print("WORLD_CAPTURE PASS")
	get_tree().quit()


func _capture(folder: String, id: String, from: Vector3, to: Vector3, caption: String) -> void:
	(_level.get("_hud") as Label).text = caption
	_camera.global_position = from
	_camera.look_at(to)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var error := get_tree().root.get_texture().get_image().save_png(folder.path_join(id + ".png"))
	assert(error == OK)
