extends GutTest

const STAND := preload("res://features/bar_companion/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var _stand: Node3D
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
	var bar := STAND.instantiate()
	add_child_autofree(bar)
	_stand = bar.get_node("Bartender")
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = _stand.global_position + Vector3(0, -1.1, 0.8)
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
	_stand.get_node("ShopMenu")._close(false)
	_stand.get_node("ShopMenu/Dialogue").close(false)
	await get_tree().process_frame


func test_order_charges_price_and_beer_can_be_drunk() -> void:
	assert_eq(_request("beer"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 9500)
	assert_eq(_hand.net_item_id, "beer")
	for remaining: int in [3, 2, 1]:
		assert_eq(ItemCatalog.uses_remaining(_hand.net_item_id), remaining)
		_hand.request_primary_action()
		_hand._process(3.1)
	assert_eq(_hand.net_item_id, "")
	assert_eq(_wallet.balances[1], 9500, "One purchase pays for all three sips")
	assert_true(_drops.items.is_empty())


func test_cigarette_and_occupied_hand_use_existing_backpack() -> void:
	_hand.inventory().collect("kebab")
	_request("cigarette")
	assert_eq(_wallet.balances[1], 9800)
	assert_eq(_hand.net_item_id, "kebab")
	assert_eq(_hand.inventory().backpack[0], "cigarette")


func test_insufficient_funds_and_full_bag_never_deliver_or_spend() -> void:
	_wallet.balances = {1: 100}
	_request("beer")
	assert_eq(_wallet.balances[1], 100)
	assert_eq(_hand.net_item_id, "")
	_wallet.balances = {1: 10000}
	_stand._pending.clear()
	for index: int in 9:
		_hand.inventory().collect("banana")
	assert_eq(_request("beer"), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 10000)
	assert_eq(_hand.inventory().backpack.count("banana"), 8)


func test_rejects_forged_stock_price_peer_and_range() -> void:
	for payload: Dictionary in [
		{},
		{"item": "unknown"},
		{"item": "beer:2"},
		{"item": 1},
		{"item": "beer", "price": 1},
		{"item": "beer", "peer": 1}
	]:
		assert_eq(_stand._talk._evaluate(1, &"order", payload), NetworkedEntity.Result.DENIED)
	assert_eq(_stand._talk._evaluate(77, &"order", {"item": "beer"}), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, 1, 8)
	assert_eq(_request("beer"), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 10000)


func test_use_opens_modal_without_spending_and_close_restores_controls() -> void:
	_stand.use()
	var menu: CanvasLayer = _stand.get_node("ShopMenu")
	var dialogue := menu.get_node("Dialogue") as NpcDialogue
	assert_true(dialogue.is_open(), "The bartender greets you first")
	assert_eq(dialogue.action_labels(), PackedStringArray(["Buy", "Ask", "Leave"]))
	assert_true(dialogue.is_in_group(&"modal_ui"))
	(dialogue.get_node("Root/Panel").find_child("Buy", true, false) as Button).pressed.emit()
	assert_false(dialogue.is_open())
	assert_true(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing)
	assert_eq(_wallet.balances[1], 10000)
	assert_eq(menu._buttons.size(), 3)
	assert_string_contains(menu._buttons[0].text, "$5")
	menu._close()
	assert_false(menu.is_in_group(&"modal_ui"))
	assert_true(Controls.playing)


func test_delayed_charge_blocks_duplicates_but_not_another_peer() -> void:
	var slow := _slow_wallet()
	_request("beer")
	assert_eq(slow.calls, 1)
	assert_eq(_request("cigarette"), NetworkedEntity.Result.DENIED)
	var second := PLAYER.instantiate() as Player
	second.name = "2"
	second.set_multiplayer_authority(2)
	add_child_autofree(second)
	second.set_physics_process(false)
	second.net_position = _player.net_position
	assert_true(_stand._may_order(2, {"item": "beer"}))
	slow.complete.emit()
	assert_eq(slow.total, 500)
	assert_eq(_hand.net_item_id, "beer")
	assert_false(_stand._pending.has(1))


func test_bag_filling_during_payment_leaves_one_public_pickup() -> void:
	var slow := _slow_wallet()
	_request("beer")
	for index: int in 9:
		_hand.inventory().collect("banana")
	slow.complete.emit()
	assert_eq(_drops.items, ["beer"])
	assert_eq(_drops.landing, _stand.global_position + Vector3(0, -1.1, 1.25))
	assert_eq(_hand.net_item_id, "banana")


func test_disconnected_buyer_does_not_deliver_to_replacement_peer() -> void:
	var slow := _slow_wallet()
	_request("beer")
	_player.free()
	slow.complete.emit()
	assert_eq(_drops.items, ["beer"])
	assert_eq(_hand.net_item_id, "")


func test_respawn_during_charge_keeps_normal_inventory_delivery() -> void:
	var slow := _slow_wallet()
	_request("beer")
	_player.net_position = Vector3(0, 1, 200)
	slow.complete.emit()
	assert_eq(_hand.net_item_id, "beer")
	assert_true(_drops.items.is_empty())


func test_session_reset_ignores_old_payment_completion() -> void:
	var slow := _slow_wallet()
	_request("beer")
	_stand._talk.session_reset.emit(Network.Mode.OFFLINE)
	slow.complete.emit()
	assert_eq(_hand.net_item_id, "")
	assert_true(_drops.items.is_empty())
	assert_true(_stand._pending.is_empty())


func test_late_join_item_snapshot_uses_existing_server_owned_sync() -> void:
	_request("beer")
	var late := HAND.instantiate() as Hand
	late.peer_id = 9
	add_child_autofree(late)
	late.net_item_id = _hand.net_item_id
	assert_eq(late.net_item_id, "beer")
	var sync := late.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:net_item_id")))
	var view := ItemCatalog.create_view(late.net_item_id)
	add_child_autofree(view)
	assert_true(view.has_node("Bottle"))
	assert_true(view.has_node("Grip"))


func test_non_authority_cannot_apply_purchase() -> void:
	_stand._talk.set_multiplayer_authority(77)
	assert_ne(_request("beer"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 10000)
	assert_eq(_hand.net_item_id, "")


func test_order_buttons_disable_keep_close_focus_and_menu_request_stays_paused() -> void:
	_stand.use()
	var menu: CanvasLayer = _stand.get_node("ShopMenu")
	menu._open_shop()
	menu._buy("beer")
	assert_eq(_hand.net_item_id, "beer")
	assert_string_contains(menu._status.text, "Added to inventory")
	for button: Button in menu._buttons:
		assert_true(button.disabled)
	assert_true(menu._close_button.has_focus())
	Controls.menu_requested.emit()
	assert_false(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing, "The controller Start menu keeps gameplay paused")


func _request(item: String) -> NetworkedEntity.Result:
	return _stand._talk._evaluate(1, &"order", {"item": item})


func _slow_wallet() -> SlowWallet:
	_wallet.remove_from_group(&"player_money")
	var slow := SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	return slow


func test_bartender_ask_answers_and_leave_resumes_without_buying() -> void:
	_stand.use()
	var dialogue := _stand.get_node("ShopMenu/Dialogue") as NpcDialogue
	var line := (dialogue.find_child("Line", true, false) as Label).text
	(dialogue.find_child("Ask", true, false) as Button).pressed.emit()
	assert_ne((dialogue.find_child("Line", true, false) as Label).text, line)
	assert_true(dialogue.is_open(), "Ask keeps the conversation going")
	(dialogue.find_child("Leave", true, false) as Button).pressed.emit()
	assert_false(dialogue.is_open())
	assert_false(dialogue.is_in_group(&"modal_ui"))
	assert_false(_stand.get_node("ShopMenu").is_in_group(&"modal_ui"))
	assert_true(Controls.playing)
	assert_eq(_wallet.balances[1], 10000)
