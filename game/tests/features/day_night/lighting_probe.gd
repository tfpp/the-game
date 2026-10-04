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
	var garage := $Game/Features/procedural_rooms/Garage as Node3D
	await _shot(
		player,
		garage.to_global(Vector3(-8, 17.65, 5)),
		garage.to_global(Vector3(4, 17, 10)),
		"garage-b1-night.png"
	)
	await _shot(
		player,
		garage.to_global(Vector3(-8, 1.65, 5)),
		garage.to_global(Vector3(4, 1, 10)),
		"garage-b5-night.png"
	)
	for node: Node in get_tree().get_nodes_in_group(LootContainer.GROUP):
		if node is CarBoot and garage.is_ancestor_of(node):
			var boot := node as CarBoot
			var car := boot.get_parent() as Node3D
			boot.net_boot_open = true
			boot._process(.5)
			await _shot(
				player,
				car.to_global(Vector3(-3, 1.8, 2.6)),
				boot.global_position,
				"car-boot-open.png"
			)
			break
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
