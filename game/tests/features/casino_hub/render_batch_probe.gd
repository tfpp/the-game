extends SceneTree
## Manual Compatibility-renderer comparison of four-cell and eight-cell batches.
## Run with a display and --audio-driver Dummy using -s with this script path.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(960, 540)
	var room := (
		(load("res://features/casino_hub/gridmap/playable.tscn") as PackedScene).instantiate()
	)
	root.add_child(room)
	# Freeze animated furnishings for a comparable framebuffer.
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	room.add_child(camera)
	camera.current = true
	var views: Array[Vector3] = [
		Vector3(0, 1.65, 16), Vector3(-19, 2.2, -8), Vector3(-1, 0.15, 5), Vector3(6, 1.65, 26)
	]
	var targets: Array[Vector3] = [
		Vector3(0, 1, 0), Vector3(-23, 0.9, -13), Vector3(-1, 1.8, -5), Vector3(24, 1.2, 29)
	]
	for index: int in views.size():
		camera.position = views[index]
		camera.look_at(targets[index])
		var images: Array[Image] = []
		for size: int in [4, 8]:
			for node: Node in room.find_children("*", "GridMap", true, false):
				(node as GridMap).cell_octant_size = size
			for frame: int in 10:
				await process_frame
			await RenderingServer.frame_post_draw
			print(
				"VIEW ",
				index,
				" SIZE ",
				size,
				" DRAWS ",
				root.get_render_info(
					Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
				),
				" SHADOW DRAWS ",
				root.get_render_info(
					Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
				)
			)
			var image := root.get_texture().get_image()
			image.save_png("/tmp/batch-%d-%d.png" % [index, size])
			images.append(image)
		var difference := 0.0
		var changed := 0
		for y: int in images[0].get_height():
			for x: int in images[0].get_width():
				var a := images[0].get_pixel(x, y)
				var b := images[1].get_pixel(x, y)
				var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
				difference = maxf(difference, d)
				if d > 0.01:
					changed += 1
		print("PIXELS ", index, " max ", difference, " changed ", changed)
		if difference > 0.05 or changed > 50:
			push_error("Batching changed scene lighting beyond the comparison tolerance")
			quit(1)
			return
	quit()
