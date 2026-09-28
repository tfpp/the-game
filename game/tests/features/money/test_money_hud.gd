extends GutTest
## The bottom-right wallet readout (features/money/money_hud.gd).

const MoneyHud := preload("res://features/money/money_hud.gd")
const MoneyScene := preload("res://features/money/feature.tscn")


func test_wallet_text_waits_for_the_balance() -> void:
	assert_eq(MoneyHud.wallet_text({}, 1), "…")
	assert_eq(MoneyHud.wallet_text({1: 1250}, 1), "$12.50")
	assert_eq(MoneyHud.wallet_text({2: 1250}, 1), "…")


func test_hud_shows_the_local_balance() -> void:
	var money := MoneyScene.instantiate() as PlayerMoney
	add_child_autofree(money)
	money.balances = {multiplayer.get_unique_id(): 4200}
	await wait_process_frames(1)
	assert_eq((money.get_node("Hud/Wallet/Amount") as Label).text, "$42.00")
