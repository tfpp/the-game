extends Node
## Run this scene in a rendered Godot window to capture the forced midnight
## lighting on the casino exit, alley and each garage floor.

const OUTPUT_ENV := "CASINO_PROBE_OUTPUT"


func _ready() -> void:
	_capture_views.call_deferred()


func _capture_views() -> void:
	var cycle := $Game/Features/day_night as DayNight
	cycle.set_process(false)
	cycle._apply(0.0)
	await get_tree().create_timer(1.0).timeout
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null:
		push_error("Lighting probe needs an offline player")
		get_tree().quit(1)
		return
	player.set_physics_process(false)
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await _shot(player, Vector3(0, 1.65, 917), Vector3(0, 1.1, 900), "alley-night.png")
	await _shot(player, Vector3(-8, 1.65, 595), Vector3(4, 1.1, 600), "garage-p1-night.png")
	await _shot(player, Vector3(-8, 8.25, 595), Vector3(4, 7.7, 600), "garage-p3-night.png")
	var car := $Game/Features/parking_garage/Garage/Car_F0_1 as CarWreck
	(car.get_node("Loot") as LootContainer).net_searched = true
	car._process(0.5)
	await _shot(
		player,
		car.global_position + Vector3(-3, 1.8, 2.6),
		car.global_position + Vector3(-1.5, 1.0, 0),
		"car-boot-open.png"
	)
	print("LIGHTING_PROBE PASS")
	get_tree().quit()


func _shot(player: Player, eye: Vector3, target: Vector3, filename: String) -> void:
	var eye_offset := player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5
	player.global_position = eye - Vector3(0, eye_offset, 0)
	player.net_position = player.global_position
	var direction := (target - eye).normalized()
	player.yaw = atan2(-direction.x, -direction.z)
	player.pitch = asin(direction.y)
	player.net_yaw = player.yaw
	player.reset_physics_interpolation()
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var output := OS.get_environment(OUTPUT_ENV)
	if output.is_empty():
		output = ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output.path_join(filename))
