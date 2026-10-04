extends Node3D
## Render native geometry, painted skin and animation key poses from all sides.


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		get_tree().quit(1)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().root.size = Vector2i(1000, 800)
	var model := preload("res://features/holdables/items/pistol_view.tscn").instantiate() as Node3D
	add_child(model)
	var document := GLTFDocument.new()
	var gltf := GLTFState.new()
	if document.append_from_scene(model, gltf) == OK:
		document.write_to_filesystem(
			gltf,
			ProjectSettings.globalize_path("res://../docs/design/model-sources/m1911/m1911.glb")
		)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("343d46")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .8
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.light_energy = 1.0
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .34
	var target := Vector3(0, .01, -.055)
	var views: Dictionary[String, Vector3] = {
		"left": Vector3(-.6, .04, -.055),
		"right": Vector3(.6, .04, -.055),
		"muzzle-oblique": Vector3(.4, .28, -.5),
		"rear-oblique": Vector3(-.4, .2, .4),
		"underside": Vector3(.3, -.4, -.3)
	}
	for label: String in views:
		camera.position = views[label]
		camera.look_at(target)
		await _save(output, label)
	camera.position = Vector3(-.4, .2, .4)
	camera.look_at(target)
	var animation := model.get_node("AnimationPlayer") as AnimationPlayer
	for clip: String in ["fire", "reload"]:
		camera.size = .34 if clip == "fire" else .55
		camera.look_at(target if clip == "fire" else Vector3(-.08, .06, -.09))
		animation.play(clip)
		animation.seek(.04 if clip == "fire" else .74, true)
		animation.pause()
		await _save(output, clip)
	animation.play(&"RESET")
	animation.advance(0.0)
	animation.stop()
	camera.size = .34
	camera.look_at(target)
	PrawnSkinAppearance.apply(model, "crown")
	await _save(output, "skin")
	get_tree().quit()


func _save(output: String, label: String) -> void:
	for frame: int in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
