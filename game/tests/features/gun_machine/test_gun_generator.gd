extends GutTest


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_generate_is_deterministic_for_a_given_seed() -> void:
	var a := GunGenerator.generate(_rng(42))
	var b := GunGenerator.generate(_rng(42))
	assert_eq(a, b)


func test_different_seeds_can_roll_different_guns() -> void:
	var results: Dictionary = {}
	for seed_value: int in 40:
		var gun := GunGenerator.generate(_rng(seed_value))
		results[JSON.stringify(gun)] = true
	assert_gt(results.size(), 1, "40 seeds should not all roll the identical gun")


func test_every_stat_is_within_its_ammo_types_range() -> void:
	for seed_value: int in 200:
		var gun := GunGenerator.generate(_rng(seed_value))
		var profile := GunGenerator.profile(gun["ammo_type"])
		assert_between(int(gun["barrel_count"]), 1, 4)
		assert_between(float(gun["fire_rate"]), profile["fire_rate"][0], profile["fire_rate"][1])
		assert_between(
			int(gun["magazine_size"]), profile["magazine_size"][0], profile["magazine_size"][1]
		)
		assert_between(float(gun["damage"]), profile["damage"][0], profile["damage"][1])
		assert_between(
			float(gun["projectile_speed"]),
			profile["projectile_speed"][0],
			profile["projectile_speed"][1]
		)
		assert_true(int(gun["total_ammo"]) >= int(gun["magazine_size"]))
		assert_true(not str(gun["display_name"]).is_empty())
		assert_true(
			int(gun["barrel_count"]) <= int(gun["magazine_size"]),
			"a gun that can never be fully loaded could never fire"
		)


func test_display_name_mentions_barrel_count_and_ammo_type() -> void:
	assert_eq(GunGenerator.display_name(GunGenerator.AmmoType.PLASMA, 1), "Plasma Gun")
	assert_eq(
		GunGenerator.display_name(GunGenerator.AmmoType.ROCKET, 2), "Double-Barrel Rocket Gun"
	)


func test_display_name_mentions_automatic_fire_mode_when_rolled() -> void:
	assert_eq(GunGenerator.display_name(GunGenerator.AmmoType.RIFLE, 1, true), "Auto Rifle Gun")
	assert_eq(GunGenerator.display_name(GunGenerator.AmmoType.RIFLE, 1, false), "Rifle Gun")


func test_grenade_profile_bounces_and_rocket_profile_explodes() -> void:
	var grenade := GunGenerator.profile(GunGenerator.AmmoType.GRENADE)
	assert_gt(int(grenade["bounces"]), 0)
	assert_gt(float(grenade["gravity_scale"]), 0.0)
	var rocket := GunGenerator.profile(GunGenerator.AmmoType.ROCKET)
	assert_gt(float(rocket["explosion_radius"]), 0.0)
	assert_gt(float(rocket["splash_force"]), 0.0)
	var rifle := GunGenerator.profile(GunGenerator.AmmoType.RIFLE)
	assert_eq(float(rifle["explosion_radius"]), 0.0)
	assert_eq(float(rifle["splash_force"]), 0.0)
	assert_eq(int(rifle["bounces"]), 0)


func test_generated_guns_roll_a_fire_mode_and_both_modes_occur() -> void:
	var modes := {}
	for seed_value: int in 60:
		var gun := GunGenerator.generate(_rng(seed_value))
		assert_true(gun["is_automatic"] is bool)
		modes[gun["is_automatic"]] = true
	assert_eq(modes.size(), 2, "60 seeds should roll both automatic and semi-automatic guns")
