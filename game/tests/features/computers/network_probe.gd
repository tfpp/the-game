extends Node
## Real authenticated WebSocket peers, launched by network_test.py.

@onready var computer: ArcadeComputer = $Game/Features/computers/TurkeyOne


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	# Server HUD caches a departed player in the base snapshot; it is unrelated to this probe.
	if Network.mode == Network.Mode.SERVER:
		$Game/Features/weapon_hotbar.set_process(false)
	var role := str(Network.args.get("computer-role", "server"))
	if role == "driver":
		_drive()
	elif role == "observer":
		_observe()


func _place() -> void:
	while get_tree().get_first_node_in_group(&"local_player") == null:
		await get_tree().process_frame
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	player.position = computer.to_global(Vector3(0, 0.9144, 2.5))
	player.net_position = player.position
	player.net_yaw = PI
	player.net_pitch = 0
	await get_tree().create_timer(0.8).timeout


func _drive() -> void:
	await _place()
	computer.request_open.rpc_id(1)
	while int(computer.state.owner) != multiplayer.get_unique_id():
		await get_tree().process_frame
	var epoch := int(computer.state.epoch)
	computer.request_click.rpc_id(1, epoch, Vector2i(160, 170))
	await get_tree().create_timer(0.2).timeout
	for index: int in 3:
		computer.request_click.rpc_id(1, epoch, Vector2i(160, 100))
		await get_tree().create_timer(0.2).timeout
	assert(int(computer.state.score) == 30)
	print("DRIVER_SCORED")
	while true:
		computer.keep_alive.rpc_id(1, epoch)
		await get_tree().create_timer(1).timeout


func _observe() -> void:
	await _place()
	assert(int(computer.state.score) == 30, "Late join sees live score")
	assert(int(computer.state.best) == 30)
	var owner_peer := int(computer.state.owner)
	var epoch := int(computer.state.epoch)
	assert(owner_peer != 0 and owner_peer != multiplayer.get_unique_id())
	computer.request_open.rpc_id(1)
	computer.request_click.rpc_id(1, epoch, Vector2i(160, 100))
	computer.request_close.rpc_id(1, epoch)
	await get_tree().create_timer(0.4).timeout
	assert(int(computer.state.owner) == owner_peer)
	assert(int(computer.state.score) == 30)
	print("LATE_JOIN_AND_COMPETING_REJECTED")
	while int(computer.state.owner) != 0:
		await get_tree().process_frame
	computer.request_open.rpc_id(1)
	while int(computer.state.owner) != multiplayer.get_unique_id():
		await get_tree().process_frame
	assert(int(computer.state.epoch) > epoch)
	assert(int(computer.state.best) == 30)
	computer.request_click.rpc_id(1, int(computer.state.epoch), Vector2i(160, 170))
	await get_tree().create_timer(0.2).timeout
	computer.request_click.rpc_id(1, int(computer.state.epoch), Vector2i(160, 100))
	await get_tree().create_timer(0.2).timeout
	assert(int(computer.state.score) == 10)
	print("HANDOFF_DONE")
