extends Node3D
## Visual fixture: --plasma-capture=/tmp/plasma.png [--plasma-hands]


func _ready() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.0
	add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("1b202c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("bcc7dc")
	world.environment.ambient_light_energy = 0.5
	add_child(world)
	var mount := Node3D.new()
	add_child(mount)
	var model := preload("res://features/gun_machine/double_barrel_plasma.tscn").instantiate()
	mount.add_child(model)
	if Network.has_flag("plasma-hands"):
		mount.position = GunView.PLASMA_FIRST_PERSON_OFFSET
		var arms := HeldArms.new()
		mount.add_child(arms)
		arms.pose(
			arms.to_local(Vector3(0.32, -0.36, 0.10)),
			arms.to_local(Vector3(-0.32, -0.36, 0.10)),
			model.get_node("SupportGrip") as Node3D
		)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.25
		camera.position = Vector3(1.1, 0.75, -1.4)
		camera.look_at(Vector3(0, 0.07, -0.24))
	for frame: int in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := str(Network.args.get("plasma-capture", ""))
	if not path.is_empty():
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
