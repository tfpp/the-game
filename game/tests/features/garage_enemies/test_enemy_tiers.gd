extends GutTest


func test_deeper_tiers_are_faster_and_hit_harder() -> void:
	var lurker := GarageEnemyTiers.profile(GarageEnemyTiers.Tier.LURKER)
	var gunman := GarageEnemyTiers.profile(GarageEnemyTiers.Tier.GUNMAN)
	var stalker := GarageEnemyTiers.profile(GarageEnemyTiers.Tier.STALKER)
	assert_lt(float(lurker["speed"]), float(stalker["speed"]))
	assert_lt(float(lurker["damage"]), float(gunman["damage"]))
	assert_lt(float(gunman["damage"]), float(stalker["damage"]))
	assert_true(gunman["ranged"])
	assert_false(stalker["ranged"])
	# Toughness grows modestly; difficulty isn't just more health.
	assert_lte(int(stalker["hits"]), 3)


func test_same_floor_uses_player_capsule_center() -> void:
	var feet := Vector3(0, 3.3, 0)
	assert_true(GarageEnemyTiers.same_floor(feet, Vector3(4, 3.3 + 0.9, 0)))
	assert_false(GarageEnemyTiers.same_floor(feet, Vector3(0, 0.9, 0)))
	assert_false(GarageEnemyTiers.same_floor(feet, Vector3(0, 6.6 + 0.9, 0)))


func test_nearest_ignores_other_floors_and_far_players() -> void:
	var feet := Vector3.ZERO
	var points: Array[Vector3] = [Vector3(1, 4.2, 0), Vector3(20, 0.9, 0), Vector3(5, 0.9, 0)]
	assert_eq(GarageEnemyTiers.nearest(feet, points, 10.0), 2)
	assert_eq(GarageEnemyTiers.nearest(feet, points, 4.0), -1)


func test_facing_yaw_turns_minus_z_model_towards_direction() -> void:
	var dir := Vector3(1, 0, 0)
	var forward := Vector3.FORWARD.rotated(Vector3.UP, GarageEnemyTiers.facing_yaw(dir))
	assert_almost_eq(forward.x, 1.0, 0.001)
	assert_almost_eq(forward.z, 0.0, 0.001)


func test_moving_targets_are_harder_to_shoot() -> void:
	assert_gt(GarageEnemyTiers.hit_chance(0.0), GarageEnemyTiers.hit_chance(6.0))
	assert_eq(GarageEnemyTiers.hit_chance(50.0), GarageEnemyTiers.MIN_HIT_CHANCE)


func test_gunmen_hold_distance_while_melee_closes_in() -> void:
	assert_false(GarageEnemyTiers.wants_to_advance(GarageEnemyTiers.Tier.GUNMAN, 6.0))
	assert_true(GarageEnemyTiers.wants_to_advance(GarageEnemyTiers.Tier.GUNMAN, 12.0))
	assert_true(GarageEnemyTiers.wants_to_advance(GarageEnemyTiers.Tier.LURKER, 3.0))
	assert_false(GarageEnemyTiers.wants_to_advance(GarageEnemyTiers.Tier.LURKER, 1.0))
