extends SceneTree
## Render the real reusable gameplay machine and its moving lever in Godot.


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1200, 1000)
	var stage := Node3D.new()
	root.add_child(stage)
	var machine := (
		(load("res://features/slot_machine/machine.tscn") as PackedScene).instantiate() as Node3D
	)
	stage.add_child(machine)
	machine.set_process(false)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.8
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-35, -35, 0)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("242a2d")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("eadfcb")
	world.environment.ambient_light_energy = .6
	stage.add_child(world)
	var output := OS.get_cmdline_user_args()[0]
	for shot: Array in [
		["straight", Vector3(0, 1.5, 7), Vector3(0, 1.5, 0), 3.5],
		["front", Vector3(3.7, 2.8, 6), Vector3(0, 1.35, 0), 3.8],
		["rear", Vector3(-3.7, 2.8, -6), Vector3(0, 1.35, 0), 3.8],
		["underside", Vector3(2, -1, 5), Vector3(0, 1.2, 0), 3.8],
		["hardware", Vector3(3, 1.8, 3), Vector3(.8, 1.15, .3), 1.7],
		["spinning", Vector3(3.7, 2.8, 6), Vector3(0, 1.35, 0), 3.8],
		["winner", Vector3(2.8, 2.5, 6), Vector3(0, 1.5, 0), 3.8]
	]:
		camera.position = shot[1]
		camera.size = shot[3]
		camera.look_at(shot[2])
		if shot[0] == "spinning":
			machine.state = {
				"spin": 1,
				"spinning": true,
				"stopped": 0,
				"reels": [0, 1, 2],
				"won": false,
				"payout": 0,
				"operator": "Preview",
				"message": ""
			}
		if shot[0] == "winner":
			var reels: Array[int] = [0, 0, 0]
			machine._begin_spin(1, "Preview", reels, 3000)
			machine._advance(3.1)
		for frame: int in 15 if shot[0] == "winner" else 30:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + str(shot[0]) + ".png")
	# Inspect the repeated model at its actual casino placement and local lighting.
	machine.visible = false
	world.queue_free()
	light.queue_free()
	await process_frame
	var room := (
		(load("res://features/casino_hub/casino_gridmap.tscn") as PackedScene).instantiate()
		as Node3D
	)
	stage.add_child(room)
	var bank := (load("res://features/slot_machine/feature.tscn") as PackedScene).instantiate()
	stage.add_child(bank)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = Vector3(2.8, .9, -5.5)
	camera.look_at(Vector3(7.4, .35, -6))
	camera.current = true
	for frame: int in 180:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/casino.png")
	quit()
