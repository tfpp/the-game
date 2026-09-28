extends Node
## Real WebSocket and real interpreter integration, driven by network_test.py.

var _role := ""
var _competed := false
var _last_tick := 0
var _last_error := ""
var _last_frame_ms := 0
var _frame_intervals: Array[int] = []

@onready var _cabinet: ScummArcadeCabinet = $Game/Features/scumm_arcade/MonkeyIsland


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_role = str(Network.args.get("arcade-role", "server"))
	_cabinet._emulator.frame_ready.connect(_record_frame)
	for machine: ScummArcadeCabinet in _machines():
		machine._emulator.frame_ready.connect(_record_machine.bind(machine.game_id))
	if _role == "driver":
		_drive()
	elif _role == "observer":
		_observe()
	elif _role == "restored":
		_check_restore()


func _process(_delta: float) -> void:
	for machine: ScummArcadeCabinet in _machines():
		assert(machine.local_error.is_empty(), machine.game_id + ": " + machine.local_error)
	if _last_error != _cabinet.local_error:
		_last_error = _cabinet.local_error
		print("ARCADE_ERROR ", _last_error)


func _record_frame(
	tick: int, checksum: int, _pixels: PackedByteArray, _pcm: PackedByteArray
) -> void:
	if tick % 250 == 0:
		print("CHECK ", tick, " ", checksum)
	var now := Time.get_ticks_msec()
	if tick > 50 and tick < 750 and _last_frame_ms > 0:
		_frame_intervals.append(now - _last_frame_ms)
	_last_frame_ms = now
	_last_tick = tick


func _local_player() -> Player:
	return get_tree().get_first_node_in_group(&"local_player") as Player


func _drive() -> void:
	while _local_player() == null:
		await get_tree().process_frame
	var player := _local_player()
	player.set_physics_process(false)
	player.position = _cabinet.position + Vector3(0, 0.9144, 14)
	player.net_position = player.position
	player.net_yaw = 0
	player.net_pitch = 0
	await get_tree().create_timer(0.5).timeout
	_cabinet.request_control.rpc_id(1)
	await get_tree().create_timer(0.3).timeout
	assert(_cabinet.state["owner"] == 0)
	print("RANGE_REJECTED")
	player.position.z = _cabinet.position.z + 2.5
	player.net_position = player.position
	while _cabinet.local_tick < 50:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_cabinet.request_control.rpc_id(1)
	while not _cabinet.controls_local():
		await get_tree().process_frame
	print("DRIVER_CONTROLS")
	for index: int in 10:
		_cabinet.keep_control.rpc_id(1)
		_cabinet.send_input([0, 60 + index * 15, 85, 0])
		_cabinet.send_input([1, 60 + index * 15, 85, 0])
		await get_tree().create_timer(0.04).timeout
		_cabinet.send_input([2, 60 + index * 15, 85, 0])
		_cabinet.send_input([5, 160, 100, 46])
		_cabinet.send_input([6, 160, 100, 46])
		await get_tree().create_timer(0.5).timeout
	while _cabinet.local_tick < 750:
		_cabinet.keep_control.rpc_id(1)
		await get_tree().create_timer(1).timeout
	_frame_intervals.sort()
	var median := _frame_intervals[_frame_intervals.size() / 2]
	assert(median < 80, "Push delivery must improve on 100 ms polling")
	print("NETWORK_FRAME_MS ", median)
	print("DRIVER_DONE")


func _observe() -> void:
	while _local_player() == null:
		await get_tree().process_frame
	var player := _local_player()
	player.set_physics_process(false)
	player.position = _cabinet.position + Vector3(0.4, 0.9144, 2.5)
	player.net_position = player.position
	player.net_yaw = 0
	player.net_pitch = 0
	while _cabinet.local_tick < 50:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_cabinet.request_control.rpc_id(1)
	_cabinet.request_input.rpc_id(1, 1, [1, 10, 10, 0])
	_cabinet.request_restart.rpc_id(1)
	await get_tree().create_timer(0.5).timeout
	assert(not _cabinet.controls_local())
	assert(_cabinet.state["epoch"] == 1)
	print("COMPETING_REJECTED")
	while int(_cabinet.state["owner"]) != 0:
		await get_tree().process_frame
	_cabinet.request_control.rpc_id(1)
	while not _cabinet.controls_local():
		await get_tree().process_frame
	print("HANDOFF_DONE")
	player.position = ScummArcadeRoom.ENTRANCE + Vector3(0, 0.95, 2)
	player.net_position = player.position
	await get_tree().create_timer(1).timeout
	for machine: ScummArcadeCabinet in _machines():
		assert(machine._emulator.status == "stopped")
	var paused := int(_cabinet.state["tick"])
	await get_tree().create_timer(0.5).timeout
	assert(int(_cabinet.state["tick"]) == paused)
	player.position = _cabinet.position + Vector3(0.4, 0.9144, 2.5)
	player.net_position = player.position
	while _cabinet.local_tick < paused:
		await get_tree().process_frame
	assert(_cabinet.local_error.is_empty())
	print("ROOM_RETURNED")


func _check_restore() -> void:
	while _local_player() == null:
		await get_tree().process_frame
	var player := _local_player()
	player.set_physics_process(false)
	player.position = _cabinet.position + Vector3(0, 0.9144, 2.5)
	player.net_position = player.position
	while _cabinet.local_tick < 750:
		await get_tree().process_frame
	assert(int(_cabinet.state["owner"]) == 0)
	assert(int(_cabinet.state.get("saved_tick", 0)) >= 750)
	print("RESTORED_PROGRESS")


func _record_machine(
	tick: int, checksum: int, _pixels: PackedByteArray, _pcm: PackedByteArray, game: String
) -> void:
	if tick % 250 == 0:
		print("FLOOR_CHECK ", game, " ", tick, " ", checksum)


func _machines() -> Array[ScummArcadeCabinet]:
	var result: Array[ScummArcadeCabinet] = []
	for node: Node in $Game/Features/scumm_arcade.get_children():
		if node is ScummArcadeCabinet:
			result.append(node as ScummArcadeCabinet)
	return result
