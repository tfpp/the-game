extends Node3D
## Renders the band on its own: run with a window (not --headless), e.g.
## godot res://tests/features/mariachi_band/band_probe.tscn -- --band-capture=/tmp/band.png
## Optional: --band-camera=x,y,z --band-target=x,y,z (band space; it faces -Z),
## --band-time=seconds into the song to pose.

const BAND := preload("res://features/mariachi_band/feature.tscn")


func _ready() -> void:
	var camera_at := Vector3(1.6, 1.9, -5.2)
	var target := Vector3(0, 1.1, 0)
	var capture := ""
	var clock := -1.0
	for arg: String in OS.get_cmdline_user_args():
		var value := arg.split("=", true, 1)[-1]
		if arg.begins_with("--band-capture="):
			capture = value
		elif arg.begins_with("--band-camera="):
			camera_at = _vector(value)
		elif arg.begins_with("--band-target="):
			target = _vector(value)
		elif arg.begins_with("--band-time="):
			clock = float(value)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7cde2")
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 150, 0)
	add_child(light)
	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(12, 0.2, 12)
	floor_box.position.y = -0.1
	add_child(floor_box)
	var band := BAND.instantiate() as Node3D
	band.transform = Transform3D.IDENTITY
	add_child(band)
	if clock >= 0.0:
		(band.get_node("Audio") as AudioStreamPlayer3D).stop()
		band.set("_clock", clock)
	var camera := Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.position = camera_at
	camera.look_at(target)
	if capture.is_empty():
		return
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture)
	get_tree().quit()


static func _vector(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
