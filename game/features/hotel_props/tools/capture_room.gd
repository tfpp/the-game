extends Node3D
## Render the actual room with Godot. Sources/previews remain outside game assets.

const FEATURE := preload("res://features/hotel_props/feature.tscn")


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child(feature)
	(feature.get_node("Room") as StreamedRoom).load_room(60000)
	var camera := Camera3D.new()
	camera.fov = 78
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0.12, 0.1, 0.08)
	camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	camera.environment.ambient_light_color = Color(1, 0.9, 0.76)
	camera.environment.ambient_light_energy = 0.65
	add_child(camera)
	camera.make_current()
	get_tree().root.size = Vector2i(1280, 720)
	var output := ProjectSettings.globalize_path("res://../docs/design/previews/hotel-props")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var views := [
		["overview", Vector3(0, 2.5, 7), Vector3(0, 1.3, -3)],
		["guest-suite", Vector3(-2, 1.8, -0.5), Vector3(-6.5, 0.9, -4.7)],
		["lounge", Vector3(1.5, 1.8, -0.5), Vector3(6, 0.9, -4.5)],
		["reception", Vector3(0.8, 1.8, 6), Vector3(5.7, 1, 3.6)],
		["room-service", Vector3(-2, 1.8, 6), Vector3(-7.5, 0.9, 4.5)],
	]
	for view: Array in views:
		camera.position = (view[1] as Vector3) + Vector3(0, 0, -1800)
		camera.look_at((view[2] as Vector3) + Vector3(0, 0, -1800))
		for frame: int in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(
			(
				get_viewport().get_texture().get_image().save_png(
					output.path_join(str(view[0]) + ".png")
				)
				== OK
			)
		)
	print("HOTEL_ROOM_CAPTURE: five gameplay-scale Godot views")
	get_tree().quit()
