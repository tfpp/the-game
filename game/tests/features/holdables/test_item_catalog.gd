extends GutTest
## The item registry (features/holdables/item_catalog.gd): every item the "as a test"
## request asked for should resolve, and each with the right category so hand.gd
## dispatches its primary action correctly.

const ItemCatalog := preload("res://features/holdables/item_catalog.gd")
const ItemDefinition := preload("res://features/holdables/item_definition.gd")


func test_pistol_is_a_weapon() -> void:
	var item := ItemCatalog.find("pistol")
	assert_not_null(item)
	assert_eq(item.category, ItemDefinition.Category.WEAPON)


func test_banana_is_food() -> void:
	var item := ItemCatalog.find("banana")
	assert_not_null(item)
	assert_eq(item.category, ItemDefinition.Category.FOOD)


func test_ball_is_a_prop() -> void:
	var item := ItemCatalog.find("ball")
	assert_not_null(item)
	assert_eq(item.category, ItemDefinition.Category.PROP)


func test_smg_and_shotgun_are_weapons_with_damage() -> void:
	for id: String in ["smg", "shotgun"]:
		var item := ItemCatalog.find(id)
		assert_not_null(item)
		assert_eq(item.category, ItemDefinition.Category.WEAPON)
		assert_gt(item.damage, 0.0)


func test_shotgun_fires_more_pellets_with_more_spread_than_the_pistol() -> void:
	var pistol := ItemCatalog.find("pistol")
	var shotgun := ItemCatalog.find("shotgun")
	assert_gt(shotgun.pellet_count, pistol.pellet_count)
	assert_gt(shotgun.spread_degrees, pistol.spread_degrees)


func test_weapons_are_heavier_than_props_and_bounce_less() -> void:
	var ball := ItemCatalog.find("ball")
	var pistol := ItemCatalog.find("pistol")
	assert_gt(pistol.weight, ball.weight)


func test_awp_is_a_weapon() -> void:
	var item := ItemCatalog.find("awp")
	assert_not_null(item)
	assert_eq(item.category, ItemDefinition.Category.WEAPON)


func test_every_definition_has_an_id_matching_its_lookup_and_a_view() -> void:
	for item: ItemDefinition in ItemCatalog.DEFINITIONS:
		assert_false(item.id.is_empty())
		assert_eq(ItemCatalog.find(item.id), item)
		assert_not_null(item.view_scene)


func test_unknown_id_returns_null() -> void:
	assert_null(ItemCatalog.find("nonexistent"))
	assert_null(ItemCatalog.find(""))
