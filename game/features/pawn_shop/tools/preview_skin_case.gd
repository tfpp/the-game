extends Node3D
## Render the actual reusable prop from its important construction views.


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		get_tree().quit(1)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().root.size = Vector2i(800, 800)
	var model := preload("res://features/pawn_shop/skin_case.tscn").instantiate()
	add_child(model)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("343d46")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.1
	var views: Dictionary[String, Vector3] = {
		"front-oblique": Vector3(1, 1.1, 1.4),
		"rear-oblique": Vector3(-1, 0.9, -1.4),
		"front": Vector3(0, 0.3, 2),
		"underside": Vector3(1, -1, 1),
	}
	for label: String in views:
		camera.position = views[label]
		camera.look_at(Vector3(0, 0.3, 0))
		for frame: int in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	get_tree().quit()
