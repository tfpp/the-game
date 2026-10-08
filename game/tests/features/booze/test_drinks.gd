extends GutTest
## Casino drinks: catalog items, sipping through the shared consumable path, and the
## server-authoritative drink spots that restock around the casino.

const BOOZE := preload("res://features/booze/feature.tscn")
const BAR := preload("res://features/bar_companion/feature.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _booze: Booze
var _bar: BarCompanion
var _hand: Hand
var _player: Player


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hand.set_process(false)
	_bar = BAR.instantiate() as BarCompanion
	add_child_autofree(_bar)
	_bar.set_process(false)
	_booze = BOOZE.instantiate() as Booze
	add_child_autofree(_booze)
	_booze.set_process(false)
	_booze.get_node("DrunkView").set_process(false)
	_booze.get_node("DrunkView").set_physics_process(false)
	_booze._bar()


func after_each() -> void:
	await get_tree().process_frame


func _spot(index: int) -> DrinkSpot:
	return _booze.get_node("Spots/Spot%d" % index) as DrinkSpot


func _sip() -> void:
	_hand.request_primary_action()
	_hand._process(ConsumableUse.DURATION + 0.1)


func test_every_drink_is_a_catalog_consumable_with_mouth_and_floor_contact() -> void:
	for id: String in BoozeRules.DRINKS:
		var definition := ItemCatalog.find(id)
		assert_not_null(definition, id)
		assert_eq(definition.category, ItemDefinition.Category.FOOD, id)
		assert_eq(definition.consumption_group, &"booze", id)
		assert_eq(definition.heal_amount, 0.0, id)
		var view := ItemCatalog.create_view(id)
		add_child_autofree(view)
		assert_true(view.has_node("Grip"), id)
		assert_true(view.has_node("Mouth"), id)
		var bottom := INF
		for child: Node in view.get_children():
			var mesh := child as MeshInstance3D
			if mesh != null:
				bottom = minf(bottom, (mesh.transform * mesh.get_aabb()).position.y)
		assert_almost_eq(bottom + definition.ground_clearance, 0.0, 0.01, id + " stands on base")
	assert_eq(ItemCatalog.uses_remaining("whiskey"), 3)
	assert_eq(ItemCatalog.uses_remaining("red_wine"), 3)
	assert_eq(ItemCatalog.uses_remaining("martini"), 1)
	assert_eq(ItemCatalog.find("whiskey:2").display_name, "Bottle of whiskey (2 sips left)")
	assert_eq(ItemCatalog.find("cigarette:2").display_name, "Cigarette (2 puffs left)")
	assert_eq(ItemCatalog.find("beer:1").display_name, "Bottled beer (1 sips left)")


func test_each_sip_of_liquor_is_one_drink_and_cocktails_are_single_glasses() -> void:
	_hand.net_item_id = "whiskey"
	for sip: int in 3:
		assert_eq(_bar.intoxication_for(1), sip)
		_sip()
	assert_eq(_bar.intoxication_for(1), 3, "a bottle is three drinks")
	assert_eq(_hand.net_item_id, "", "empty bottle is gone")
	_hand.net_item_id = "cosmopolitan"
	_sip()
	assert_eq(_bar.intoxication_for(1), 4)
	assert_eq(_hand.net_item_id, "")
	_hand.net_item_id = "beer"
	_sip()
	_sip()
	assert_eq(_bar.intoxication_for(1), 5, "bar beer still counts once per bottle")


func test_drinking_is_refused_while_blacked_out_without_spending_the_drink() -> void:
	_hand.net_item_id = "martini"
	_booze._set_phase(1, BoozeRules.Phase.OUT)
	assert_false(_booze.can_consume(1, "martini"))
	_hand.request_primary_action()
	assert_false(_hand.consumption.active())
	assert_eq(_hand.net_item_id, "martini")
	assert_eq(_bar.intoxication_for(1), 0)
	assert_false(_booze.can_consume(2, "beer"), "only casino liquor uses this handler")


func test_spots_stock_a_random_drink_that_one_player_can_take() -> void:
	assert_eq(_booze.get_node("Spots").get_child_count(), BoozeRules.SPOTS.size())
	var spot := _spot(0)
	spot.restock()
	spot._process(0.0)
	assert_true(BoozeRules.is_drink(spot.net_item))
	assert_true(spot.is_in_group(&"interactables"))
	assert_string_contains(spot.interaction_text(), ItemCatalog.find(spot.net_item).display_name)
	var drink := spot.net_item
	_player.net_position = spot.global_position + Vector3(1.5, 0.6, 0)
	assert_true(spot.can_use(_player))
	assert_eq(spot.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_hand.net_item_id, drink, "fills the empty hand first")
	assert_eq(spot.net_item, "")
	spot._process(0.0)
	assert_false(spot.is_in_group(&"interactables"))
	assert_eq(spot._mount.get_child_count(), 0)
	assert_eq(spot.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED, "only once")
	assert_eq(_hand.inventory().backpack.count(drink), 0)
	spot._process(BoozeRules.RESTOCK_MIN_S - 1.0)
	assert_eq(spot.net_item, "", "not yet")
	spot._process(BoozeRules.RESTOCK_MAX_S)
	assert_true(BoozeRules.is_drink(spot.net_item), "a new random drink appears later")


func test_spot_requests_check_range_payload_sender_and_inventory_space() -> void:
	var spot := _spot(1)
	spot.restock()
	_player.net_position = spot.global_position + Vector3(4.0, 0.6, 0)
	assert_eq(spot.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED, "too far")
	_player.net_position = spot.global_position + Vector3(1.0, 0.6, 0)
	assert_eq(
		spot.entity._evaluate(1, &"use", {"item": "whiskey"}),
		NetworkedEntity.Result.DENIED,
		"clients cannot pick the drink"
	)
	assert_true(BoozeRules.is_drink(spot.net_item))
	assert_eq(spot.entity._evaluate(2, &"use", {}), NetworkedEntity.Result.DENIED, "no player 2")
	_hand.net_item_id = "pistol"
	for slot: int in PlayerInventory.CAPACITY:
		_hand.inventory().backpack[slot] = "scrap"
	assert_false(spot.can_use(_player))
	assert_eq(spot.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED, "full bag")
	assert_false(spot.net_item.is_empty())
	_hand.inventory().backpack[3] = ""
	assert_eq(spot.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_true(BoozeRules.is_drink(_hand.inventory().backpack[3]), "goes to the backpack")


func test_spot_state_and_blackouts_are_declared_for_late_joiners() -> void:
	var entity := _spot(0).entity
	assert_true(entity.replicated_properties.has(NodePath(".:net_item")))
	assert_true(
		(_booze.entity as NetworkedEntity).replicated_properties.has(NodePath(".:blackouts"))
	)
	# A late client spawns with the replicated drink and draws it immediately.
	var late := preload("res://features/booze/drink_spot.tscn").instantiate() as DrinkSpot
	late.net_item = "martini"
	add_child_autofree(late)
	assert_true(late.is_in_group(&"interactables"))
	assert_eq(late._mount.get_child_count(), 1)
	assert_almost_eq(late._mount.position.y, ItemCatalog.find("martini").ground_clearance, 0.001)
	_spot(2)._reset(Network.Mode.OFFLINE)
	assert_true(BoozeRules.is_drink(_spot(2).net_item), "new sessions start stocked")
