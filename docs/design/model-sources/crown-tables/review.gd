extends SceneTree
## Render actual runtime exports, including underside and native UV checker.
const DIRECTORY := "res://../docs/design/previews/crown-games/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("24201f")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dfd4c7")
	settings.ambient_light_energy = .65
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.1
	world.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 45
	world.add_child(camera)
	camera.make_current()
	var visual := MeshInstance3D.new()
	world.add_child(visual)
	for kind: String in ["poker", "blackjack", "baccarat", "video_poker"]:
		visual.mesh = load(
			(
				"res://assets/table_games/models/"
				+ ("video_poker_machine.res" if kind == "video_poker" else kind + "_table.res")
			)
		)
		for view: String in ["front", "back", "side", "underside", "checker"]:
			visual.material_override = null
			var eye := Vector3(2.6, 2.5, 3.2)
			if view == "back":
				eye = Vector3(-2.6, 2, -3.2)
			elif view == "side":
				eye = Vector3(3.9, 1.2, 0)
			elif view == "underside":
				eye = Vector3(2.3, -.8, 2.8)
			elif view == "checker":
				var material := StandardMaterial3D.new()
				material.albedo_texture = ImageTexture.create_from_image(
					Image.load_from_file(
						"res://../docs/design/model-sources/crown-tables/card-tables-checker.png"
					)
				)
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				visual.material_override = material
			camera.position = eye
			camera.look_at(Vector3(0, .5, 0))
			for i: int in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(DIRECTORY + kind + "-" + view + ".png")
	world.free()
	quit()
