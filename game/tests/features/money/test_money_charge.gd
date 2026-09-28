extends GutTest

var _wallet: PlayerMoney


func before_each() -> void:
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)


func test_charge_deducts_from_the_temporary_wallet() -> void:
	var result: Dictionary = await _wallet.charge(1, "one", 500)
	assert_false(result.has("error"))
	assert_eq(int(result["balance"]), 1500)
	assert_eq(int(_wallet.balances[1]), 1500)


func test_charge_rejects_without_touching_the_balance() -> void:
	var result: Dictionary = await _wallet.charge(1, "one", 999999)
	assert_true(result.has("error"))
	assert_false(_wallet.balances.has(1))
