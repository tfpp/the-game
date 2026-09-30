extends Node
## Render actual module assemblies. Run with a display and OUTPUT_DIR after --.

const LAB := preload("res://features/procedural_rooms/examples/lab.tscn")
var _camera: Camera3D
var _lab: Node3D
@onready var root: Window = get_tree().root


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		printerr("Use a real renderer and pass OUTPUT_DIR after --")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	root.size = Vector2i(1440, 900)
	_lab = LAB.instantiate() as Node3D
	root.add_child(_lab)
	var player := _lab.get("player") as Player
	player.set_physics_process(false)
	player.set_process(false)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 78
	_lab.add_child(_camera)
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Controls.playing = false
	_lab.set_process(false)
	(_lab.get("_prompt") as Label).visible = false
	for label: Node in _lab.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	var hud := _lab.get("_hud") as Label
	hud.text = (
		"MODULAR SETS / SHARED W03 ATTACHMENTS\n"
		+ "Garage / utility / pump sets / sliding doors / indexed interior faces"
	)
	await _capture(args[0], "door-closed", Vector3(-20, 1.7, 4.3), Vector3(-20, 1.6, 8))
	for door: ProceduralSlidingDoor in get_tree().get_nodes_in_group(&"prototype_doors"):
		door.net_open = true
	await get_tree().create_timer(0.5).timeout
	await _capture(args[0], "garage-set", Vector3(-17, 2.1, 6.7), Vector3(-22.1, 1.1, 3.9))
	await _capture(args[0], "utility-set", Vector3(2.8, 1.8, 6.5), Vector3(-3.1, 1.5, 3.9))
	await _capture(args[0], "pump-set", Vector3(22.5, 1.8, 7), Vector3(17.5, 1.2, 3.8))
	await _capture(args[0], "door-open", Vector3(-20, 1.7, 4.3), Vector3(-20, 1.6, 8))
	await _capture(args[0], "ramp", Vector3(-20.7, 1.8, 6.1), Vector3(-20, 4.8, 31))
	await _capture(args[0], "stairs", Vector3(-0.7, 1.8, 6.2), Vector3(0, 3.8, 16))
	await _capture(args[0], "sewer", Vector3(20.7, 1.7, 6), Vector3(20, 1.3, 21))
	await _capture(args[0], "side-attachment", Vector3(18, 1.8, 23), Vector3(31, 1.5, 22))
	for roof: Node3D in get_tree().get_nodes_in_group(&"lab_roofs"):
		roof.visible = false
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 55
	await _capture(args[0], "overview", Vector3(64, 62, 64), Vector3(1, 0, 20))
	for label: Label3D in get_tree().get_nodes_in_group(&"catalogue_labels"):
		label.visible = true
	_camera.size = 34
	hud.text = (
		"ASSEMBLY GUIDE / SEPARATED MODULES\n"
		+ "Cyan W03 frames mate exactly / door installs once at the joint"
	)
	_camera.global_position = Vector3(2, 28, -17)
	_camera.look_at(Vector3(-20, 0, -38))
	_camera.force_update_transform()
	await get_tree().process_frame
	_guide_overlay()
	await _capture(args[0], "assembly-guide", Vector3(2, 28, -17), Vector3(-20, 0, -38))
	print("SOCKET_CAPTURE PASS: sets, closed/open doors, routes, overview, assembly guide")
	get_tree().quit()


func _capture(folder: String, id: String, from: Vector3, to: Vector3) -> void:
	_camera.global_position = from
	_camera.look_at(to)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(folder.path_join(id + ".png"))
	if error != OK:
		printerr("Cannot save ", id)
		get_tree().quit(1)


func _guide_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	_lab.add_child(canvas)
	for item: Array in [
		["01  GARAGE BAY", Vector3(-20, 4.5, -51)],
		["02  SLIDING DOOR", Vector3(-20, 4.5, -45)],
		["03  HALL CONNECTOR", Vector3(-20, 4.5, -38)],
		["04  PUMP CHAMBER", Vector3(-20, 4.5, -25)]
	]:
		var label := Label.new()
		label.text = item[0]
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color("fff0d4"))
		label.add_theme_color_override("font_outline_color", Color("17202b"))
		label.add_theme_constant_override("outline_size", 6)
		label.position = _camera.unproject_position(item[1]) + Vector2(-100, -24)
		canvas.add_child(label)
	for pair: Array in [
		[Vector3(-20, 0.1, -47), Vector3(-20, 0.1, -43)],
		[Vector3(-20, 0.1, -33), Vector3(-20, 0.1, -29)]
	]:
		var line := Line2D.new()
		line.width = 4
		line.default_color = Color("51dbcf")
		line.points = PackedVector2Array(
			[_camera.unproject_position(pair[0]), _camera.unproject_position(pair[1])]
		)
		canvas.add_child(line)
		var label := Label.new()
		label.text = "W03 = W03"
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color("51dbcf"))
		label.add_theme_constant_override("outline_size", 6)
		label.position = (line.points[0] + line.points[1]) * 0.5 + Vector2(18, 0)
		canvas.add_child(label)
