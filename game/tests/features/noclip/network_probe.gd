extends Node

var _noclip: Node


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_noclip = $Game/Features/noclip
	match Network.args.get("cheat-role", ""):
		"driver":
			_driver()
		"observer":
			_observer()


func _driver() -> void:
	while get_tree().get_first_node_in_group(&"local_player") == null:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	_check(not _noclip.cheats_enabled, "Cheats must start off")
	_noclip.request_cheats.rpc_id(1, 1)
	while not _noclip.cheats_enabled:
		await get_tree().process_frame
	_noclip.toggle()
	_check(_noclip._active, "Driver can fly after server enables cheats")
	print("CHEAT_DRIVER_READY")
	while _noclip.cheats_enabled:
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not _noclip._active, "Remote revocation stops driver flight")
	print("CHEAT_DRIVER_DONE")


func _observer() -> void:
	while get_tree().get_first_node_in_group(&"local_player") == null:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_check(_noclip.cheats_enabled, "Late join receives enabled snapshot")
	_check(not _noclip.apply_cheats(multiplayer.get_unique_id(), 0), "Client cannot apply state")
	_noclip.request_cheats.rpc_id(1, 99)
	await get_tree().create_timer(0.3).timeout
	_check(_noclip.cheats_enabled, "Server rejects invalid cheat value")
	_noclip.toggle()
	_check(_noclip._active, "Late join can use flight")
	print("CHEAT_OBSERVER_READY")
	_noclip.request_cheats.rpc_id(1, 0)
	while _noclip.cheats_enabled:
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not _noclip._active, "Revocation stops observer flight")
	print("CHEAT_OBSERVER_DONE")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		get_tree().quit(1)
