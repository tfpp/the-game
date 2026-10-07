extends Node3D
## Actual runtime meshes: -- --avatar-capture=/tmp/chests.png [--chest-view=side|rear].


func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.9
	add_child(camera)
	camera.position = Vector3(0, 0.4, -6)
	camera.look_at(Vector3(0, 0.15, 0))
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
	var view := str(Network.args.get("chest-view", "front"))
	for index: int in 6:
		var model := BlockPlayerModel.new()
		var look := PlayerAppearance.defaults()
		look["skin"] = 3
		look["chest"] = "default" if index == 0 else "full"
		look["hair"] = "crop"
		look["outfit"] = "tactical" if index == 4 else "casual"
		model.set_appearance(look)
		model.set_body_type("penguin" if index == 5 else ("girl" if index in [2, 3] else "default"))
		if index == 3:
			model.set_clothing("shirt:4", "pants:3")
		model.position = Vector3((index % 3 - 1) * 1.25, 1.0 if index < 3 else -1.0, 0)
		model.rotation.y = {"front": -0.35, "side": PI / 2.0, "rear": PI}.get(view, -0.35)
		add_child(model)
		var label := Label3D.new()
		label.text = [
			"Default",
			"Full",
			"Girl + Full",
			"Shirt + Full",
			"Tactical + Full",
			"Penguin (retained)"
		][index]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 24
		label.pixel_size = 0.003
		label.position = model.position + Vector3(0, 0.96, 0)
		add_child(label)
		if index == 4:
			model.animate(0.2, Vector3(0, 0, -6), true, 8)
	if Network.has_flag("character-page"):
		var models: PlayerModels = (
			preload("res://features/player_models/feature.tscn").instantiate()
		)
		add_child(models)
		models.entity.request_action(
			&"appearance",
			{
				"skin": 3,
				"hair": "crop",
				"hair_color": 0,
				"eyes": 0,
				"chest": "full",
				"outfit": "casual"
			}
		)
		var settings: Node = preload("res://features/settings/feature.tscn").instantiate()
		add_child(settings)
		settings.open()
		settings.show_page(models.get_node("ModelPicker"))
		if Network.has_flag("scroll-chest"):
			settings._scroll.scroll_vertical = 360
	for frame: int in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := str(Network.args.get("avatar-capture", ""))
	if not path.is_empty():
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
