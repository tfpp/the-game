extends Node
## Verify and capture travel in the actual loaded game, including its normal player.


func _ready() -> void:
	get_tree().root.size = Vector2i(1200, 800)
	var player: Player
	for frame: int in 600:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
		if player != null:
			break
	assert(player != null)
	player.set_physics_process(false)
	Controls.start()
	var kit := $Game/Features/procedural_rooms
	var entrance := kit.get_node("Entrance") as GarageDoor
	player.server_teleport.rpc_id(1, Vector3(16, .95, -12.8), 1.05)
	player.pitch = .18
	await get_tree().create_timer(.3).timeout
	await _save("crown-teleporter.png")
	assert(not kit.has_node("TeleportRoom"))
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = [player.get_rid()]
	query.transform.origin = Vector3(12, .95, -12.7)
	query.motion = Vector3(0, 0, -1.8)
	assert(space.cast_motion(query)[0] == 1.0, "Teleporter approach blocked")
	for z: float in [-12.7, -13.5, -14.5]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(12, .5, z), Vector3(12, -.5, z))
		assert(not space.intersect_ray(ray).is_empty(), "Teleporter approach floor gap")
	player.server_teleport.rpc_id(1, entrance.global_position + Vector3(0, -.9, 2), 0)
	player.pitch = 0
	await get_tree().create_timer(.3).timeout
	await _save("casino-portal.png")
	var interaction := get_tree().get_first_node_in_group(&"interaction")
	assert(interaction.call("_find_target") == entrance)
	interaction.call("use")
	await get_tree().create_timer(.5).timeout
	assert(player.net_position == (kit.get_node("Garage/Arrival") as Marker3D).global_position)
	await _save("portal-garage-arrival.png")
	var lift := kit.get_node("Garage/CrownGarage/Lift") as ProceduralMovingLift
	player.server_teleport.rpc_id(1, lift.global_position + Vector3(1.8, 16.95, -4.2), .327)
	await get_tree().create_timer(.3).timeout
	await _save("elevator-model-entrance.png")
	player.server_teleport.rpc_id(1, lift.cab.global_position + Vector3.UP * .95, 0)
	player.pitch = -.12
	await get_tree().create_timer(.3).timeout
	await _save("elevator-model-interior.png")
	var visual := lift.cab.get_node("ElevatorCabModel/Visual") as MeshInstance3D
	var painting := visual.material_override
	var checker := painting.duplicate() as StandardMaterial3D
	checker.albedo_texture = load("res://assets/procedural_rooms/models/elevator/uv_checker.png")
	visual.material_override = checker
	await get_tree().create_timer(.2).timeout
	await _save("elevator-model-checker.png")
	visual.material_override = painting
	player.pitch = 0
	player.yaw = PI
	player.net_yaw = PI
	player.set_physics_process(true)
	await get_tree().create_timer(.5).timeout
	await _save("physical-lift-b1.png")
	var button := lift.cab.get_node("Floor0") as Node3D
	player.global_position.x += .35
	player.net_position = player.global_position
	button.call("use")
	assert(lift.net_phase == ProceduralMovingLift.Phase.CLOSING)
	await get_tree().create_timer(4.5).timeout
	assert(lift.net_height > 0 and lift.net_height < 16)
	assert(absf(player.global_position.y - lift.cab.global_position.y - .9144) < .08)
	await _save("physical-lift-moving.png")
	await get_tree().create_timer(6).timeout
	assert(lift.net_phase == ProceduralMovingLift.Phase.DOCKED and lift.net_floor == 0)
	assert(absf(player.global_position.y - kit.global_position.y - .9144) < .08)
	await _save("physical-lift-b5.png")
	player.set_physics_process(false)
	var returning := kit.get_node("Garage/Return") as GarageDoor
	player.server_teleport.rpc_id(1, returning.global_position - Vector3(2, 0, 0), -PI / 2)
	returning.use()
	await get_tree().create_timer(.3).timeout
	assert(player.net_position == (kit.get_node("CasinoArrival") as Marker3D).global_position)
	assert(get_tree().get_nodes_in_group(&"local_player").size() == 1)
	print("LIVE_PORTAL_CAPTURE PASS")
	get_tree().quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var folder := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(folder)
	assert(get_viewport().get_texture().get_image().save_png(folder.path_join(name)) == OK)
