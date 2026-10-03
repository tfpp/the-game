extends GutTest

const MALL := preload("res://features/strip_mall/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const Fixtures := preload("res://tests/features/food_court/test_poke_stand.gd")

var _room: StreamedRoom
var _player: Player
var _hand: Hand
var _wallet: PlayerMoney
var _drops: Fixtures.DropRecorder


func before_each() -> void:
	var mall := MALL.instantiate()
	add_child_autofree(mall)
	_room = mall.get_node("Room") as StreamedRoom
	_room.set_physics_process(false)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 10000}
	_drops = Fixtures.DropRecorder.new()
	_drops.add_to_group(&"holdables_root")
	add_child_autofree(_drops)


func after_each() -> void:
	for stand: PokeStand in _shops():
		stand.get_node("Menu")._close(false)
	Controls.start()
	await get_tree().process_frame


func test_both_counters_charge_exact_price_deliver_and_eat_existing_food() -> void:
	for stand: PokeStand in _shops():
		_at(stand)
		var balance: int = _wallet.balances[1]
		assert_eq(_buy(stand), NetworkedEntity.Result.ACCEPTED)
		assert_eq(_wallet.balances[1], balance - stand.price_cents)
		assert_eq(_hand.net_item_id, "poke_bowl")
		assert_eq(_buy(stand), NetworkedEntity.Result.DENIED)
		assert_eq(_wallet.balances[1], balance - stand.price_cents)
		_hand.request_primary_action()
		assert_eq(_hand.net_item_id, "")


func test_menus_show_correct_brand_price_and_no_tip_and_cancel_without_spending() -> void:
	for stand: PokeStand in _shops():
		_at(stand)
		stand.use()
		var menu: CanvasLayer = stand.get_node("Menu")
		assert_true(menu.is_in_group(&"modal_ui"))
		assert_false(Controls.playing)
		assert_eq(menu._buttons.size(), 1)
		assert_eq(
			menu._buttons[0].text, "Buy bowl — %s" % PlayerMoney.format_money(stand.price_cents)
		)
		assert_true(menu._buttons[0].has_focus())
		var headings := menu.find_children("*", "Label", true, false)
		assert_eq(
			headings[0].text,
			"%s — %s" % [stand.menu_title, PlayerMoney.format_money(stand.price_cents)]
		)
		assert_string_contains(stand.interaction_text(), stand.menu_title.capitalize())
		menu._close()
		assert_true(Controls.playing)
	assert_eq(_wallet.balances[1], 10000)


func test_buy_button_uses_existing_order_action_and_disables_repeats() -> void:
	for stand: PokeStand in _shops():
		_at(stand)
		stand.use()
		var menu: CanvasLayer = stand.get_node("Menu")
		menu._buttons[0].pressed.emit()
		assert_eq(_hand.net_item_id, "poke_bowl")
		assert_true(menu._buttons[0].disabled)
		assert_true(menu._close_button.has_focus())
		assert_string_contains(
			menu._status.text, PlayerMoney.format_money(stand.price_cents) + " paid"
		)
		menu._close()
		_hand.request_primary_action()


func test_forged_payload_sender_wrong_side_and_distance_never_spend() -> void:
	for stand: PokeStand in _shops():
		_at(stand)
		for payload: Dictionary in [
			{}, {"tip": 15}, {"tip": 0.0}, {"tip": 0, "price": 1}, {"tip": 0, "peer": 1}
		]:
			assert_eq(stand.entity._evaluate(1, &"order", payload), NetworkedEntity.Result.DENIED)
		assert_eq(stand.entity._evaluate(77, &"order", {"tip": 0}), NetworkedEntity.Result.DENIED)
		_player.net_position = stand.to_global(Vector3(0, 1, -1))
		assert_eq(_buy(stand), NetworkedEntity.Result.DENIED)
		_player.net_position = stand.to_global(Vector3(0, 1, 8))
		assert_eq(_buy(stand), NetworkedEntity.Result.DENIED)
		stand.entity.set_multiplayer_authority(77)
		_at(stand)
		assert_ne(_buy(stand), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 10000)
	assert_eq(_hand.net_item_id, "")


func test_insufficient_funds_full_bag_and_occupied_hand_keep_inventory_rules() -> void:
	for stand: PokeStand in _shops():
		_at(stand)
		_wallet.balances[1] = stand.price_cents - 1
		_buy(stand)
		assert_eq(_wallet.balances[1], stand.price_cents - 1)
		assert_eq(_hand.net_item_id, "")
		stand._next_order.clear()
	_wallet.balances[1] = 10000
	_hand.inventory().collect("banana")
	var wok := _shops()[0]
	_at(wok)
	_buy(wok)
	assert_eq(_hand.net_item_id, "banana")
	assert_eq(_hand.inventory().backpack[0], "poke_bowl")
	for index: int in 7:
		_hand.inventory().collect("banana")
	var sushi := _shops()[1]
	_at(sushi)
	assert_eq(_buy(sushi), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 8800)


func test_service_transforms_match_visible_counters_and_survive_streaming() -> void:
	_room.load_room()
	var shops := _shops()
	for index: int in shops.size():
		var stand := shops[index]
		var path := (
			"Content/RivalRestaurants/CityWok"
			if index == 0
			else "Content/RivalRestaurants/CitySushi"
		)
		var decor := _room.get_node(path) as Node3D
		assert_eq(stand.global_position, decor.global_position)
		assert_eq(stand.global_basis, decor.global_basis)
		assert_string_contains(decor.get_node("MenuBoard").text, "$12" if index == 0 else "$15")
		_at(stand)
		assert_true(stand.can_use(_player))
		assert_true(_room.contains(_player.net_position))
	_room.unload_room()
	await wait_physics_frames(1)
	assert_eq(_shops(), shops)
	_room.load_room()
	assert_eq(_shops(), shops)
	assert_true(
		_room.get_node("Content").find_children("*", "NetworkedInteraction", true, false).is_empty()
	)


func test_pending_payment_blocks_duplicates_and_fallback_uses_customer_side() -> void:
	_wallet.remove_from_group(&"player_money")
	var slow := Fixtures.SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	var wok := _shops()[0]
	_at(wok)
	_buy(wok)
	assert_eq(_buy(wok), NetworkedEntity.Result.DENIED)
	for index: int in 9:
		_hand.inventory().collect("banana")
	slow.complete.emit()
	assert_eq(slow.total, 1200)
	assert_eq(_drops.items, ["poke_bowl"])
	assert_eq(_drops.landing, wok.to_global(Vector3(0, 0, 1.25)))
	assert_gt(_drops.landing.x, wok.global_position.x)


func test_sushi_pending_payment_session_reset_and_disconnect_follow_existing_service() -> void:
	_wallet.remove_from_group(&"player_money")
	var slow := Fixtures.SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	var sushi := _shops()[1]
	_at(sushi)
	_buy(sushi)
	sushi.entity.session_reset.emit(Network.Mode.OFFLINE)
	slow.complete.emit()
	assert_eq(_hand.net_item_id, "")
	assert_true(_drops.items.is_empty())
	_buy(sushi)
	_player.free()
	slow.complete.emit()
	assert_eq(slow.total, 1500)
	assert_eq(_drops.items, ["poke_bowl"])
	assert_lt(_drops.landing.x, sushi.global_position.x)


func _shops() -> Array[PokeStand]:
	return [
		_room.get_node("CityWokShop") as PokeStand, _room.get_node("CitySushiShop") as PokeStand
	]


func _at(stand: PokeStand) -> void:
	_player.net_position = stand.to_global(Vector3(0, 1, 1.7))
	_player.global_position = _player.net_position


func _buy(stand: PokeStand) -> NetworkedEntity.Result:
	return stand.entity._evaluate(1, &"order", {"tip": 0})
