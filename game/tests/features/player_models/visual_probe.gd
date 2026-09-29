extends Node3D
## Reproducible avatar contact sheet: run this scene with -- --avatar-capture=/tmp/file.png.


func _ready() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.65
	add_child(camera)
	camera.position = Vector3(0, 0.7, -5)
	camera.look_at(Vector3(0, 0, 0))
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
	for index: int in 4:
		var model := BlockPlayerModel.new()
		model.set_appearance(
			{
				"skin": index * 2,
				"hair": ["crop", "swept", "long", "bald"][index],
				"hair_color": index,
				"eyes": index,
				"outfit": "tactical" if index in [1, 3] else "casual"
			}
		)
		model.set_body_type("girl" if index == 2 else "default")
		model.set_clothing(
			["shirt:0", "shirt:1", "shirt:4", "shirt:6"][index],
			["pants:3", "pants:1", "pants:9", "pants:6"][index]
		)
		model.position.x = (float(index) - 1.5) * 1.0
		model.rotation.y = -0.25 if index < 3 else -0.8
		add_child(model)
		if index == 3:
			model.animate(0.15, Vector3(0, 0, -6), true, 8)
		elif index == 1:
			var item: Node3D = (
				preload("res://features/holdables/items/shotgun_view.tscn").instantiate()
			)
			model.add_child(item)
			HeldItemPose.align_grip(item)
			item.position += Vector3(0.15, 0.08, -0.32)
			model.animate(0.1, Vector3.ZERO, true, 8, 0, true, true)
			model.human.reach_grip(true, model.to_global(Vector3(0.205, 0.04, -0.265)))
			var support := item.get_node("SupportGrip") as Node3D
			model.human.reach_grip(false, support.to_global(Vector3(-0.055, -0.04, 0.055)))
	if Network.has_flag("character-page"):
		var models := preload("res://features/player_models/feature.tscn").instantiate()
		add_child(models)
		var settings: Node = preload("res://features/settings/feature.tscn").instantiate()
		add_child(settings)
		settings.open()
		settings.show_page(models.get_node("ModelPicker"))
	for frame: int in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := str(Network.args.get("avatar-capture", ""))
	if not path.is_empty():
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
