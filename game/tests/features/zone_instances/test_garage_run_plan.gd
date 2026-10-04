extends GutTest


func test_server_seed_selects_distinct_authored_points_and_scales_encounters() -> void:
	var plan := GarageRunPlan.enemies(42)
	assert_eq(plan, GarageRunPlan.enemies(42), "Shared seed reproduces exact spawn data")
	assert_ne(plan, GarageRunPlan.enemies(43), "A different run changes encounters")
	var counts: Array[int] = [0, 0, 0, 0, 0]
	var strengths: Array[int] = [0, 0, 0, 0, 0]
	var seen: Dictionary = {}
	for entry: Dictionary in plan:
		var depth := int(entry["depth"])
		var point := int(entry["point"])
		var key := "%d:%d" % [depth, point]
		assert_false(seen.has(key), "Only one enemy may occupy each marker")
		seen[key] = true
		assert_between(point, 0, 5)
		counts[depth] += 1
		strengths[depth] += int(GarageEnemyTiers.profile(int(entry["tier"]))["hits"])
		if depth == 0:
			assert_eq(int(entry["tier"]), GarageEnemyTiers.Tier.LURKER)
			assert_gte(point, 2, "Top arrival lane is clear")
	assert_eq(counts, [2, 3, 4, 4, 6] as Array[int])
	for depth: int in range(1, 5):
		assert_gt(strengths[depth], strengths[depth - 1])


func test_expected_loot_value_increases_with_depth_and_tables_are_independent() -> void:
	var previous := 0.0
	for depth: int in 5:
		var table := GarageRunPlan.loot_table(depth)
		var weight := 0.0
		var weighted_value := 0.0
		for index: int in table.item_ids.size():
			var item := ItemCatalog.find(table.item_ids[index])
			assert_not_null(item)
			weight += table.weights[index]
			weighted_value += table.weights[index] * item.sale_value_cents
		var average_items := (table.min_items + table.max_items) * .5
		var expected := (1 - table.empty_chance) * average_items * weighted_value / weight
		assert_gt(expected, previous, "Each deeper floor offers greater expected payout")
		previous = expected
		var other := GarageRunPlan.loot_table(depth)
		table.weights[0] = 999
		assert_ne(table.weights[0], other.weights[0], "Instances do not share mutable roll data")
