extends Node
## Reproducible local frame-time probe. Run with the normal Compatibility renderer:
## godot --path game res://tests/features/retro_style/runtime_perf_probe.tscn

@onready var game: Node = $Game


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var sun := game.get_node("Features/day_night/Sun") as DirectionalLight3D
	sun.shadow_enabled = "--perf-shadows" in OS.get_cmdline_user_args()
	print("PERF_SHADOWS ", sun.shadow_enabled)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null:
		push_error("No local player for performance probe")
		get_tree().quit(1)
		return
	player.set_physics_process(false)
	for point: Dictionary in [
		{"name": "casino", "at": Vector3(0, 1.2, 23)},
		{"name": "garage", "at": Vector3(-10, 1.2, 595)},
		{"name": "alley", "at": Vector3(0, 1.2, 918)},
		{"name": "hotel", "at": Vector3(8.75, 1.2, -1398)},
		{"name": "apartments", "at": Vector3(195, 1.2, 1204)},
	]:
		player.global_position = point["at"]
		player.net_position = point["at"]
		player.reset_physics_interpolation()
		await get_tree().create_timer(1.0).timeout
		await _sample(point["name"])
		if point["name"] == "apartments":
			await _measure_room_contributors()
	var features := game.get_node("Features")
	player.global_position = Vector3(0, 1.2, 23)
	player.net_position = player.global_position
	await get_tree().create_timer(0.5).timeout
	var rid := get_tree().root.get_viewport_rid()
	var baseline := _draw_calls(rid)
	for feature: Node in features.get_children():
		var spatial := feature as Node3D
		if spatial == null or not spatial.visible:
			continue
		spatial.visible = false
		await get_tree().process_frame
		await get_tree().process_frame
		var removed := baseline - _draw_calls(rid)
		spatial.visible = true
		await get_tree().process_frame
		await get_tree().process_frame
		if removed >= 25:
			print("PERF_DRAWS ", feature.name, " removed=", removed)
	for feature: Node in features.get_children():
		var counts := _count_process_nodes(feature)
		if counts["process"] + counts["physics"] >= 5:
			print("PERF_FEATURE ", feature.name, " ", counts)
	get_tree().quit()


func _measure_room_contributors() -> void:
	var room := game.get_node("Room") as Node3D
	var features := game.get_node("Features") as Node3D
	var rid := get_tree().root.get_viewport_rid()
	var baseline := _draw_calls(rid)
	room.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	print("PERF_APARTMENT_LOBBY removed=", baseline - _draw_calls(rid))
	room.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	for feature: Node in features.get_children():
		var spatial := feature as Node3D
		if spatial == null or not spatial.visible:
			continue
		spatial.visible = false
		await get_tree().process_frame
		await get_tree().process_frame
		var removed := baseline - _draw_calls(rid)
		spatial.visible = true
		await get_tree().process_frame
		await get_tree().process_frame
		if removed >= 25:
			print("PERF_APARTMENT_DRAWS ", feature.name, " removed=", removed)


func _draw_calls(rid: RID) -> int:
	return RenderingServer.viewport_get_render_info(
		rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	)


func _sample(label: String) -> void:
	var camera := get_viewport().get_camera_3d()
	print(
		"PERF_CAMERA ",
		label,
		" at=",
		camera.global_position if camera != null else Vector3.ZERO,
		" far=",
		camera.far if camera != null else 0.0
	)
	if label == "casino":
		var visibility := game.get_node("Features/room_visibility") as RoomVisibility
		print(
			"PERF_CASINO_BOUNDS ",
			visibility._casino_bounds,
			" current=",
			visibility._current_bounds
		)
	if label == "apartments":
		var lobby := game.get_node("Features/apartments/Lobby") as StreamedRoom
		print("PERF_LOBBY loaded=", lobby.is_loaded())
		if lobby.is_loaded():
			var geometry := lobby.get_node("Content").get_child(0) as Node3D
			print("PERF_LOBBY_GEOM ", geometry.name, " at=", geometry.global_position)
	var frame_ms: Array[float] = []
	var wall_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var draws: Array[float] = []
	var rid := get_tree().root.get_viewport_rid()
	var last_tick := Time.get_ticks_usec()
	for _i in 120:
		await get_tree().process_frame
		var tick := Time.get_ticks_usec()
		wall_ms.append(float(tick - last_tick) / 1000.0)
		last_tick = tick
		frame_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		physics_ms.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		draws.append(
			float(
				RenderingServer.viewport_get_render_info(
					rid,
					RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
					RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
				)
			)
		)
	frame_ms.sort()
	wall_ms.sort()
	physics_ms.sort()
	draws.sort()
	print(
		"PERF_SAMPLE ",
		label,
		" process_median_ms=",
		frame_ms[60],
		" process_p95_ms=",
		frame_ms[114],
		" frame_median_ms=",
		wall_ms[60],
		" frame_p95_ms=",
		wall_ms[114],
		" physics_p95_ms=",
		physics_ms[114],
		" draws_median=",
		draws[60],
		" fps=",
		Engine.get_frames_per_second()
	)


func _count_process_nodes(node: Node) -> Dictionary:
	var result := {
		"process": 1 if node.is_processing() else 0,
		"physics": 1 if node.is_physics_processing() else 0
	}
	for child: Node in node.get_children():
		var child_counts := _count_process_nodes(child)
		result["process"] += child_counts["process"]
		result["physics"] += child_counts["physics"]
	return result
