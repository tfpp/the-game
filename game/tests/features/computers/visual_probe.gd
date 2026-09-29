extends Node3D
## xvfb-run -a godot --path game --audio-driver Dummy <this scene>


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	var computer := (
		preload("res://features/computers/computer.tscn").instantiate() as ArcadeComputer
	)
	add_child(computer)
	computer.set_process(false)
	computer.ensure_view()
	var view: Node3D = computer._view
	view.set_process(false)
	view.camera.make_current()
	view.display.set_state(ArcadeComputer.initial_state())
	view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().create_timer(1).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/computer-screen.png")
	get_tree().quit()
