extends SceneTree
## Native exports from front, rear and underneath, under real engine lighting.


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1200, 800)
	var stage := Node3D.new()
	root.add_child(stage)
	var sconce := (
		(load("res://features/casino_hub/models/brass_sconce.tscn") as PackedScene).instantiate()
		as Node3D
	)
	stage.add_child(sconce)
	sconce.position = Vector3(-1.8, 1, 0)
	var chandelier := (
		(
			(load("res://features/casino_hub/models/brass_chandelier.tscn") as PackedScene)
			. instantiate()
		)
		as Node3D
	)
	stage.add_child(chandelier)
	chandelier.position = Vector3(0, 2.1, 0)
	var railing := (
		(load("res://features/room_kits/brass_railing.tscn") as PackedScene).instantiate() as Node3D
	)
	stage.add_child(railing)
	railing.position = Vector3(.8, 0, 0)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.4
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("242b32")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("e7d9c3")
	world.environment.ambient_light_energy = .6
	stage.add_child(world)
	var output := OS.get_cmdline_user_args()[0]
	for entry: Array in [
		["front", Vector3(3, 2.8, 7)],
		["rear", Vector3(-3, 2.8, -7)],
		["underside", Vector3(1, -.8, 6)]
	]:
		camera.position = entry[1]
		camera.look_at(Vector3(.35, 1, 0))
		for frame: int in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/native-" + str(entry[0]) + ".png")
	quit()
