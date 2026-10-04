extends Node3D

const DOLL := preload("res://features/pawn_shop/creepy_doll_passer.tscn")
const SHOP := preload("res://features/pawn_shop/interior.tscn")


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var output := ProjectSettings.globalize_path("res://../docs/design/previews/creepy-doll")
	DirAccess.make_dir_recursive_absolute(output)
	get_window().size = Vector2i(1000, 720)
	add_child(SHOP.instantiate())
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("273440")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = .6
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	add_child(light)
	var doll := DOLL.instantiate() as CreepyDollPasser
	add_child(doll)
	doll.set_process(false)
	doll.net_phase = 14.0
	doll._present(0.0)
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	var views := {"pavement": Vector3(-10, 1.6, 33.8), "shop-window": Vector3(-12, 1.5, 27.5)}
	for title: String in views:
		camera.position = views[title]
		camera.look_at(doll.visual.position + Vector3(0, .7, 0))
		for frame: int in 15:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(title + ".png"))
	for child: Node in get_children():
		for descendant: Node in child.find_children("*", "AudioStreamPlayer3D", true, false):
			(descendant as AudioStreamPlayer3D).stop()
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(.1).timeout
	get_tree().quit()
