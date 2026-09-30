extends Node
## Real WebSocket roulette check, never loaded by the game. Roles (--roulette-role):
## server, a and b (seated bettors) and late (joins mid-round). See network_check.py.

const BETTING_S := 12.0

var _role := ""
var _results: Array[String] = []
var _saw_bets := false
var _reported := false

@onready var _table: RouletteTable = $Game/Features/roulette/Table
@onready var _wallet: PlayerMoney = $Game/Features/money


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_role = str(Network.args.get("roulette-role", "server"))
	_table.betting_seconds = BETTING_S
	_table.entity.request_finished.connect(
		func(action: StringName, result: NetworkedEntity.Result) -> void:
			_results.append("%s=%d" % [action, result])
	)
	if _role == "a" or _role == "b":
		_drive.call_deferred()


func _process(_delta: float) -> void:
	if FileAccess.file_exists(str(Network.args.get("probe-stop", ""))):
		get_tree().quit()
		return
	var state := _table.state
	if _role == "late" and not _saw_bets and state["phase"] == RouletteTable.PHASE_BETTING:
		if (state["bets"] as Dictionary).size() == 2:
			_saw_bets = true
			print(
				"ROULETTE_LATE_SAW ",
				JSON.stringify(state["seats"]),
				" ",
				JSON.stringify(state["bets"])
			)
	if state["phase"] == RouletteTable.PHASE_RESULT and not _reported:
		var settled := true
		for result: Dictionary in (state["results"] as Dictionary).values():
			settled = settled and result["status"] != "settling"
		if settled and not (state["results"] as Dictionary).is_empty():
			_reported = true
			print(
				(
					"ROULETTE_RESULT number=%d results=%s balances=%s"
					% [
						state["number"],
						JSON.stringify(state["results"]),
						JSON.stringify(_wallet.balances)
					]
				)
			)
	if _reported and _role != "server" and state["phase"] == RouletteTable.PHASE_IDLE:
		if (state["seats"] as Array) == [0, 0, 0] and not _results.has("released"):
			_results.append("released")
			print("ROULETTE_RELEASED ", " ".join(_results))


func _drive() -> void:
	var player: Player
	while player == null or not _wallet.balances.has(multiplayer.get_unique_id()):
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	var x := 0.3 if _role == "a" else 1.2
	player.global_position = _table.to_global(Vector3(x, 0.9144, -2.4))
	player.net_position = player.global_position
	player.yaw = _table.seat_yaw()
	player.net_yaw = player.yaw
	player.pitch = -0.3
	player.net_pitch = player.pitch
	if _role == "b":
		while _table.seat_of(_other_peer()) < 0:
			await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_table.use()
	var peer := multiplayer.get_unique_id()
	while _table.seat_of(peer) < 0:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var seat := _table.seat_of(peer)
	if player.global_position.distance_to(_table.seat_position(seat)) > 0.05:
		_fail("not moved to seat %d" % seat)
	var view := _table.get_node("View") as RouletteTableView
	if view.seat_view == null or player.is_physics_processing():
		_fail("seated player can still move")
	view.open_betting()
	if view.screen == null:
		_fail("bet view did not open")
	# Forged identity and chips the wallet cannot cover are refused.
	_table.entity.request_action(&"bet", {"spot": "red", "cents": 100, "peer": 1})
	_table.request_bet("black", 5000)
	if _role == "a":
		_table.request_bet("red", 100)
		_table.request_bet("17", 500)
		_table.request_bet("0-37", 100)
		_table.request_undo()
	else:
		_table.request_bet("black", 100)
		_table.request_bet("dozen2", 500)
	while RouletteBets.total(_table.placements_for(peer)) != 600:
		await get_tree().process_frame
	print("ROULETTE_BETS_PLACED %s %s" % [_role, JSON.stringify(_table.placements_for(peer))])
	while _table.phase() != RouletteTable.PHASE_SPINNING:
		await get_tree().process_frame
	_table.request_leave()
	await get_tree().create_timer(0.5).timeout
	if _table.seat_of(peer) < 0:
		_fail("left mid-spin with bets riding")
	print("ROULETTE_DRIVER_DONE ", " ".join(_results))


func _other_peer() -> int:
	for seat_peer: int in _table.state["seats"]:
		if seat_peer != 0 and seat_peer != multiplayer.get_unique_id():
			return seat_peer
	return -1


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
