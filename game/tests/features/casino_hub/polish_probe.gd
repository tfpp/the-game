extends Node
## Capture the actual main level and exercise the visual reel settle sequence.

var _player: Player


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	$Game/Features/character_memory.queue_free()
	var cycle := $Game/Features/day_night as DayNight
	cycle.set_process(false)
	cycle._apply(0.5)
	await get_tree().create_timer(0.5).timeout
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	_player.set_physics_process(false)
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	var machine := $Game/Features/slot_machine/Machine as SlotMachine
	machine.set_process(false)
	_view(machine.to_global(Vector3(0.4, 1.9, 3.2)), machine.interaction_point())
	await _capture("/tmp/casino-slot-detail.png")
	machine.state = {
		"spin": 1,
		"spinning": true,
		"reels": [4, 3, 2],
		"stopped": 0,
		"operator": "Preview",
		"won": true,
		"payout": 3000,
		"message": ""
	}
	await get_tree().create_timer(0.5).timeout
	for stopped: int in range(1, 4):
		machine.state = {
			"spin": 1,
			"spinning": stopped < 3,
			"reels": [0, 0, 0],
			"stopped": stopped,
			"operator": "Preview",
			"won": true,
			"payout": 3000,
			"message": ""
		}
		await get_tree().create_timer(0.4).timeout
	var view: Node3D = machine.get_node("View")
	for index: int in 3:
		assert(is_zero_approx(fposmod(view._positions[index], 5.0)))
	assert(view._status.text == "WON $30.00")
	await _capture("/tmp/casino-slot-win.png")
	_view(Vector3(-27, 2.2, -8), Vector3(-31, 0.9, -13))
	await _capture("/tmp/casino-furniture.png")
	_view(Vector3(-1, 0.15, 5), Vector3(-1, 1.8, -5))
	await _capture("/tmp/casino-chandeliers.png")
	_view(Vector3(-0.7, 0.15, 5), Vector3(-0.7, 0.15, -8))
	await _capture("/tmp/casino-polished-wide.png")
	cycle._apply(0.0)
	await _capture("/tmp/casino-night.png")
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_view(Vector3(-1.4, 0.25, 4.6), Vector3(-4, -0.65, 4))
	await _capture("/tmp/casino-salon-table.png")
	_view(Vector3(-11, 4.85, -9), Vector3(-1, -0.1, 3))
	await _capture("/tmp/casino-salon-gallery.png")
	print("POLISH_PROBE PASS: real level, models, authoritative reel stops and win display")
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
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
