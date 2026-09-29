extends SceneTree
## Native render QA for examples/hotel.scn. Pass SCENE and an existing output folder.

const PREVIEW := preload("res://features/world_builder/preview.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not DirAccess.dir_exists_absolute(args[1]):
		printerr("Usage: -- SCENE OUTPUT_DIRECTORY (render with a display, not --headless)")
		quit(1)
		return
	var preview := PREVIEW.instantiate()
	root.add_child(preview)
	await process_frame
	var camera := root.get_camera_3d()
	if camera == null:
		quit(1)
		return
	var views := {
		"room": [Vector3(10.5, 1.8, 8.3), Vector3(2, 2.2, 2), 75.0],
		"hallway": [Vector3(6.5, 1.75, 12), Vector3(6.5, 2.0, 29), 75.0],
		"door": [Vector3(9.8, 1.6, 3.6), Vector3(12, 1.5, 2.75), 58.0],
		"column": [Vector3(3.4, 4.15, 3.4), Vector3(2, 4.55, 2), 55.0],
		"column-base": [Vector3(3.0, 0.65, 3.0), Vector3(2, 0.35, 2), 45.0],
		"window": [Vector3(3.2, 1.8, 5.0), Vector3(-1, 2.8, 4.8), 65.0],
	}
	for label: String in views:
		camera.position = views[label][0]
		camera.look_at(views[label][1])
		camera.fov = views[label][2]
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(args[1].path_join(label + ".jpg"), 0.92)
	print("WORLD_PREVIEW: captured room, hallway, door, column and window")
	quit()
