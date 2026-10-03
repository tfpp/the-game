extends Node
## Real WebSocket requests, two bettors and a mid-fight late joiner.

var _role := ""
var _player: Player
@onready var _book: ChickenBettingBook = $Game/Features/chicken_betting/Room/Book


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	if Network.has_flag("server"):
		$Game/Features/weapon_hotbar.set_process(false)
	_role = str(Network.args.get("chicken-role", ""))
	if not _role.is_empty():
		_drive()


func _wait(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while not predicate.call():
		if Time.get_ticks_msec() > deadline:
			push_error("Chicken probe timed out: " + _role)
			get_tree().quit(1)
			return
		await get_tree().process_frame


func _drive() -> void:
	await _wait(func() -> bool: return get_tree().get_first_node_in_group(&"local_player") != null)
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	_player.set_physics_process(false)
	if _role == "late":
		await _wait(func() -> bool: return int(_book.state["round"]) > 0)
		if _book.state["birds"].size() != 2 or _book.state["bets"].size() != 2:
			push_error("Late join omitted birds or tickets")
			return
		print("LATE_FIGHT_SNAPSHOT_PASS")
		return
	var wallet := $Game/Features/money as PlayerMoney
	var peer := multiplayer.get_unique_id()
	await _wait(func() -> bool: return wallet.balances.has(peer))
	if _role == "driver":
		_book.entity.request_action(&"bet", {"side": 0, "stake": 100, "match": 1})
		await get_tree().create_timer(0.5).timeout
		if _book.state["phase"] != "idle":
			push_error("Out of range chicken ticket accepted")
			return
		print("RANGE_REJECTED")
	_player.position = _book.global_position + Vector3(0, 1, 1.5)
	_player.net_position = _player.position
	_player.net_yaw = 0
	_player.net_pitch = 0
	await get_tree().create_timer(0.5).timeout
	if _role == "driver":
		_book.entity.request_use()
	else:
		await _wait(func() -> bool: return _book.state["phase"] == "betting")
	await _wait(func() -> bool: return not _book.state["birds"].is_empty())
	if _book._menu != null:
		_book._menu.close()
	var side := 0 if _role == "driver" else 1
	var before := int(wallet.balances[peer])
	var payload := {"side": side, "stake": 100, "match": int(_book.state["match"])}
	_book.entity.request_action(&"bet", payload)
	_book.entity.request_action(&"bet", payload)
	await _wait(func() -> bool: return int(wallet.balances[peer]) == before - 100)
	print("UPFRONT_DEBIT_PASS")
	await _wait(func() -> bool: return _book.state["phase"] == "fighting")
	if _book.state["bets"].size() != 2:
		push_error("Competing bettors failed to share match")
		return
	print("FIGHT_STARTED")
	_book.entity.request_action(&"bet", {"side": 1 - side, "stake": 500, "match": 1})
	await _wait(func() -> bool: return _book.state["phase"] == "result")
	await _wait(func() -> bool: return str(_book.state["bets"][peer]["result"]).contains("Balance"))
	var payout := (
		ChickenFightSimulation.payout(100, _book.state["odds"][side])
		if int(_book.state["winner"]) == side
		else 0
	)
	await _wait(func() -> bool: return int(wallet.balances[peer]) == before - 100 + payout)
	if int(_book.state["bets"][peer]["side"]) != side:
		push_error("Locked ticket changed")
		return
	print("WALLET_RESULT_PASS ", _role)
	if _role == "driver":
		print("DRIVER_DONE")
