extends GutTest
## Exercise the real slot -> wallet -> signed request boundary without a live API.


class AccountWallet:
	extends PlayerMoney
	var sent: Dictionary = {}
	var response: Dictionary = {"reels": [0, 1, 2], "payout": 0, "balance": 1900}

	func _account(_peer: int) -> int:
		return 42

	func _temporary() -> bool:
		return false

	func _request(
		_account_id: int, action: String, _id: String, extra: Dictionary = {}
	) -> Dictionary:
		assert(action == "spin")
		sent = extra.duplicate()
		return response


func test_slot_passes_only_operators_blessings_and_consumes_only_on_win() -> void:
	var wallet := AccountWallet.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	var kaaba := preload("res://features/kaaba/feature.tscn").instantiate()
	add_child_autofree(kaaba)
	var prayer := kaaba.get_node("Prayer") as KaabaPrayer
	prayer.blessings = {1: 2, 2: 5}
	var trump := preload("res://features/casino_patrons/trump.tscn").instantiate() as Trump
	trump._bribes[1] = Trump.MAX_BRIBES
	add_child_autofree(trump)
	trump.set_physics_process(false)
	var machine := preload("res://features/slot_machine/machine.tscn").instantiate() as SlotMachine
	add_child_autofree(machine)
	machine.set_process(false)
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = Vector3(0, 0.9144, 2.5)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = player.position
	await get_tree().physics_frame
	machine.request_spin()
	assert_eq(wallet.sent, {"wager_cents": 100, "blessings": 2})
	assert_eq(prayer.blessings_for(1), 2, "a losing spin keeps blessings")
	machine._advance(4.0)
	wallet.response = {"error": "API unavailable"}
	machine.request_spin()
	assert_eq(prayer.blessings_for(1), 2, "a failed spin keeps blessings")
	wallet.response = {"reels": [2, 2, 2], "payout": 1000, "balance": 2800}
	machine.request_spin()
	assert_eq(prayer.blessings_for(1), 0, "a settled win spends the operator's blessings")
	assert_eq(prayer.blessings_for(2), 5, "another player's blessings remain")
	assert_eq(int(machine.state["spin"]), 2, "the failed request did not spin")
	assert_eq(int(wallet.balances[1]), 2800, "the account result owns the balance")


func test_old_wallet_callers_send_zero_blessings_and_excess_is_bounded() -> void:
	var wallet := AccountWallet.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	await wallet.spin(1, "plain")
	assert_eq(wallet.sent, {"wager_cents": 100, "blessings": 0})
	await wallet.spin(1, "bounded", 1500, 0, 999)
	assert_eq(wallet.sent, {"wager_cents": 1500, "blessings": 5})


func test_legacy_extra_roll_stays_small_and_separate_from_blessings() -> void:
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	var wins := 0
	for spin: int in 10000:
		wallet.balances[1] = 2000
		var result: Dictionary = await wallet.spin(1, "favor%d" % spin, 1, 1)
		wins += int(int(result.get("payout", 0)) > 0)
	assert_between(wins, 650, 920, "one extra ordinary roll wins about 7.84%, not 12%")
