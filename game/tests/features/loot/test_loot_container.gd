extends GutTest
## Loot tables and the server-authoritative searchable container
## (features/loot), plus its first use on the parking garage's wrecked cars.

const CONTAINER := preload("res://features/loot/loot_container.tscn")
const CAR_LOOT := preload("res://features/parking_garage/car_loot.tres")
const GARAGE := preload("res://features/parking_garage/feature.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _hand: Hand
var _player: Player


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)


func after_each() -> void:
	await get_tree().process_frame


func _table(empty: float, lo: int, hi: int) -> LootTable:
	var table := LootTable.new()
	table.empty_chance = empty
	table.min_items = lo
	table.max_items = hi
	table.item_ids = PackedStringArray(["watch", "scrap"])
	table.weights = PackedFloat32Array([1, 0])
	return table


func _container(table: LootTable) -> LootContainer:
	var container := CONTAINER.instantiate() as LootContainer
	container.loot_table = table
	add_child_autofree(container)
	container.rng.seed = 7
	return container


func _inventory_count(id: String) -> int:
	var inv := _hand.inventory()
	return inv.backpack.count(id) + (1 if _hand.net_item_id == id else 0)


func test_roll_respects_counts_weights_and_empty_chance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for _i in 50:
		var items := _table(0.0, 2, 4).roll(rng)
		assert_between(items.size(), 2, 4)
		assert_false(items.has("scrap"), "Zero-weight items never drop")
	assert_eq(_table(1.0, 1, 3).roll(rng).size(), 0)


func test_car_loot_items_are_real_inventory_items() -> void:
	assert_eq(CAR_LOOT.item_ids.size(), CAR_LOOT.weights.size())
	for id: String in ["stolen_wallet", "watch", "jewelry", "electronics", "scrap", "cash_bundle"]:
		assert_true(CAR_LOOT.item_ids.has(id), id)
		assert_not_null(ItemCatalog.find(id), id)
		var view := ItemCatalog.create_view(id)
		assert_not_null(view, id)
		view.free()


func test_search_grants_loot_once_and_stays_searched() -> void:
	var container := _container(_table(0.0, 3, 3))
	container.request_search()
	assert_true(container.net_searched)
	assert_eq(_inventory_count("watch"), 3)
	assert_eq(container.net_contents.size(), 0)
	container.request_search()
	assert_eq(_inventory_count("watch"), 3, "A searched container cannot be claimed twice")


func test_leftovers_stay_until_there_is_room() -> void:
	var container := _container(_table(0.0, 10, 10))
	container.request_search()
	assert_eq(_inventory_count("watch"), 9)
	assert_eq(container.net_contents.size(), 1)
	assert_string_contains(container.interaction_text(), "Take Watch")
	var bag := _hand.inventory().backpack.duplicate()
	bag[0] = ""
	_hand.inventory().backpack = bag
	container.request_search()
	assert_eq(container.net_contents.size(), 0)


func test_distant_player_cannot_search() -> void:
	var container := _container(_table(0.0, 1, 1))
	container.position = Vector3(20, 0, 0)
	assert_false(container.can_use(_player))
	container.request_search()
	assert_false(container.net_searched)
	assert_eq(_inventory_count("watch"), 0)


func test_reset_all_rerolls_on_next_search() -> void:
	var container := _container(_table(1.0, 1, 1))
	container.request_search()
	assert_true(container.net_searched)
	assert_eq(container.interaction_text(), "Searched container (empty)")
	container.loot_table = _table(0.0, 1, 1)
	LootContainer.reset_all(get_tree())
	assert_false(container.net_searched)
	container.request_search()
	assert_eq(_inventory_count("watch"), 1)


func test_garage_places_searchable_wrecked_cars() -> void:
	var garage := GARAGE.instantiate() as Node3D
	add_child_autofree(garage)
	var found := 0
	for node: Node in get_tree().get_nodes_in_group(LootContainer.GROUP):
		var container := node as LootContainer
		if garage.is_ancestor_of(container):
			found += 1
			assert_is(container.get_parent(), CarWreck)
			assert_eq(container.loot_table, CAR_LOOT)
	assert_gt(found, 5)
