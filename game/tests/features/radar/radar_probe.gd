extends Node
## Full-scene rendered QA, including streaming, screen size and device changes.

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := $Game
	game.get_node("Features/character_memory").queue_free()
	await get_tree().create_timer(0.5).timeout
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	var radar: Control = game.get_node("Features/radar/Map")
	player.global_position = Vector3(0, 0.94, 23)
	player.net_yaw = 0
	player.yaw = 0
	player.pitch = 0
	player.reset_physics_interpolation()
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	await get_tree().create_timer(2).timeout
	_check(radar.visible, "Desktop gamepad radar is visible")
	_check(radar._geometry != null and radar._geometry.walls.size() > 0, "Real map walls drawn")
	_check(radar._geometry != null and radar._geometry.floors.size() > 0, "Real map floors drawn")
	await _capture("/tmp/radar-casino.png")
	# Check the same clear routes against all loaded feature collisions.
	_sweep(
		player,
		[
			Vector2(-12, -30),
			Vector2(-12, -45),
			Vector2(-33, -45),
			Vector2(-44, -45),
			Vector2(-44, -58),
			Vector2(-50, -58),
			Vector2(-50, 28)
		]
	)
	_sweep(player, [Vector2(-26, 8), Vector2(-50, 8)])
	_sweep(player, [Vector2(10, -30), Vector2(10, -62.5)])
	_sweep(player, [Vector2(10, -45), Vector2(30, -45)])
	_sweep(
		player,
		[Vector2(34, -10), Vector2(65, -10), Vector2(65, -16), Vector2(60, -16), Vector2(60, -40)]
	)
	_sweep(player, [Vector2(0, 30), Vector2(0, 48), Vector2(-22.5, 48), Vector2(-22.5, 70)])
	_sweep(
		player,
		[Vector2(-50, 28), Vector2(-56, 28), Vector2(-56, 37), Vector2(-50, 37), Vector2(-50, 55)]
	)
	player.global_position = Vector3(-12, 0.94, -40)
	player.reset_physics_interpolation()
	await get_tree().create_timer(2).timeout
	await _capture("/tmp/radar-annex.png")
	# Load a real streamed room and ensure the map follows the destination.
	var lounge := game.get_node("Features/room_doors/Lounge") as StreamedRoom
	player.global_position = lounge.global_position + Vector3(0, 0.94, 0)
	player.reset_physics_interpolation()
	await get_tree().create_timer(2).timeout
	_check(lounge.is_loaded(), "Lounge loaded around player")
	_check(radar._geometry != null and radar._geometry.walls.size() > 0, "Streamed room mapped")
	_check(
		(
			radar._center.distance_to(Vector2(player.global_position.x, player.global_position.z))
			< 0.01
		),
		"Radar follows teleport"
	)
	await _capture("/tmp/radar-lounge.png")
	# Exercise the actual interactive door chain, including both return journeys.
	var doors := game.get_node("Features/room_doors")
	for path: String in [
		"Lounge/CellarDoor", "Cellar/LoungeDoor", "Lounge/LobbyDoor", "Lobby/Door"
	]:
		var door := doors.get_node(path) as RoomDoor
		player.global_position = door.global_position + Vector3(0, 0, 0.9)
		player.net_position = player.global_position
		door.use()
		await get_tree().create_timer(0.3).timeout
		var arrival := door.get_node(door.destination) as Marker3D
		_check(player.net_position.is_equal_approx(arrival.global_position), "Door works: " + path)
		var destination_room := door.destination_room()
		if destination_room != null:
			_check(destination_room.is_loaded(), "Destination built: " + path)
			var floor_ray := PhysicsRayQueryParameters3D.create(
				arrival.global_position, arrival.global_position - Vector3(0, 2, 0)
			)
			floor_ray.exclude = [player.get_rid()]
			_check(
				not player.get_world_3d().direct_space_state.intersect_ray(floor_ray).is_empty(),
				"Arrival floor exists: " + path
			)
		if path == "Lounge/CellarDoor":
			await _capture("/tmp/radar-cellar.png")
	get_window().size = Vector2i(960, 600)
	await get_tree().create_timer(0.2).timeout
	var panel: Control = game.get_node("HUD/Corners/Players")
	_check(
		radar.get_global_rect().position.y > panel.get_global_rect().end.y,
		"Radar clears status panel"
	)
	await _capture("/tmp/radar-small.png")
	radar._mobile = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not radar.visible, "Mobile hides radar even with gamepad")
	radar._mobile = false
	Controls.touch_available = true
	Controls.joypad = -1
	Controls.select_device(Controls.Device.TOUCH)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not radar.visible, "Touch play hides radar")
	print("RADAR_PROBE ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


func _sweep(player: Player, points: Array[Vector2]) -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4064
	shape.height = 1.8288
	var space := player.get_world_3d().direct_space_state
	for index: int in range(points.size() - 1):
		var start := Vector3(points[index].x, 0.94, points[index].y)
		var end := Vector3(points[index + 1].x, 0.94, points[index + 1].y)
		for reverse: bool in [false, true]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.exclude = [player.get_rid()]
			query.transform.origin = end if reverse else start
			query.motion = start - end if reverse else end - start
			_check(
				space.cast_motion(query)[0] > 0.999, "Full-scene passage %s -> %s" % [start, end]
			)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failed = true
		push_error(description)


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
