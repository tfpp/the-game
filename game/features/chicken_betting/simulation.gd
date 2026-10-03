class_name ChickenFightSimulation
extends RefCounted
## Pure seeded rules. No nodes, spawning, wallet or UI dependencies.

const FIRST: Array[String] = ["Sir", "Lady", "Rusty", "Velvet", "Lucky", "Captain"]
const LAST: Array[String] = ["Cluckles", "Drumstick", "Pecks", "Nugget", "Feathers", "Biscuit"]


static func generate(rng: RandomNumberGenerator, config: ChickenFightConfig) -> Dictionary:
	var bird := {"name": FIRST[rng.randi_range(0, 5)] + " " + LAST[rng.randi_range(0, 5)]}
	for stat: String in ["strength", "speed", "stamina", "luck"]:
		bird[stat] = rng.randi_range(config.stat_min, config.stat_max)
	bird["health"] = config.health_base + int(bird["stamina"]) * config.health_per_stamina
	return bird


static func power(bird: Dictionary, config: ChickenFightConfig) -> float:
	return (
		float(bird["strength"]) * config.strength_weight
		+ float(bird["speed"]) * config.speed_weight
		+ float(bird["stamina"]) * config.stamina_weight
		+ float(bird["luck"]) * config.luck_weight
	)


## Exactly one attack per round, so simultaneous double knockouts cannot occur.
static func round_result(
	birds: Array, health: Array, rng: RandomNumberGenerator, config: ChickenFightConfig
) -> Dictionary:
	var chance := power(birds[0], config) / (power(birds[0], config) + power(birds[1], config))
	var attacker := 0 if rng.randf() < chance else 1
	var defender := 1 - attacker
	var damage := maxi(
		1,
		(
			rng.randi_range(config.damage_min, config.damage_max)
			+ roundi(float(birds[attacker]["strength"]) * config.strength_damage)
		)
	)
	var remaining := health.duplicate()
	remaining[defender] = maxi(0, int(remaining[defender]) - damage)
	return {
		"attacker": attacker,
		"damage": damage,
		"health": remaining,
		"winner": attacker if int(remaining[defender]) == 0 else -1
	}


## Quote the same round simulation using an independent deterministic sample stream.
## Smoothing prevents infinite odds; odds include the returned stake.
static func odds(birds: Array, config: ChickenFightConfig) -> Array:
	var rng := RandomNumberGenerator.new()
	var stats: Array = []
	for bird: Dictionary in birds:
		for field: String in ["strength", "speed", "stamina", "luck", "health"]:
			stats.append(bird[field])
	rng.seed = hash(stats)
	var wins := 0
	for sample: int in config.odds_samples:
		var health: Array = [birds[0]["health"], birds[1]["health"]]
		while int(health[0]) > 0 and int(health[1]) > 0:
			var result := round_result(birds, health, rng, config)
			health = result["health"]
			if int(result["winner"]) == 0:
				wins += 1
	var probability := clampf(
		float(wins + 1) / float(config.odds_samples + 2),
		config.probability_floor,
		1.0 - config.probability_floor
	)
	return [
		floorf((1.0 - config.house_edge) / probability * 100.0) / 100.0,
		floorf((1.0 - config.house_edge) / (1.0 - probability) * 100.0) / 100.0
	]


static func payout(stake: int, odds_value: float) -> int:
	return floori(stake * odds_value)
