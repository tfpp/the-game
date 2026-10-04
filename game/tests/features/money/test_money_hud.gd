extends GutTest
## The bottom-right wallet readout (features/money/money_hud.gd).

const MoneyHud := preload("res://features/money/money_hud.gd")
const MoneyScene := preload("res://features/money/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const ModelsScene := preload("res://features/player_models/feature.tscn")


func test_wallet_text_waits_for_the_balance() -> void:
	assert_eq(MoneyHud.wallet_text({}, 1), "…")
	assert_eq(MoneyHud.wallet_text({1: 1250}, 1), "$12.50")
	assert_eq(MoneyHud.wallet_text({2: 1250}, 1), "…")


func test_hud_shows_the_local_balance() -> void:
	var money := MoneyScene.instantiate() as PlayerMoney
	add_child_autofree(money)
	money.balances = {multiplayer.get_unique_id(): 4200}
	await wait_process_frames(1)
	assert_eq((money.get_node("Hud/Wallet/Row/Amount") as Label).text, "$42.00")


func test_temporary_income_follows_model_choice() -> void:
	var money := MoneyScene.instantiate() as PlayerMoney
	add_child_autofree(money)
	money.set_process(false)
	var models := ModelsScene.instantiate() as PlayerModels
	add_child_autofree(models)
	models.set_process(false)
	var player := PlayerScene.instantiate() as Player
	player.name = "2"
	player.set_multiplayer_authority(2)
	add_child_autofree(player)
	player.set_process(false)
	var original := Network.peer_accounts.duplicate(true)
	Network.peer_accounts[2] = {"account_id": 0}
	money._process(30.0)
	models.body_types = {2: "girl"}
	money._process(30.0)
	assert_eq(int(money.balances[2]), 2462)
	money._process(60.0)
	assert_eq(int(money.balances[2]), 2887)
	Network.peer_accounts = original
