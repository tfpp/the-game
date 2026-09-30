extends GutTest
## Eating FOOD restores health through features/combat's server-only `heal()`.

const HandScene := preload("res://features/holdables/hand.tscn")
const ItemCatalog := preload("res://features/holdables/item_catalog.gd")

var _combat: Combat
var _hand: Hand


func before_each() -> void:
	_combat = Combat.new()
	add_child_autofree(_combat)
	_hand = HandScene.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)


func test_kebab_and_poke_bowl_restore_full_health() -> void:
	for item_id: String in ["kebab", "poke_bowl"]:
		_combat.apply_damage(1, 95.0, 2)
		_hand.net_item_id = item_id
		_hand.request_primary_action()
		assert_eq(_hand.net_item_id, "")
		assert_eq(_combat.health_for(1), Combat.MAX_HEALTH, item_id)


func test_banana_heals_partially() -> void:
	_combat.apply_damage(1, 60.0, 2)
	_hand.net_item_id = "banana"
	_hand.request_primary_action()
	assert_almost_eq(_combat.health_for(1), 40.0 + ItemCatalog.find("banana").heal_amount, 0.01)


func test_every_food_heals() -> void:
	for item_id: String in ["kebab", "poke_bowl", "banana"]:
		assert_gt(ItemCatalog.find(item_id).heal_amount, 0.0, item_id)


func test_heal_never_exceeds_max_health() -> void:
	_combat.apply_damage(1, 10.0, 2)
	_combat.heal(1, 500.0)
	assert_eq(_combat.health_for(1), Combat.MAX_HEALTH)


func test_heal_ignores_non_positive_amounts() -> void:
	_combat.apply_damage(1, 10.0, 2)
	_combat.heal(1, -20.0)
	assert_eq(_combat.health_for(1), 90.0)


func test_eating_another_peers_food_does_not_heal() -> void:
	_combat.apply_damage(1, 50.0, 2)
	_hand.peer_id = 2
	_hand.net_item_id = "kebab"
	_hand.request_primary_action()
	assert_eq(_combat.health_for(1), 50.0)
	assert_eq(_hand.net_item_id, "kebab")
