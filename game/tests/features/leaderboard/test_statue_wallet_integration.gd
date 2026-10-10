extends GutTest
## Exercise the actual heartbeat consumer rather than constructing another timer.


class FakeWallet:
	extends PlayerMoney
	var response := {"balance": 2000, "playtime_seconds": 600}
	var requested_action := ""

	func _temporary() -> bool:
		return false

	func _request(
		_account_id: int, action: String, _id: String, _extra: Dictionary = {}
	) -> Dictionary:
		requested_action = action
		return response


func after_each() -> void:
	Network.peer_accounts = {}


func test_existing_balance_refresh_consumes_optional_api_time_and_preserves_income() -> void:
	Network.peer_accounts = {2: {"account_id": 42, "name": "Regular"}}
	var wallet := FakeWallet.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	await wallet._refresh(2)
	assert_eq(wallet.requested_action, "balance")
	assert_eq(wallet.playtime_for(2), 600)
	assert_eq(wallet.balances[2], 2000)
	wallet.response = {"balance": 2500, "playtime_seconds": 660}
	await wallet._refresh(2)
	assert_eq(wallet.balances[2], 2500, "Existing heartbeat income remains authoritative")
	assert_eq(wallet.playtime_for(2), 660, "Absolute time replaces, never adds")
	wallet.response = {"balance": 2600}
	await wallet._refresh(2)
	assert_eq(wallet.balances[2], 2600, "Older APIs still update money")
	assert_eq(wallet.playtime_for(2), 660, "Missing time retains the last snapshot")
	Network.peer_accounts[2] = {"account_id": 43, "name": "Replacement"}
	assert_eq(wallet.playtime_for(2), -1)


func test_portrait_reads_equipped_clothing_and_hat_without_modifying_inventory() -> void:
	var hand := load("res://features/holdables/hand.tscn").instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	var inventory := hand.inventory()
	inventory.shirt = "shirt:1"
	inventory.pants = "pants:2"
	inventory.hat = ClothingCatalog.TOP_HAT
	var portrait := OnlineStatue.portrait_for(get_tree(), 1)
	assert_true(OnlineStatue.valid_portrait(portrait))
	assert_eq(portrait["shirt"], inventory.shirt)
	assert_eq(portrait["pants"], inventory.pants)
	assert_eq(portrait["hat"], inventory.hat)
	var statue := (
		load("res://features/leaderboard/online_statue.tscn").instantiate() as OnlineStatue
	)
	add_child_autofree(statue)
	statue.set_process(false)
	statue.champion = {"name": "Dressed guest", "seconds": 42, "portrait": portrait}
	var model := statue.get_node("Portrait") as BlockPlayerModel
	assert_eq(model.shirt_id, inventory.shirt)
	assert_eq(model.pants_id, inventory.pants)
	assert_eq(model.hat_id, inventory.hat)
	assert_eq(inventory.shirt, "shirt:1")
	await wait_process_frames(1)
