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
	player.server_teleport.rpc_id(1, Vector3(30, .2, -10), -PI / 2)
	await get_tree().create_timer(.3).timeout
	await _save("teleport-room-entrance.png")
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = [player.get_rid()]
	query.transform.origin = Vector3(31, .95, -10)
	query.motion = Vector3(8, 0, 0)
	assert(space.cast_motion(query)[0] == 1.0, "Casino-to-room passage blocked")
	for x: float in [33.8, 34.0, 34.2, 36.0, 39.0]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x, .5, -10), Vector3(x, -.5, -10))
		assert(not space.intersect_ray(ray).is_empty(), "Teleport room floor gap")
	player.server_teleport.rpc_id(1, entrance.global_position - Vector3(2, .9, 0), -PI / 2)
	await get_tree().create_timer(.3).timeout
	await _save("casino-portal.png")
	var interaction := get_tree().get_first_node_in_group(&"interaction")
	assert(interaction.call("_find_target") == entrance)
	interaction.call("use")
	await get_tree().create_timer(.5).timeout
	assert(player.net_position == (kit.get_node("Garage/Arrival") as Marker3D).global_position)
	await _save("portal-garage-arrival.png")
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
