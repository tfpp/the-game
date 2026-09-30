extends Node3D
## Card dealer close-up: run with -- --dealer-capture=/tmp/dealer.png [--dealer-back].

const DEALER := preload("res://features/casino_patrons/card_dealer.tscn")


func _ready() -> void:
	var back := "--dealer-back" in OS.get_cmdline_user_args()
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.9, 1.6, -1.6 if back else 1.9)
	camera.look_at(Vector3(0, 1.1, 0.2))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7cde2")
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var table := CSGBox3D.new()
	table.size = Vector3(1.6, 0.94, 0.8)
	table.position = Vector3(0, 0.47, 0.75)
	add_child(table)
	add_child(DEALER.instantiate())
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dealer-capture="):
			await get_tree().create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.split("=", true, 1)[1])
			get_tree().quit()
