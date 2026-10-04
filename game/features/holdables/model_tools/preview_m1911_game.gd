extends Node
## Authoring capture: exercise the actual first-person hand and reload visuals.


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		get_tree().quit(1)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().root.size = Vector2i(1280, 720)
	var game := preload("res://main.tscn").instantiate()
	get_tree().root.add_child(game)
	var shop := game.get_node("Features/pawn_shop") as Node3D
	(shop.get_node("Room") as StreamedRoom).load_room(60000)
	for frame: int in 10:
		await get_tree().process_frame
	game.get_node("LoginScreen").set_process(false)
	for overlay: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		overlay.hide()
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	assert(player != null)
	player.set_physics_process(false)
	player.global_position = shop.to_global(Vector3(-9, .95, 31.5))
	player.net_position = player.global_position
	player.yaw = PI
	player.net_yaw = PI
	player.pitch = 0.0
	var hand := Hand.for_peer(get_tree(), 1)
	assert(hand != null)
	hand.net_item_id = "pistol"
	hand.inventory().backpack = PackedStringArray(["ammo:pistol:20", "", "", "", "", "", "", ""])
	for frame: int in 30:
		await get_tree().process_frame
	(player.get_node("FirstPersonView") as CanvasLayer).show()
	await _save(output, "first-person")
	# Drive seven real server shots, then start the registered reload action.
	for shot: int in 7:
		hand._fire_cooldown = 0.0
		hand.request_primary_action()
		await get_tree().process_frame
	await get_tree().create_timer(.2).timeout
	await _save(output, "first-person-empty")
	hand.pistol.entity.request_action(&"reload")
	await get_tree().create_timer(.72).timeout
	await _save(output, "first-person-reload")
	await get_tree().create_timer(1.05).timeout
	await _save(output, "first-person-reloaded")
	print(
		"M1911 IN-GAME: ",
		hand.pistol.loaded(),
		" loaded, ",
		hand.inventory().ammo_for("pistol"),
		" total, reload active=",
		hand.pistol.active()
	)
	game.queue_free()
	for renderer: Node in get_tree().get_nodes_in_group(&"model_icon_renderers"):
		renderer.queue_free()
	for frame: int in 3:
		await get_tree().process_frame
	get_tree().quit()


func _save(output: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
