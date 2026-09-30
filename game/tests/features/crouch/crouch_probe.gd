extends Node3D
## Side-view crouch contact sheet: standing, crouched, crouch walking, and a
## crouched penguin, over a floor line at the capsule bottom. Run with
## -- --avatar-capture=/tmp/crouch.png.

const FEET := -0.9144


func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	add_child(camera)
	camera.position = Vector3(6, 0.0, 1.4)
	camera.look_at(Vector3(0, -0.2, 1.4))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 60, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7cde2")
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 0.02, 6)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(0, FEET - 0.01, 1.4)
	add_child(floor_mesh)
	var models: Array[BlockPlayerModel] = []
	for index: int in 5:
		var model := BlockPlayerModel.new()
		model.set_body_type("penguin" if index >= 3 else "default")
		model.position.z = float(index) * 1.0
		add_child(model)
		models.append(model)
	await get_tree().process_frame
	var phase := float(Network.args.get("crouch-phase", "0.2"))
	for step: int in 60:
		for index: int in 5:
			var model := models[index]
			model.crouched = index in [1, 2, 3]
			var moving := index == 2
			model.animate(1.0 / 60.0, Vector3(0, 0, -2.5) if moving else Vector3.ZERO, true, 8.128)
		models[2]._phase = phase
	for frame: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := str(Network.args.get("avatar-capture", ""))
	if not path.is_empty():
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
