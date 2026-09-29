extends Node3D
## Close-up of the same hand topology in open and gripping poses.


func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.39
	add_child(camera)
	camera.position = Vector3(0.04, -0.32, -0.7)
	camera.look_at(Vector3(0, -0.32, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -150, 0)
	light.light_energy = 1.2
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7cde2")
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	if Network.has_flag("first-person-hands"):
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		var mount := Node3D.new()
		add_child(mount)
		mount.position = HeldItemPose.FIRST_PERSON_OFFSET
		var item: Node3D = preload("res://features/holdables/items/shotgun_view.tscn").instantiate()
		mount.add_child(item)
		HeldItemPose.align_grip(item)
		var arms := HeldArms.new()
		mount.add_child(arms)
		arms.pose(
			arms.to_local(Vector3(0.32, -0.36, 0.10)),
			arms.to_local(Vector3(-0.32, -0.36, 0.10)),
			item.get_node("SupportGrip") as Node3D
		)
	else:
		_build_hands()
	for frame: int in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := str(Network.args.get("avatar-capture", ""))
	if not path.is_empty():
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()


func _build_hands() -> void:
	for index: int in 2:
		var human := SkinnedHuman.new()
		add_child(human)
		human.position.x = (-0.08 if index == 0 else 0.08) - 0.316
		var close_shader := Shader.new()
		close_shader.code = SkinnedHuman.SURFACE.code.replace(
			"void fragment() {", "void fragment() { if (rest_xy.y > -0.244) { discard; }"
		)
		human.material.shader = close_shader
		human.material.set_shader_parameter("arms_only", true)
		human.material.set_shader_parameter("hide_left_arm", true)
		human.material.set_shader_parameter("skin_tint", PlayerSkin.TONES[2])
		human.set_finger_curl(true, 0.0 if index == 0 else 0.9)
