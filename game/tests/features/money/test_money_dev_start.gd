extends GutTest


func test_headless_checks_keep_the_twenty_dollar_start() -> void:
	assert_false(PlayerMoney.local_dev(), "GUT runs headless")
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet._refresh(1)
	assert_eq(int(wallet.balances[1]), PlayerMoney.STARTING_CENTS)


func test_local_dev_start_is_one_hundred_thousand_dollars() -> void:
	assert_eq(PlayerMoney.DEV_STARTING_CENTS, 10_000_000)
	var wallet := PlayerMoney.new()
	wallet._starting_cents = PlayerMoney.DEV_STARTING_CENTS
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet._refresh(1)
	assert_eq(PlayerMoney.format_money(int(wallet.balances[1])), "$100,000.00")
