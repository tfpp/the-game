extends Node

var _last := ""
var _competed := false
@onready var _table: CrapsTable = $Game/Features/craps/Table


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	if Network.args.get("craps-role", "") == "driver":
		_drive()


func _process(_delta: float) -> void:
	var serializable := _table.state.duplicate(true)
	var dice: Vector2i = serializable["dice"]
	serializable["dice"] = [dice.x, dice.y]
	var snapshot := JSON.stringify(serializable)
	if snapshot != _last:
		_last = snapshot
		print("CRAPS_STATE ", snapshot)
	if Network.args.get("craps-role", "") == "observer":
		if _table.state["rolling"] and not _competed:
			_competed = true
			_table.request_roll.rpc_id(1)
			print("COMPETING_REQUEST")


func _drive() -> void:
	var player: Player
	while player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	player.position = Vector3(0, 1, 20)
	player.net_position = player.position
	player.net_yaw = 0
	player.net_pitch = 0
	await get_tree().create_timer(0.5).timeout
	_table.request_roll.rpc_id(1)
	await get_tree().create_timer(0.4).timeout
	if int(_table.state["roll"]) != 0:
		push_error("Out-of-range request accepted")
		return
	print("RANGE_REJECTED")
	player.position = Vector3(-6, -0.5856, 2.5)
	player.net_position = player.position
	await get_tree().create_timer(0.5).timeout
	for roll: int in range(1, 6):
		_table.request_roll.rpc_id(1)
		_table.request_roll.rpc_id(1)
		print("REQUEST ", roll)
		while int(_table.state["roll"]) < roll or _table.state["rolling"]:
			await get_tree().process_frame
		if int(_table.state["roll"]) != roll:
			push_error("Duplicate request accepted")
			return
		await get_tree().create_timer(0.4).timeout
	print("DRIVER_DONE")
