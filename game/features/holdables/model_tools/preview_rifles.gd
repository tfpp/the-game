extends Node3D
## Actual native mesh/atlas review, including open bolt and magazine withdrawal.


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		get_tree().quit(1)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().root.size = Vector2i(1100, 800)
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
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.0
	var scenes: Dictionary[String,PackedScene] = {
		"mp5": preload("res://features/holdables/items/smg_view.tscn"),
		"m4a4": preload("res://features/holdables/items/m4a4_view.tscn"),
		"ak47": preload("res://features/holdables/items/ak47_view.tscn")
	}
	for kind: String in scenes:
		var model := scenes[kind].instantiate() as Node3D
		add_child(model)
		var document := GLTFDocument.new()
		var gltf := GLTFState.new()
		assert(document.append_from_scene(model, gltf) == OK)
		document.write_to_filesystem(
			gltf,
			ProjectSettings.globalize_path(
				"res://../docs/design/model-sources/" + kind + "/" + kind + ".glb"
			)
		)
		var views: Dictionary[String,Vector3] = {
			"left": Vector3(-1, .06, -.08),
			"right": Vector3(1, .06, -.08),
			"rear": Vector3(-.7, .40, .8),
			"muzzle": Vector3(.7, .4, -.8),
			"underside": Vector3(.7, -.4, -.6)
		}
		for label: String in views:
			camera.position = views[label]
			camera.look_at(Vector3(0, .015, -.08))
			await _save(output, kind + "-" + label)
		var animation := model.get_node("AnimationPlayer") as AnimationPlayer
		for clip: String in ["fire", "reload"]:
			camera.position = Vector3(.65, .4, .7)
			camera.look_at(Vector3(0, .01, -.1))
			animation.play(clip)
			animation.seek(.035 if clip == "fire" else .95, true)
			animation.pause()
			await _save(output, kind + "-" + clip)
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _save(output: String, label: String) -> void:
	for frame: int in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
