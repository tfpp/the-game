extends Node3D
## Renders actual catalog views from the front and underside, never concept art.


func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.65
	add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("241b1c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("f0dfc0")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var index := 0
	for id: String in VipRules.DRINK_ITEMS.values():
		var view := ItemCatalog.create_view(id)
		add_child(view)
		view.position.x = (index - 1) * 0.23
		view.position.y = ItemCatalog.find(id).ground_clearance
		var label := Label3D.new()
		label.text = ItemCatalog.find(id).display_name
		label.font_size = 32
		label.pixel_size = 0.0005
		label.position = Vector3(view.position.x, -0.04, 0)
		add_child(label)
		index += 1
	camera.position = Vector3(0.15, 0.36, 0.95)
	camera.look_at(Vector3(0, 0.09, 0))
	await _capture("/tmp/vip-drinks.png")
	camera.position = Vector3(-0.15, -0.3, -0.95)
	camera.look_at(Vector3(0, 0.09, 0))
	await _capture("/tmp/vip-drinks-underside.png")
	get_tree().quit()


func _capture(path: String) -> void:
	for frame: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
