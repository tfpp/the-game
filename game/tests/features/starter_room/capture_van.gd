extends Node
## Render the exported native scene, including views exposed by opening its leaves.

var _model: Node3D
var _camera: Camera3D
var _output := "res://../docs/design/previews/armoured-operations-van"


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	get_tree().root.size = Vector2i(960, 640)
	var world := Node3D.new()
	add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("242b30")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c0cfcc")
	environment.environment.ambient_light_energy = .7
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	world.add_child(light)
	_model = preload("res://features/starter_room/van_model.tscn").instantiate()
	world.add_child(_model)
	_camera = Camera3D.new()
	_camera.fov = 55
	world.add_child(_camera)
	_camera.current = true
	await _save("front", Vector3(-4.5, 3, 6), Vector3(0, 1, 0))
	await _save("driver-door-closed", Vector3(-3.5, 1.7, 1), Vector3(-1, 1.5, .85))
	await _save("passenger-door-closed", Vector3(3.5, 1.7, 1), Vector3(1, 1.5, .85))
	await _save("rear", Vector3(-4, 2.8, -5.7), Vector3(0, 1, -.5))
	await _save("undercarriage", Vector3(-3.8, -1.1, 4), Vector3(0, .4, 0))
	(_model.get_node("DriverDoor/Hinge") as Node3D).rotation.y = deg_to_rad(100)
	(_model.get_node("PassengerDoor/Hinge") as Node3D).rotation.y = deg_to_rad(-100)
	(_model.get_node("RearLeftDoor/Hinge") as Node3D).rotation.y = deg_to_rad(100)
	(_model.get_node("RearRightDoor/Hinge") as Node3D).rotation.y = deg_to_rad(-100)
	await _save("doors-open", Vector3(-4.5, 3, -5.7), Vector3(0, 1, -.5))
	await _save("cargo-interior", Vector3(-.1, 1.65, -4), Vector3(0, 1.3, -.2))
	await _save("driver-door-open", Vector3(-4.1, 2.6, 3.4), Vector3(-1.5, 1.45, 1.1))
	await _save("cab-interior", Vector3(-2.9, 2, 1), Vector3(0, 1.2, .8))
	get_tree().quit()


func _save(title: String, at: Vector3, target: Vector3) -> void:
	_camera.position = at
	_camera.look_at(target)
	for i: int in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(_output.path_join(title + ".png"))
