extends Node
## Standalone real-WebSocket test driver, never loaded by the game.


class WinningLuck:
	extends Node

	func favor_rerolls(_peer: int) -> int:
		return 1000


var _last_snapshot := ""
var _last_audio := 0
var _last_money := ""
var _sent_competing_request := false

@onready var _machine: SlotMachine = $Game/Features/slot_machine/Machine


func _ready() -> void:
	# Keep this probe independent of previously saved development player positions.
	$Game/Features/character_memory.queue_free()
	# Existing server hotbar retains a freed remote hand on disconnect (also
	# isolated by the Celeste probe); it is unrelated to slot/wallet networking.
	if Network.has_flag("server"):
		$Game/Features/weapon_hotbar.set_process(false)
	if Network.has_flag("server") and Network.has_flag("slot-force-win"):
		for existing: Node in get_tree().get_nodes_in_group(&"trump_favor"):
			existing.remove_from_group(&"trump_favor")
		var luck := WinningLuck.new()
		luck.add_to_group(&"trump_favor")
		add_child(luck)
	if Network.args.get("slot-role", "") == "driver":
		_drive()


func _process(_delta: float) -> void:
	if _machine._last_sound_spin != _last_audio:
		_last_audio = _machine._last_sound_spin
		print("SLOT_AUDIO ", _last_audio)
	var wallet := $Game/Features/money as PlayerMoney
	var money := JSON.stringify(wallet.balances)
	if money != _last_money:
		_last_money = money
		print("SLOT_MONEY ", money)
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
	player.position = _machine.to_global(Vector3(0, 0.9144, 2.5))
	player.net_position = player.position
	player.net_yaw = _machine.rotation.y
	await get_tree().create_timer(0.5).timeout
	var wallet := $Game/Features/money as PlayerMoney
	var peer := multiplayer.get_unique_id()
	while not wallet.balances.has(peer):
		await get_tree().process_frame
	for spin: int in range(1, 6):
		var before := int(wallet.balances[peer])
		var checked_hold := false
		# Two requests on the same frame must still create only one spin.
		_machine.request_spin.rpc_id(1)
		_machine.request_spin.rpc_id(1)
		print("REQUEST ", spin)
		while int(_machine.state["spin"]) < spin or _machine.state["spinning"]:
			await get_tree().process_frame
			if int(_machine.state["spin"]) == spin and int(_machine.state["stopped"]) == 1:
				if int(wallet.balances[peer]) != before - _machine.buy_in_cents:
					push_error("Prize exposed before the final reel")
					get_tree().quit(1)
					return
				checked_hold = true
		if int(_machine.state["spin"]) != spin:
			push_error("Concurrent request started an extra spin")
			get_tree().quit(1)
			return
		await get_tree().create_timer(0.4).timeout
		var expected := before - _machine.buy_in_cents + int(_machine.state["payout"])
		if not checked_hold or int(wallet.balances[peer]) != expected:
			push_error("Wallet did not reveal the prize with the completed result")
			get_tree().quit(1)
			return
		print("PAYOUT_REVEAL_PASS ", spin)
	print("DRIVER_DONE")
