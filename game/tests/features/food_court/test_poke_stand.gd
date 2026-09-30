extends GutTest

const STAND := preload("res://features/food_court/poke_stand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var _stand: PokeStand
var _player: Player
var _hand: Hand
var _wallet: PlayerMoney
var _drops: DropRecorder


class DropRecorder:
	extends Node
	var items: Array[String] = []
	var landing := Vector3.ZERO

	func spawn_thrown_item(id: String, _from: Vector3, to: Vector3) -> void:
		items.append(id)
		landing = to


class SlowWallet:
	extends PlayerMoney
	signal complete
	var calls := 0
	var total := 0

	func charge(_peer: int, _id: String, amount: int) -> Dictionary:
		calls += 1
		total = amount
		await complete
		return {"balance": 10000 - amount}


func before_each() -> void:
	_stand = STAND.instantiate() as PokeStand
	add_child_autofree(_stand)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = Vector3(0, 1, 1.7)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 10000}
	_drops = DropRecorder.new()
	_drops.add_to_group(&"holdables_root")
	add_child_autofree(_drops)


func after_each() -> void:
	_stand.get_node("Menu")._close(false)
	await get_tree().process_frame


func test_tip_totals_are_exact_integer_cents() -> void:
	var expected: Array[int] = [3335, 3480, 3625, 3770, 3915, 4060]
	for index: int in PokeStand.TIPS.size():
		assert_eq(PokeStand.total_cents(PokeStand.TIPS[index]), expected[index])


func test_order_charges_price_plus_tip_and_food_can_be_eaten() -> void:
	assert_eq(_request(15), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 6665)
	assert_eq(_hand.net_item_id, "poke_bowl")
	assert_eq(_request(15), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 6665)
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")
	assert_true(_drops.items.is_empty())


func test_max_tip_and_occupied_hand_use_existing_backpack() -> void:
	_hand.inventory().collect("kebab")
	_request(40)
	assert_eq(_wallet.balances[1], 5940)
	assert_eq(_hand.net_item_id, "kebab")
	assert_eq(_hand.inventory().backpack[0], "poke_bowl")


func test_insufficient_funds_and_full_bag_never_deliver_or_spend() -> void:
	_wallet.balances = {1: 3334}
	_request(15)
	assert_eq(_wallet.balances[1], 3334)
	assert_eq(_hand.net_item_id, "")
	_wallet.balances = {1: 10000}
	_stand._next_order.clear()
	for index: int in 9:
		_hand.inventory().collect("banana")
	assert_eq(_request(15), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 10000)
	assert_eq(_hand.inventory().backpack.count("banana"), 8)


func test_rejects_forged_peer_tip_price_and_range() -> void:
	for payload: Dictionary in [
		{},
		{"tip": 0},
		{"tip": 14},
		{"tip": 41},
		{"tip": 16},
		{"tip": 15.0},
		{"tip": "15"},
		{"tip": 15, "peer": 1},
		{"tip": 15, "price": 1}
	]:
		assert_eq(_stand.entity._evaluate(1, &"order", payload), NetworkedEntity.Result.DENIED)
	assert_eq(_stand.entity._evaluate(77, &"order", {"tip": 15}), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, 1, -1)
	assert_eq(_request(15), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, 1, 8)
	assert_eq(_request(15), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 10000)


func test_use_opens_modal_without_spending_and_close_restores_controls() -> void:
	_stand.use()
	var menu: CanvasLayer = _stand.get_node("Menu")
	assert_true(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing)
	assert_eq(_wallet.balances[1], 10000)
	assert_eq(menu._buttons.size(), 6)
	assert_string_contains(menu._buttons[0].text, "$33.35")
	menu._close()
	assert_false(menu.is_in_group(&"modal_ui"))
	assert_true(Controls.playing)


func test_delayed_charge_blocks_duplicates_but_not_another_peer() -> void:
	var slow := _slow_wallet()
	_request(25)
	assert_eq(slow.calls, 1)
	assert_eq(_request(40), NetworkedEntity.Result.DENIED)
	var second := PLAYER.instantiate() as Player
	second.name = "2"
	second.set_multiplayer_authority(2)
	add_child_autofree(second)
	second.set_physics_process(false)
	second.net_position = _player.net_position
	assert_true(_stand._may_order(2, {"tip": 15}))
	slow.complete.emit()
	assert_eq(slow.total, 3625)
	assert_eq(_hand.net_item_id, "poke_bowl")
	assert_false(_stand._busy.has(1))


func test_bag_filling_during_payment_leaves_one_public_pickup() -> void:
	var slow := _slow_wallet()
	_request(15)
	for index: int in 9:
		_hand.inventory().collect("banana")
	slow.complete.emit()
	assert_eq(_drops.items, ["poke_bowl"])
	assert_eq(_drops.landing, _stand.to_global(Vector3(0, 0, 1.25)))
	assert_eq(_hand.net_item_id, "banana")


func test_disconnected_buyer_does_not_deliver_to_replacement_peer() -> void:
	var slow := _slow_wallet()
	_request(15)
	_player.free()
	slow.complete.emit()
	assert_eq(_drops.items, ["poke_bowl"])
	assert_eq(_hand.net_item_id, "")


func test_respawn_during_charge_keeps_normal_inventory_delivery() -> void:
	var slow := _slow_wallet()
	_request(15)
	_player.net_position = Vector3(0, 1, 200)
	slow.complete.emit()
	assert_eq(_hand.net_item_id, "poke_bowl")
	assert_true(_drops.items.is_empty())


func test_session_reset_ignores_old_payment_completion() -> void:
	var slow := _slow_wallet()
	_request(15)
	_stand.entity.session_reset.emit(Network.Mode.OFFLINE)
	slow.complete.emit()
	assert_eq(_hand.net_item_id, "")
	assert_true(_drops.items.is_empty())
	assert_true(_stand._busy.is_empty())


func test_late_join_item_snapshot_uses_existing_server_owned_sync() -> void:
	_request(15)
	var late := HAND.instantiate() as Hand
	late.peer_id = 9
	add_child_autofree(late)
	late.net_item_id = _hand.net_item_id
	assert_eq(late.net_item_id, "poke_bowl")
	var sync := late.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:net_item_id")))
	var view := ItemCatalog.create_view(late.net_item_id)
	add_child_autofree(view)
	assert_true(view.has_node("Rice"))
	assert_true(view.has_node("Grip"))
	assert_true(view.has_node("SupportGrip"))


func test_non_authority_cannot_apply_purchase() -> void:
	_stand.entity.set_multiplayer_authority(77)
	assert_ne(_request(15), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 10000)
	assert_eq(_hand.net_item_id, "")


func test_order_buttons_disable_keep_close_focus_and_menu_request_stays_paused() -> void:
	_stand.use()
	var menu: CanvasLayer = _stand.get_node("Menu")
	menu._buy(15)
	assert_eq(_hand.net_item_id, "poke_bowl")
	assert_string_contains(menu._status.text, "$33.35 paid")
	for button: Button in menu._buttons:
		assert_true(button.disabled)
	assert_true(menu._close_button.has_focus())
	Controls.menu_requested.emit()
	assert_false(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing, "The controller Start menu keeps gameplay paused")


func _request(tip: int) -> NetworkedEntity.Result:
	return _stand.entity._evaluate(1, &"order", {"tip": tip})


func _slow_wallet() -> SlowWallet:
	_wallet.remove_from_group(&"player_money")
	var slow := SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	return slow
