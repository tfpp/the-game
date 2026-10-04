extends Node3D


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var output := ProjectSettings.globalize_path("res://../docs/design/previews/ammo-boxes")
	DirAccess.make_dir_recursive_absolute(output)
	get_window().size = Vector2i(900, 650)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("273440")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = .7
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .29
	camera.current = true
	add_child(camera)
	for weapon: String in ItemCatalog.AMMO_VIEWS:
		var model := ItemCatalog.AMMO_VIEWS[weapon].instantiate() as Node3D
		add_child(model)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_scene(model, state) == OK)
		assert(
			(
				document.write_to_filesystem(
					state,
					ProjectSettings.globalize_path(
						"res://../docs/design/model-sources/ammo-boxes/" + weapon + ".glb"
					)
				)
				== OK
			)
		)
		var views := {
			"front": Vector3(.5, .3, 1),
			"rear": Vector3(-.5, .3, -1),
			"underside": Vector3(.5, -.6, 1),
			"top": Vector3(.1, 1, .3)
		}
		for label: String in views:
			camera.position = views[label]
			camera.look_at(Vector3.ZERO)
			for frame: int in 5:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				output.path_join(weapon + "-" + label + ".png")
			)
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit()
