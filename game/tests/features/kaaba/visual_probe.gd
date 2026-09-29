extends Node
## Render the real level: close-wall prayer, third-person view, and a blessed spin.

var _player: Player


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	$Game/Features/character_memory.queue_free()
	await get_tree().create_timer(1.0).timeout
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	_player.set_physics_process(false)
	Controls.select_device(Controls.Device.GAMEPAD)
	$Game/LoginScreen._resume()
	var prayer := $Game/Features/kaaba/Prayer as KaabaPrayer
	var interaction := get_tree().get_first_node_in_group(&"interaction")
	_view(prayer.global_position + Vector3(2.7, 0.9144, 0), PI * 0.5)
	await get_tree().physics_frame
	interaction.use()
	await get_tree().create_timer(1.0).timeout
	assert("Praying" in interaction.target_text())
	await _capture("praying")
	await prayer.entity.event_received
	assert(prayer.blessings_for(1) == 1)
	for child: Node in prayer.get_children():
		if child is BlessingEffect:
			child.set_process(false)
	await _capture("completed-first-person")
	for child: Node in prayer.get_children():
		if child is BlessingEffect:
			child._process(0.8)
	$Game/Features/third_person.enabled = true
	await _capture("completed-third-person")
	$Game/Features/third_person.enabled = false
	var machine := $Game/Features/slot_machine/Machine as SlotMachine
	_view(machine.to_global(Vector3(0, 0.9144, 2.5)), machine.global_rotation.y)
	await get_tree().physics_frame
	interaction.use()
	assert(machine.state["spinning"])
	await _capture("blessed-spin")
	print("KAABA_VISUAL PASS: shared Use, timed completion, first/third person, paid spin")
	get_tree().quit()


func _view(at: Vector3, yaw: float) -> void:
	_player.position = at
	_player.net_position = at
	_player.yaw = yaw
	_player.net_yaw = yaw
	_player.pitch = 0.0
	_player.net_pitch = 0.0
	_player.reset_physics_interpolation()


func _capture(suffix: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/kaaba-" + suffix + ".png")
