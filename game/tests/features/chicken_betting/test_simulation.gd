extends GutTest

var config := ChickenFightConfig.new()


func test_generation_obeys_tunable_ranges_and_health() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 477
	config.stat_min = 4
	config.stat_max = 6
	for index: int in 100:
		var bird := ChickenFightSimulation.generate(rng, config)
		assert_false(str(bird["name"]).is_empty())
		for stat: String in ["strength", "speed", "stamina", "luck"]:
			assert_between(int(bird[stat]), 4, 6)
		assert_eq(
			bird["health"], config.health_base + int(bird["stamina"]) * config.health_per_stamina
		)


func test_rounds_only_damage_the_chosen_defender_and_end_in_one_knockout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var birds: Array = [
		ChickenFightSimulation.generate(rng, config), ChickenFightSimulation.generate(rng, config)
	]
	var health: Array = [birds[0]["health"], birds[1]["health"]]
	var rounds := 0
	while int(health[0]) > 0 and int(health[1]) > 0:
		var result := ChickenFightSimulation.round_result(birds, health, rng, config)
		var attacker := int(result["attacker"])
		assert_eq(result["health"][attacker], health[attacker])
		assert_eq(
			result["health"][1 - attacker],
			maxi(0, int(health[1 - attacker]) - int(result["damage"]))
		)
		health = result["health"]
		rounds += 1
		assert_lt(rounds, 100)
		if result["winner"] != -1:
			assert_eq(int(result["winner"]), attacker)
			assert_eq(int(health[1 - attacker]), 0)
	assert_eq(int(health[0]) == 0, int(health[1]) > 0)


func _bird(stat: int) -> Dictionary:
	return {
		"name": "Bird",
		"strength": stat,
		"speed": stat,
		"stamina": stat,
		"luck": stat,
		"health": config.health_base + stat * config.health_per_stamina
	}


func test_odds_are_repeatable_favorite_shorter_and_house_edge_included() -> void:
	config.odds_samples = 512
	var birds: Array = [_bird(7), _bird(5)]
	var odds := ChickenFightSimulation.odds(birds, config)
	assert_eq(odds, ChickenFightSimulation.odds(birds, config))
	var renamed := birds.duplicate(true)
	renamed[0]["name"] = "Different Name"
	assert_eq(odds, ChickenFightSimulation.odds(renamed, config), "names never affect odds")
	assert_lt(float(odds[0]), float(odds[1]))
	assert_gt(1.0 / float(odds[0]) + 1.0 / float(odds[1]), 1.0)
	assert_eq(ChickenFightSimulation.payout(123, 1.91), 234)


func test_favorite_usually_wins_but_upsets_remain_possible() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 477
	var birds: Array = [_bird(7), _bird(5)]
	var wins := 0
	for match_index: int in 400:
		var health: Array = [birds[0]["health"], birds[1]["health"]]
		while int(health[0]) > 0 and int(health[1]) > 0:
			var result := ChickenFightSimulation.round_result(birds, health, rng, config)
			health = result["health"]
			if int(result["winner"]) == 0:
				wins += 1
	assert_gt(wins, 200)
	assert_lt(wins, 400)
