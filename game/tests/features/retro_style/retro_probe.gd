extends Node
## Render the real scene with an optional forced mobile budget and record GPU work.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	$Game/Features/character_memory.queue_free()
	var cycle := $Game/Features/day_night as DayNight
	cycle.set_process(false)
	cycle._apply(0.5)
	await get_tree().create_timer(3.0).timeout
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	player.yaw = 0.0
	player.pitch = 0.0
	player.net_yaw = 0.0
	var eye_offset := player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5
	player.global_position = Vector3(0, 1.65 - eye_offset, 23)
	player.net_position = player.global_position
	player.reset_physics_interpolation()
	var style := $Game/Features/retro_style as RetroStyle
	if style.mobile:
		Controls.touch_available = true
		Controls.select_device(Controls.Device.TOUCH)
	else:
		Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	await _capture("day")
	cycle._apply(0.0)
	await _capture("night")
	player.global_position = Vector3(-0.7, 0.15 - eye_offset, 5)
	player.net_position = player.global_position
	player.reset_physics_interpolation()
	cycle._apply(0.5)
	await _capture("salon-day")
	cycle._apply(0.0)
	await _capture("salon-night")
	assert(is_equal_approx(get_viewport().scaling_3d_scale, 1.0))
	if style.mobile:
		assert(get_viewport().msaa_3d == Viewport.MSAA_DISABLED)
		for node: Node in get_tree().root.find_children("*", "Light3D", true, false):
			assert(not (node as Light3D).shadow_enabled)
	print("RETRO_PROBE PASS mobile=", style.mobile, " scale=", get_viewport().scaling_3d_scale)
	cycle._apply(0.5)
	player.global_position = Vector3(0, 1.65 - eye_offset, 23)
	player.net_position = player.global_position
	player.reset_physics_interpolation()
	for index: int in 3:
		var avatar := BlockPlayerModel.new()
		avatar.position = Vector3(float(index - 1) * 1.6, 0.9144, 19)
		avatar.rotation.y = PI
		avatar.set_skin_index(index * 2)
		avatar.set_body_type("girl" if index == 1 else "default")
		avatar.set_clothing("shirt:%d" % [1, 11, 2][index], "pants:1")
		add_child(avatar)
	await _capture("avatars")
	get_tree().quit()


func _capture(label: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/retro-%s.png" % label)
	var rid := get_viewport().get_viewport_rid()
	print(
		"RETRO_COUNTERS ",
		label,
		" draws=",
		RenderingServer.viewport_get_render_info(
			rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
		),
		" primitives=",
		RenderingServer.viewport_get_render_info(
			rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
		)
	)
