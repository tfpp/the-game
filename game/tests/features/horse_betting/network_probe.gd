extends Node
## Full game WebSocket integration, with real authenticated component requests.

var _role := ""
var _player: Player
@onready var _race: HorseBetting = $Game/Features/horse_betting


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	if Network.has_flag("server"):
		$Game/Features/weapon_hotbar.set_process(false)
	_role = str(Network.args.get("horse-role", ""))
	if not _role.is_empty():
		_drive()


func _wait(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 35000
	while not predicate.call():
		if Time.get_ticks_msec() > deadline:
			push_error("Horse probe timed out: " + _role)
			get_tree().quit(1)
			return
		await get_tree().process_frame


func _drive() -> void:
	await _wait(func() -> bool: return get_tree().get_first_node_in_group(&"local_player") != null)
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	_player.set_physics_process(false)
	if _role == "late":
		await _wait(func() -> bool: return _race.state["phase"] == "racing")
		await _wait(func() -> bool: return _race.progress[0] > 0.0)
		if _race.state["bets"].size() != 2 or int(_race.state["round"]) != 1:
			push_error("Late join omitted race tickets")
			get_tree().quit(1)
			return
		print("LATE_RACE_SNAPSHOT_PASS")
		return
	var wallet := $Game/Features/money as PlayerMoney
	var peer := multiplayer.get_unique_id()
	await _wait(func() -> bool: return wallet.balances.has(peer))
	if _role == "driver":
		_player.position = Vector3(0, 1, 16)
		_player.net_position = _player.position
		await get_tree().create_timer(0.5).timeout
		_race.entity.request_action(&"bet", {"horse": 0, "stake": 100, "round": 1})
		await get_tree().create_timer(0.5).timeout
		if _race.state["phase"] != "idle":
			push_error("Out of range horse ticket accepted")
			get_tree().quit(1)
			return
		print("RANGE_REJECTED")
	_player.position = _race.to_global(Vector3(0, 0.9144, 2.4))
	_player.net_position = _player.position
	_player.net_yaw = _race.rotation.y
	_player.net_pitch = 0
	await get_tree().create_timer(0.5).timeout
	if _role == "observer":
		await _wait(func() -> bool: return _race.state["phase"] == "betting")
	var horse := 0 if _role == "driver" else 1
	var before := int(wallet.balances[peer])
	var payload := {"horse": horse, "stake": 100, "round": _race.ticket_round()}
	_race.entity.request_action(&"bet", payload)
	_race.entity.request_action(&"bet", payload)
	await _wait(func() -> bool: return _race.state["bets"].has(peer))
	await _wait(func() -> bool: return _race.state["phase"] == "racing")
	if _race.state["bets"].size() != 2:
		push_error("Competing bettors did not join same race")
		get_tree().quit(1)
		return
	print("RACE_STARTED")
	_race.entity.request_action(&"bet", {"horse": 3, "stake": 500, "round": 1})
	await _wait(func() -> bool: return _race.state["phase"] == "result")
	await _wait(
		func() -> bool:
			return (
				str(_race.state["results"].get(peer, "")).contains("ticket")
				or str(_race.state["results"].get(peer, "")).begins_with("Won")
			)
	)
	await get_tree().create_timer(0.4).timeout
	var expected := before - 100 + (400 if int(_race.state["winner"]) == horse else 0)
	if int(wallet.balances[peer]) != expected or int(_race.state["bets"][peer]["horse"]) != horse:
		push_error("Horse wallet payout or locked ticket mismatch")
		get_tree().quit(1)
		return
	print("WALLET_RESULT_PASS ", _role)
	if _role == "driver":
		print("DRIVER_DONE")
