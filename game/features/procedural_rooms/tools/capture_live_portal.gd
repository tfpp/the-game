extends Node
## Capture actual walking and continuous casino/basement travel with the normal player.


func _ready() -> void:
	get_tree().root.size = Vector2i(1200, 800)
	var player: Player
	for frame: int in 600:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
		if player != null:
			break
	assert(player != null)
	var kit := $Game/Features/procedural_rooms
	var lift := kit.get_node("Garage/CrownGarage/Lift") as ProceduralMovingLift
	assert(lift.net_floor == 5 and lift.gates.size() == 6)
	player.server_teleport.rpc_id(1, Vector3(31, .95, -25), -PI / 2)
	Controls.start()
	await get_tree().create_timer(.3).timeout
	await _save("casino-elevator-entrance.png")
	await _walk(player, -PI / 2, 35.5)
	assert(lift.contains(player))
	assert(absf(player.global_position.y - .9144) < .08)
	var original_parent := player.get_parent()
	await _select(player, lift, 4)
	await get_tree().create_timer(4.8).timeout
	assert(lift.net_floor == 4 and lift.net_phase == ProceduralMovingLift.Phase.DOCKED)
	assert(player.get_parent() == original_parent)
	assert(absf(player.global_position.y + 6 - .9144) < .08)
	await _save("physical-lift-b1.png")
	await _walk(player, PI / 2, 24)
	assert(absf(player.global_position.y + 6 - .9144) < .08)
	await _save("casino-basement-b1.png")
	await _walk(player, -PI / 2, 35.5)
	player.set_physics_process(false)
	player.global_position = lift.cab.to_global(Vector3(0, .95, -.65))
	player.net_position = player.global_position
	player.yaw = lift.global_rotation.y - PI / 2
	player.pitch = -.05
	await get_tree().create_timer(.3).timeout
	await _save("elevator-floor-panel.png")
	await _select(player, lift, 0)
	await get_tree().create_timer(4.5).timeout
	assert(lift.net_height > 0 and lift.net_height < 16)
	assert(absf(player.global_position.y - lift.cab.global_position.y - .9144) < .08)
	player.yaw = lift.global_rotation.y + PI
	player.pitch = 0
	await _save("physical-lift-moving.png")
	await get_tree().create_timer(6).timeout
	assert(lift.net_floor == 0 and lift.net_phase == ProceduralMovingLift.Phase.DOCKED)
	await _save("physical-lift-b5.png")
	await _select(player, lift, 5)
	await get_tree().create_timer(13.3).timeout
	assert(lift.net_floor == 5 and lift.net_phase == ProceduralMovingLift.Phase.DOCKED)
	assert(absf(player.global_position.y - .9144) < .08)
	assert(player.get_parent() == original_parent)
	await _walk(player, PI / 2, 31)
	await _save("casino-elevator-return.png")
	assert(get_tree().get_nodes_in_group(&"local_player").size() == 1)
	print("CASINO_BASEMENT_LIFT_CAPTURE PASS")
	get_tree().quit()


func _walk(player: Player, yaw: float, target_x: float) -> void:
	Controls.device = Controls.Device.XR
	Controls.playing = true
	player.yaw = yaw
	player.set_physics_process(true)
	Controls.xr_move = Vector2(0, -.5)
	for frame: int in 400:
		await get_tree().physics_frame
		if absf(player.global_position.x - target_x) < .12:
			break
	Controls.xr_move = Vector2.ZERO
	for frame: int in 8:
		await get_tree().physics_frame
	assert(
		absf(player.global_position.x - target_x) < .45,
		"Walking route must stay clear: %s toward x=%s" % [player.global_position, target_x]
	)
	Controls.device = Controls.Device.KEYBOARD
	Controls.start()


func _select(player: Player, lift: ProceduralMovingLift, index: int) -> void:
	player.set_physics_process(false)
	player.global_position = lift.cab.to_global(Vector3(0, .95, -.65))
	player.net_position = player.global_position
	var button := lift.cab.get_node("Floor%d" % index) as Node3D
	var eye := (
		player.global_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * .5)
	)
	var direction := (button.global_position - eye).normalized()
	player.yaw = atan2(-direction.x, -direction.z)
	player.pitch = asin(direction.y)
	Controls.start()
	var interaction := get_tree().get_first_node_in_group(&"interaction")
	assert(interaction.call("_find_target") == button)
	interaction.call("use")
	assert(lift.net_target == index and lift.net_phase == ProceduralMovingLift.Phase.CLOSING)
	player.set_physics_process(true)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var folder := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(folder)
	assert(get_viewport().get_texture().get_image().save_png(folder.path_join(name)) == OK)
