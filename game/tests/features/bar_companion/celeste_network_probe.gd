extends Node
## Real-peer and rendered-scene probe; run with celeste_network_test.sh.

@onready var _npc: Celeste = $Game/Features/bar_companion/Celeste


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_run.call_deferred()


func _run() -> void:
	var role := str(Network.args.get("celeste-role", "server"))
	if role == "server":
		# This client-only HUD caches a freed hand after remote peers disconnect.
		# It is unrelated to companion state and has no presentation on this server.
		$Game/Features/weapon_hotbar.set_process(false)
		return
	var player: Player
	while player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	if role == "capture":
		await _capture(player)
		return
	var talk := _npc.get_node("NetworkedEntity") as NetworkedInteraction
	if role == "driver":
		player.global_position = Vector3(0, 0, 5)
		player.net_position = player.global_position
		await get_tree().create_timer(0.7).timeout
		_npc.use()
		await get_tree().create_timer(0.3).timeout
		assert(_npc.net_leader == 0, "out-of-range request rejected")
		player.global_position = _npc.global_position + Vector3(0, 0, 1)
		player.net_position = player.global_position
		await get_tree().create_timer(0.7).timeout
		talk.request_action(&"use", {"peer": 1})
		await get_tree().create_timer(0.3).timeout
		assert(_npc.net_leader == 0, "forged payload rejected")
		_npc.use()
		_npc.use()
		await get_tree().create_timer(0.5).timeout
		assert(_npc.net_leader == multiplayer.get_unique_id())
		var subtitles := get_tree().get_first_node_in_group(&"subtitles") as Subtitles
		assert(subtitles.current_text().contains("Celeste:"))
		print("CELESTE_RECRUITED")
		await get_tree().create_timer(8.0).timeout
		assert(_npc.net_leader == multiplayer.get_unique_id(), "observer cannot steal companion")
		print("CELESTE_DRIVER_PASS")
		get_tree().quit()
	else:
		await get_tree().create_timer(0.7).timeout
		assert(_npc.net_leader != 0, "late join receives active leader")
		assert(_npc.global_position.distance_to(_npc.net_position) < 0.1)
		var leader := _npc.net_leader
		player.global_position = _npc.global_position + Vector3(0.5, 0, 0)
		player.net_position = player.global_position
		await get_tree().create_timer(0.5).timeout
		_npc.use()
		await get_tree().create_timer(0.5).timeout
		assert(_npc.net_leader == leader, "other player cannot dismiss or recruit her")
		var subtitles := get_tree().get_first_node_in_group(&"subtitles") as Subtitles
		assert(
			not subtitles.current_text().contains("Celeste:"), "dialogue is private and transient"
		)
		print("CELESTE_LATE_JOIN_PASS")
		while _npc.net_leader != 0:
			await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		assert(_npc.net_position.distance_to(Vector3(-6.6, -1.25, -7.8)) < 0.01)
		print("CELESTE_DISCONNECT_PASS")
		get_tree().quit()


func _capture(player: Player) -> void:
	Controls.start()
	player.global_position = _npc.global_position + Vector3(0, 0, 3.5)
	player.net_position = player.global_position
	for layer: Node in get_tree().get_nodes_in_group(&"modal_ui"):
		layer.queue_free()
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = _npc.global_position + Vector3(0.6, 1.5, 3.2)
	camera.look_at(_npc.global_position + Vector3(0, 1.0, 0))
	camera.make_current()
	var day := $Game/Features/day_night as DayNight
	day.set_process(false)
	day._apply(0.5)
	await get_tree().create_timer(1.0).timeout
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/celeste.png")
	print("CELESTE_CAPTURE_PASS")
	get_tree().quit()
