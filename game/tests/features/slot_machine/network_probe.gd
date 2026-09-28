extends Node
## Standalone real-WebSocket test driver; used by network_test.py, never by the game.

var _last_snapshot := ""
var _last_audio := 0
var _sent_competing_request := false

@onready var _machine: SlotMachine = $Game/Features/slot_machine/Machine


func _ready() -> void:
	# Keep this probe independent of previously saved development player positions.
	$Game/Features/character_memory.queue_free()
	if Network.args.get("slot-role", "") == "driver":
		_drive()


func _process(_delta: float) -> void:
	if _machine._last_sound_spin != _last_audio:
		_last_audio = _machine._last_sound_spin
		print("SLOT_AUDIO ", _last_audio)
	var state := _machine.state
	var key := "%s/%s" % [state["spin"], state["stopped"]]
	if key != _last_snapshot:
		_last_snapshot = key
		print("SLOT_STATE ", JSON.stringify(state))
	if Network.args.get("slot-role", "") == "observer":
		if state["spinning"] and not _sent_competing_request:
			_sent_competing_request = true
			_machine.request_spin.rpc_id(1)
			print("COMPETING_REQUEST")


func _drive() -> void:
	var player: Player
	while player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	player.position = Vector3(0, 0.9144, 20)
	player.net_position = player.position
	player.net_yaw = 0
	player.net_pitch = 0
	await get_tree().create_timer(0.5).timeout
	_machine.request_spin.rpc_id(1)
	await get_tree().create_timer(0.4).timeout
	if int(_machine.state["spin"]) != 0:
		push_error("Out-of-range request was accepted")
		get_tree().quit(1)
		return
	print("RANGE_REJECTED")
	player.position = Vector3(0, 0.9144, 8.5)
	player.net_position = player.position
	await get_tree().create_timer(0.5).timeout
	for spin: int in range(1, 6):
		# Two requests on the same frame must still create only one spin.
		_machine.request_spin.rpc_id(1)
		_machine.request_spin.rpc_id(1)
		print("REQUEST ", spin)
		while int(_machine.state["spin"]) < spin or _machine.state["spinning"]:
			await get_tree().process_frame
		if int(_machine.state["spin"]) != spin:
			push_error("Concurrent request started an extra spin")
			get_tree().quit(1)
			return
		await get_tree().create_timer(0.4).timeout
	print("DRIVER_DONE")
