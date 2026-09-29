extends GutTest

const SHOP := preload("res://features/kebab_shop/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var _shop: KebabShop
var _player: Player
var _hand: Hand


func before_each() -> void:
	_shop = SHOP.instantiate() as KebabShop
	add_child_autofree(_shop)
	_shop.set_physics_process(false)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = _shop.position + Vector3(1.35, 1, 1.5)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)


func after_each() -> void:
	await get_tree().process_frame


func test_order_transfers_one_edible_item_and_can_be_eaten() -> void:
	_shop.use()
	assert_eq(_hand.net_item_id, "kebab")
	assert_eq(_shop.net_serving, KebabShop.SERVE_SECONDS)
	_shop.use()
	assert_eq(_hand.inventory().backpack.count("kebab"), 0)
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")
	_shop._physics_process(KebabShop.SERVE_SECONDS)
	_shop.use()
	assert_eq(_hand.net_item_id, "kebab")


func test_rejects_unknown_peer_payload_distance_and_kitchen_side() -> void:
	assert_eq(_shop.entity._evaluate(7, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_shop.entity._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	_player.net_position += Vector3(10, 0, 0)
	_shop.use()
	assert_eq(_hand.net_item_id, "")
	_player.net_position = _shop.position + Vector3(1.35, 1, -0.5)
	_shop.use()
	assert_eq(_hand.net_item_id, "")
	assert_eq(_shop.net_serving, 0.0)


func test_full_inventory_does_not_start_service_and_existing_items_survive() -> void:
	for index: int in 9:
		assert_true(_hand.inventory().collect("banana"))
	_shop.use()
	assert_eq(_shop.net_serving, 0.0)
	assert_eq(_hand.net_item_id, "banana")
	assert_eq(_hand.inventory().backpack.count("banana"), 8)
	assert_string_contains(_shop.interaction_text(), "make room")
	_hand.request_primary_action()
	_shop.use()
	assert_eq(_hand.net_item_id, "kebab")
	assert_eq(_hand.inventory().backpack.count("banana"), 8)


func test_busy_shop_rejects_second_player_and_recovers_without_requester() -> void:
	var second := PLAYER.instantiate() as Player
	second.name = "2"
	second.set_multiplayer_authority(2)
	add_child_autofree(second)
	second.set_physics_process(false)
	second.net_position = _player.net_position
	_shop.use()
	assert_eq(_shop.entity._evaluate(2, &"use", {}), NetworkedEntity.Result.DENIED)
	_player.queue_free()
	await get_tree().process_frame
	_shop._physics_process(3.1)
	assert_eq(_shop.net_serving, 0.0)
	assert_true(_shop.can_use(second))


func test_full_hand_uses_backpack_and_missing_hand_does_not_start_service() -> void:
	_hand.inventory().collect("banana")
	_shop.use()
	assert_eq(_hand.net_item_id, "banana")
	assert_eq(_hand.inventory().backpack[0], "kebab")
	_shop._physics_process(3.1)
	_hand.queue_free()
	await get_tree().process_frame
	_shop.use()
	assert_eq(_shop.net_serving, 0.0)


func test_late_join_snapshot_drives_same_pose_and_session_resets() -> void:
	var sync := _shop.entity.get_node("Sync") as MultiplayerSynchronizer
	for field: NodePath in [NodePath(".:net_phase"), NodePath(".:net_serving")]:
		assert_true(sync.replication_config.has_property(field))
		assert_true(sync.replication_config.property_get_spawn(field))
	_shop.use()
	_shop._physics_process(0.7)
	var late := SHOP.instantiate() as KebabShop
	add_child_autofree(late)
	late.set_physics_process(false)
	late.net_phase = _shop.net_phase
	late.net_serving = _shop.net_serving
	_shop.view.present(_shop.net_phase, _shop.net_serving)
	late.view.present(late.net_phase, late.net_serving)
	assert_eq(late.view.get_node("Spit").rotation, _shop.view.get_node("Spit").rotation)
	assert_string_contains(late.view.get_node("Reply").text, "Enjoy")
	_shop.entity.session_reset.emit(Network.Mode.OFFLINE)
	assert_eq(_shop.net_serving, 0.0)
	assert_eq(_shop.net_phase, 0.0)


func test_animation_moves_spit_chef_and_cashier_and_food_has_layers() -> void:
	_shop.view.present(0.0, 0.0)
	var arm: Vector3 = _shop.view.get_node("Chef/RightArm").rotation
	_shop.view.present(0.3, 2.0)
	assert_ne(_shop.view.get_node("Chef/RightArm").rotation, arm)
	assert_gt(_shop.view.get_node("Spit").rotation.y, 0.0)
	assert_lt(_shop.view.get_node("Cashier/RightArm").rotation.x, -0.5)
	var food := ItemCatalog.create_view("kebab")
	add_child_autofree(food)
	for part: String in [
		"Grip",
		"Flatbread",
		"PaperSleeve",
		"ShavedMeat0",
		"Lettuce0",
		"Tomato0",
		"Onion0",
		"YogurtSauce0"
	]:
		assert_true(food.has_node(part), part)
	assert_eq(ItemCatalog.find("kebab").category, ItemDefinition.Category.FOOD)
