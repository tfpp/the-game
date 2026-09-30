extends Node3D

const LAYOUT := preload("res://features/casino_wing/layout.gd")
var _camera: Camera3D
var _wing: Node3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	get_tree().root.size = Vector2i(1440, 900)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("211b19")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("ffdfb0")
	environment.environment.ambient_light_energy = .85
	add_child(environment)
	_wing = LAYOUT.build(self)
	_camera = Camera3D.new()
	_camera.fov = 80
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.current = true
	await _capture(args[0], "gaming-hall", "GamingHall", Vector3(0, 1.7, 1), Vector3(-5, 1.3, 13))
	await _capture(args[0], "card-room", "CardRoom", Vector3(0, 1.7, 1), Vector3(-4.5, 1, 6))
	await _capture(args[0], "bar-lounge", "BarLounge", Vector3(0, 1.7, 1), Vector3(-6, 1.3, 6))
	await _capture(
		args[0], "vault-stairs", "VaultStairs", Vector3(0, 5.7, 10.5), Vector3(0, 1.4, 1)
	)
	await _capture(args[0], "vault-door", "VaultLobby", Vector3(0, 1.7, 11), Vector3(0, 1.7, 16))
	var door := _wing.get_node("VaultDoor") as ProceduralSlidingDoor
	door.net_open = true
	await _capture(args[0], "vault-interior", "Vault", Vector3(0, 1.7, 1), Vector3(-5, 1.1, 11))
	for roof: Node3D in get_tree().get_nodes_in_group(&"lab_roofs"):
		roof.visible = false
	for sign: Label3D in _wing.find_children("*", "Label3D", true, false):
		sign.visible = false
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 140
	_camera.position = Vector3(80, 100, 80)
	_camera.look_at(Vector3(0, 0, 60))
	await _save(args[0], "connected-layout")
	print("CASINO_WING_CAPTURE PASS")
	get_tree().quit()


func _capture(folder: String, id: String, room: String, from: Vector3, to: Vector3) -> void:
	var module := _wing.get_node(room) as Node3D
	_camera.global_position = module.to_global(from)
	_camera.look_at(module.to_global(to))
	await _save(folder, id)


func _save(folder: String, id: String) -> void:
	await get_tree().create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	assert(get_tree().root.get_texture().get_image().save_png(folder.path_join(id + ".png")) == OK)
