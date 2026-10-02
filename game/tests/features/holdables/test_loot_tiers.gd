extends GutTest

const IDS := ["scrap", "stolen_wallet", "electronics", "watch", "jewelry"]
const PRICES := [100, 300, 700, 1000, 1500]
const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const COLORS := ["c5c7c9", "88c999", "8ebcf0", "c7a0e8", "e5bf72"]
const PICKUP := preload("res://features/holdables/item_pickup.tscn")
const THROWN := preload("res://features/holdables/thrown_item.tscn")


func test_exactly_five_valuable_tiers_have_stable_ids_prices_and_unique_colors() -> void:
	var tiered := 0
	for definition: ItemDefinition in ItemCatalog.DEFINITIONS:
		if definition.rarity != ItemDefinition.Rarity.NONE:
			tiered += 1
	assert_eq(tiered, 5)
	for index: int in IDS.size():
		var definition := ItemCatalog.find(IDS[index])
		assert_eq(int(definition.rarity), index + 1)
		assert_eq(definition.sale_value_cents, PRICES[index])
		assert_eq(definition.rarity_name(), NAMES[index])
		assert_eq(definition.rarity_color(), Color(COLORS[index]))
		assert_eq(definition.category, ItemDefinition.Category.PROP)
		assert_eq(definition.loot_details(), "%s · $%d.00" % [NAMES[index], PRICES[index] / 100])


func test_existing_garage_and_alley_roll_weights_decrease_with_valuable_tier() -> void:
	for table: LootTable in [
		preload("res://features/parking_garage/car_loot.tres"),
		preload("res://features/slum_alley/alley_loot.tres"),
	]:
		var previous := INF
		for id: String in IDS:
			var index := table.item_ids.find(id)
			assert_gte(index, 0)
			assert_gt(table.weights[index], 0.0)
			assert_lt(table.weights[index], previous)
			previous = table.weights[index]


func test_world_and_death_drop_pickups_share_plain_text_prices_and_color() -> void:
	for id: String in IDS:
		var pickup := PICKUP.instantiate() as ItemPickup
		pickup.item_id = id
		add_child_autofree(pickup)
		var dropped := THROWN.instantiate() as ThrownItem
		dropped.item_id = id
		add_child_autofree(dropped)
		var definition := ItemCatalog.find(id)
		var expected := "Pick up " + definition.display_name + "\n" + definition.loot_details()
		assert_eq(pickup.interaction_text(), expected)
		assert_eq(dropped.interaction_text(), expected)
		assert_eq(pickup.interaction_color(), definition.rarity_color())
		assert_eq(dropped.interaction_color(), definition.rarity_color())


func test_cash_and_ordinary_items_keep_existing_catalog_and_prompt_behavior() -> void:
	var cash := ItemCatalog.find("cash_bundle")
	assert_eq(cash.rarity, ItemDefinition.Rarity.NONE, "Cash is not a sixth valuable tier")
	assert_eq(cash.sale_value_cents, 500, "Saved cash still redeems at the pawn counter")
	assert_eq(cash.loot_details(), "Cash · $5.00")
	for id: String in ["pistol", "banana", "beer:1", "shirt:2", "upper_study_key"]:
		var definition := ItemCatalog.find(id)
		assert_eq(definition.rarity, ItemDefinition.Rarity.NONE)
		assert_eq(definition.loot_details(), "")
		assert_eq(ItemCatalog.pickup_text(id), "Pick up " + definition.display_name)
		assert_eq(ItemCatalog.item_color(id), Color.WHITE)
	assert_eq(ItemCatalog.pickup_text("unknown"), "Pick up unknown")
	assert_eq(ItemCatalog.item_color(""), Color.WHITE)


func test_price_formatting_preserves_integer_cents() -> void:
	var definition := ItemDefinition.new()
	definition.rarity = ItemDefinition.Rarity.RARE
	definition.sale_value_cents = 725
	assert_eq(definition.loot_details(), "Rare · $7.25")
