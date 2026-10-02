extends Node
## Real peers and opt-in native-render captures, not production gameplay.

var _observer_ready := false

@onready var _shift: BusboyShift = $Game/Features/bar_companion/BusboyShift


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_run.call_deferred()


func _run() -> void:
	var role := str(Network.args.get("busboy-role", "server"))
	if role == "server":
		# Same unrelated freed-hand HUD workaround as the base Celeste probe.
		$Game/Features/weapon_hotbar.set_process(false)
		while _shift.phase != "active":
			await get_tree().process_frame
		_shift.set_process(false)
		_shift.spawn_empty()
		_shift.orders = {0: 35.0}
		_shift._publish()
		return
	var player: Player
	while player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	if role == "capture":
		await _capture(player)
	elif role == "driver":
		await _drive(player)
	else:
		await _observe(player)


func _drive(player: Player) -> void:
	await _move(player, Vector3(0, 0, 8))
	_shift.get_node("Bar").use()
	await get_tree().create_timer(0.4).timeout
	assert(_shift.snapshot.get("worker", 0) == 0, "range checked on server")
	await _move(player, Vector3(-10, -0.35, -8.65))
	var talk := _shift.get_node("Bar/NetworkedEntity") as NetworkedInteraction
	talk.request_action(&"use", {"peer": 1})
	await get_tree().create_timer(0.4).timeout
	assert(_shift.snapshot.get("worker", 0) == 0, "forged payload rejected")
	_shift.get_node("Bar").use()
	while (_shift.snapshot.get("dirty", []) as Array).is_empty():
		await get_tree().process_frame
	assert(int(_shift.snapshot["worker"]) == multiplayer.get_unique_id())
	var index := int((_shift.snapshot["dirty"] as Array)[0])
	await _move(player, (_shift.get_node("Glass%d" % index) as Node3D).global_position)
	_shift.get_node("Glass%d" % index).use()
	while int(_shift.snapshot.get("cargo", -1)) != -2:
		await get_tree().process_frame
	print("BUSBOY_CARGO_READY")
	while not _observer_ready:
		await get_tree().process_frame
	assert(int(_shift.snapshot["worker"]) == multiplayer.get_unique_id())
	await _move(player, Vector3(-10, -0.35, -8.65))
	_shift.get_node("Bar").use()
	while int(_shift.snapshot["cargo"]) != -1:
		await get_tree().process_frame
	assert(int(_shift.snapshot["cleared"]) == 1)
	await get_tree().create_timer(0.3).timeout
	_shift.get_node("Bar").use()
	while int(_shift.snapshot["cargo"]) != 0:
		await get_tree().process_frame
	await _move(player, Vector3(-2.8, -0.35, -5.103984))
	_shift.get_node("Order0").use()
	while int(_shift.snapshot["served"]) != 1:
		await get_tree().process_frame
	assert((_shift.snapshot["orders"] as Dictionary).is_empty())
	print("BUSBOY_DRIVER_PASS")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _observe(player: Player) -> void:
	await get_tree().create_timer(0.7).timeout
	assert(int(_shift.snapshot.get("worker", 0)) != 0, "late worker snapshot")
	assert(int(_shift.snapshot.get("cargo", -1)) == -2, "late cargo snapshot")
	assert((_shift.snapshot.get("orders", {}) as Dictionary).has(0), "late orders")
	assert(_shift._carry.visible)
	assert(_shift.get_node("Order0").visible)
	var owner := int(_shift.snapshot["worker"])
	await _move(player, Vector3(-10, -0.35, -8.65))
	_shift.get_node("Bar").use()
	await get_tree().create_timer(0.4).timeout
	assert(int(_shift.snapshot["worker"]) == owner, "competing worker rejected")
	assert(int(_shift.snapshot["cargo"]) == -2)
	print("BUSBOY_LATE_JOIN_PASS")
	_observer_checked.rpc_id(owner)
	while str(_shift.snapshot.get("phase", "")) != "idle":
		await get_tree().process_frame
	assert(int(_shift.snapshot["worker"]) == 0)
	assert((_shift.snapshot["orders"] as Dictionary).is_empty())
	assert(not _shift._carry.visible)
	print("BUSBOY_DISCONNECT_PASS")
	get_tree().quit()


@rpc("any_peer", "call_local", "reliable")
func _observer_checked() -> void:
	# Probe-only barrier: never changes gameplay state.
	_observer_ready = true


func _move(player: Player, spot: Vector3) -> void:
	player.global_position = spot
	player.net_position = spot
	await get_tree().create_timer(0.7).timeout


func _capture(player: Player) -> void:
	if get_window().size.x < 600:
		var retro := $Game/Features/retro_style as RetroStyle
		retro.mobile = true
		retro._configure_viewport()
		Controls.touch_available = true
		Controls.select_device(Controls.Device.TOUCH)
	Controls.start()
	for layer: Node in get_tree().get_nodes_in_group(&"modal_ui"):
		layer.queue_free()
	_shift.set_process(false)
	_shift._start(player)
	_shift.dirty = [0, 1, 3, 6, 9, 10, 11]
	_shift.orders = {0: 22.0, 2: 30.0}
	_shift.elapsed = 58.0
	_shift.cargo = -2
	_shift._publish()
	player.global_position = Vector3(-10, -0.35, -8)
	player.net_position = player.global_position
	var view := str(Network.args.get("busboy-view", "bar"))
	var camera := Camera3D.new()
	add_child(camera)
	if view == "tables":
		camera.global_position = Vector3(-10, 2.2, 7)
		camera.look_at(Vector3(-5.5, -0.3, -1))
	elif view == "east":
		camera.global_position = Vector3(19.6, 2.1, 6.5)
		camera.look_at(Vector3(19.6, 1.1, 8))
	elif view == "first":
		player.yaw = 0
		camera.queue_free()
		(player.get_node("Camera") as Camera3D).make_current()
	else:
		camera.global_position = Vector3(-10, 0.8, -6.4)
		camera.look_at(Vector3(-9.9, 0.2, -9.6))
	if view != "first":
		camera.make_current()
	var day := $Game/Features/day_night as DayNight
	day.set_process(false)
	day._apply(0.5)
	await get_tree().create_timer(1.0).timeout
	_shift._present()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/busboy-%s.png" % view)
	print("BUSBOY_CAPTURE_PASS")
	get_tree().quit()
