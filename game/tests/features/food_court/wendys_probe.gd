extends Node
## Render the actual food court plus the burger in first and third person.

var _player: Player


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	$Game/Features/character_memory.queue_free()
	await get_tree().create_timer(0.5).timeout
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	_player.set_physics_process(false)
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	($Game/Features/strip_mall/Room as StreamedRoom).load_room(6000)
	_view(Vector3(25.8, 1.65, -4968), Vector3(30, 1.5, -4965))
	await _capture("/tmp/wendys-counter.png")
	_view(Vector3(28.3, 1.65, -4965), Vector3(30, 1.5, -4965))
	$Game/Features/food_court/WendysStand.use()
	var hand := Hand.for_peer(get_tree(), 1)
	assert(hand.net_item_id == "wendys_burger")
	await _capture("/tmp/wendys-first-person.png")
	# The capture harness has no focused input device; set the same camera flag.
	$Game/Features/third_person.enabled = true
	await _capture("/tmp/wendys-third-person.png")
	print("WENDYS_PROBE PASS: offline Use delivered a burger; actual room and held views captured")
	get_tree().quit()


func _view(eye: Vector3, target: Vector3) -> void:
	var offset := _player.movement.eye_height_m() - _player.movement.hull_height_m() * 0.5
	_player.global_position = eye - Vector3(0, offset, 0)
	_player.net_position = _player.global_position
	var direction := (target - eye).normalized()
	_player.yaw = atan2(-direction.x, -direction.z)
	_player.pitch = asin(direction.y)
	_player.net_yaw = _player.yaw
	_player.reset_physics_interpolation()


func _capture(path: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
