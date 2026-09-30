extends GutTest

const MACHINE := preload("res://features/slot_machine/machine.tscn")


class AccountWallet:
	extends PlayerMoney
	var account := 42
	var response: Dictionary = {"reels": [0, 0, 0], "payout": 3000, "balance": 4900}

	func _account(_peer: int) -> int:
		return account

	func _temporary() -> bool:
		return false

	func _request(
		_account_id: int, _action: String, _id: String, _extra: Dictionary = {}
	) -> Dictionary:
		return response


var _wallet: AccountWallet


func before_each() -> void:
	_wallet = AccountWallet.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances[1] = 2000


func test_wallet_and_notice_wait_for_the_final_reel_and_reveal_once() -> void:
	var machine := MACHINE.instantiate() as SlotMachine
	add_child_autofree(machine)
	machine.set_process(false)
	var result: Dictionary = await _wallet.spin_animated(1, "win")
	machine._prize_id = "win"
	var reels: Array[int] = []
	reels.assign(result["reels"])
	machine._begin_spin(1, "Alice", reels, int(result["payout"]))
	assert_eq(int(_wallet.balances[1]), 1900, "Only the buy-in is visible")
	machine._advance(1.21)
	machine._advance(0.9)
	assert_eq(int(_wallet.balances[1]), 1900, "Two stopped reels cannot reveal the prize")
	assert_eq(machine._last_sound_spin, 0)
	machine._advance(0.9)
	assert_eq(int(_wallet.balances[1]), 4900)
	assert_eq(machine._last_sound_spin, 1, "Reveal accompanies the celebration event")
	machine._advance(4.0)
	_wallet.reveal_spin(1, "win")
	assert_eq(int(_wallet.balances[1]), 4900, "No duplicate payout")
	assert_false(_wallet._busy.has(1))


func test_other_transactions_and_refreshes_cannot_expose_or_spend_held_prize() -> void:
	await _wallet.spin_animated(1, "win")
	assert_true((await _wallet.charge(1, "purchase", 100)).has("error"))
	assert_true((await _wallet.credit_coin(1, "coin", "Coin")).has("error"))
	assert_true((await _wallet.spin_animated(1, "second")).has("error"))
	assert_true(_wallet._busy.has(1), "The heartbeat skips busy wallets")
	_wallet.reveal_spin(1, "wrong-id")
	assert_eq(int(_wallet.balances[1]), 1900)
	_wallet.reveal_spin(1, "win")
	assert_eq(int(_wallet.balances[1]), 4900)


func test_temporary_wallet_income_is_not_overwritten_by_reveal() -> void:
	_wallet.remove_from_group(&"player_money")
	var temporary := PlayerMoney.new()
	add_child_autofree(temporary)
	temporary.set_process(false)
	temporary.balances[1] = 2000
	var result: Dictionary = await temporary.spin_animated(1, "offline", 100, 1000)
	assert_gt(int(result["payout"]), 0)
	assert_eq(int(temporary.balances[1]), 1900)
	# Same additive path as the minute income tick.
	temporary._set_balance(1, int(temporary.balances[1]) + 500)
	temporary.reveal_spin(1, "offline")
	assert_eq(int(temporary.balances[1]), int(result["balance"]) + 500)


func test_failed_spin_and_loss_release_correctly() -> void:
	_wallet.response = {"error": "Unavailable"}
	assert_true((await _wallet.spin_animated(1, "failure")).has("error"))
	assert_false(_wallet._busy.has(1))
	assert_true(_wallet._animated_spins.is_empty())
	_wallet.response = {"reels": [0, 1, 2], "payout": 0, "balance": 1900}
	await _wallet.spin_animated(1, "loss")
	_wallet.reveal_spin(1, "loss")
	assert_eq(int(_wallet.balances[1]), 1900)
	assert_false(_wallet._busy.has(1))


func test_reset_and_disconnected_account_cannot_receive_an_old_reveal() -> void:
	await _wallet.spin_animated(1, "old")
	_wallet._reset(Network.Mode.OFFLINE)
	_wallet.balances[1] = 2000
	_wallet.reveal_spin(1, "old")
	assert_eq(int(_wallet.balances[1]), 2000)
	await _wallet.spin_animated(1, "disconnected")
	_wallet.account = 99
	_wallet.reveal_spin(1, "disconnected")
	assert_eq(int(_wallet.balances[1]), 1900, "Never credit a replacement account")
	assert_false(_wallet._busy.has(1))


func test_removed_machine_releases_wallet_and_legacy_spin_still_settles_immediately() -> void:
	await _wallet.spin_animated(1, "removed")
	var machine := MACHINE.instantiate() as SlotMachine
	add_child(machine)
	machine.set_process(false)
	machine._prize_peer = 1
	machine._prize_id = "removed"
	machine.free()
	assert_eq(int(_wallet.balances[1]), 4900)
	assert_false(_wallet._busy.has(1))
	await _wallet.spin(1, "legacy")
	assert_eq(int(_wallet.balances[1]), 4900)
	assert_false(_wallet._busy.has(1))
