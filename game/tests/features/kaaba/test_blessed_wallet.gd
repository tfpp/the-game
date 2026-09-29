extends GutTest


class CapturingWallet:
	extends PlayerMoney
	var sent: Dictionary = {}

	func _temporary() -> bool:
		return false

	func _account(_peer: int) -> int:
		return 123

	func _request(
		_account_id: int, _action: String, _id: String, extra: Dictionary = {}
	) -> Dictionary:
		sent = extra
		return {"reels": [2, 2, 2], "payout": 1000, "balance": 2900}


func test_authenticated_wallet_sends_blessings_and_applies_settlement() -> void:
	var wallet := CapturingWallet.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	var result: Dictionary = await wallet.spin(42, "blessed", 100, 3)
	assert_eq(wallet.sent, {"wager_cents": 100, "rerolls": 3})
	assert_eq(wallet.balances[42], 2900)
	assert_eq(result["payout"], 1000)
	await wallet.spin(42, "plain")
	assert_eq(wallet.sent["rerolls"], 0, "old callers keep their original odds")
	await wallet.spin(42, "bounded", 100, 99)
	assert_eq(wallet.sent["rerolls"], 5)
