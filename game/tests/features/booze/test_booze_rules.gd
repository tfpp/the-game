extends GutTest
## Pure drink, drunkenness, lying-pose and wake-spot rules.


func test_effects_grow_with_each_drink_and_blackout_needs_eight() -> void:
	assert_eq(BoozeRules.intensity(0), 0.0)
	var previous := 0.0
	for drinks: int in range(1, 8):
		var level := BoozeRules.intensity(drinks)
		assert_gt(level, previous, "drink %d is stronger than the last" % drinks)
		previous = level
	assert_eq(BoozeRules.intensity(7), 1.0)
	assert_eq(BoozeRules.intensity(10), 1.0)
	assert_false(BoozeRules.blacks_out(7.0))
	assert_false(BoozeRules.blacks_out(7.9))
	assert_true(BoozeRules.blacks_out(8.0))
	assert_lte(BoozeRules.BLACKOUT_DRINKS, CharmMath.MAX_INTOXICATION, "reachable intoxication")
	assert_eq(BoozeRules.mood(0), "sober")
	assert_eq(BoozeRules.mood(1), "tipsy")
	assert_eq(BoozeRules.mood(4), "drunk")
	assert_eq(BoozeRules.mood(7), "hammered")


func test_sway_and_stumbles_scale_with_level_and_stay_bounded() -> void:
	assert_eq(BoozeRules.camera_roll(3.0, 0.0), 0.0)
	assert_eq(BoozeRules.aim_sway(3.0, 0.0), Vector2.ZERO)
	assert_eq(BoozeRules.veer_rate(3.0, 0.1), 0.0, "a single drink walks straight")
	assert_eq(BoozeRules.stumble_speed(0.3), 0.0, "tipsy players do not stumble")
	assert_gt(BoozeRules.stumble_speed(1.0), BoozeRules.stumble_speed(0.5))
	assert_lt(BoozeRules.stumble_interval(1.0, 0.5), BoozeRules.stumble_interval(0.5, 0.5))
	var largest_roll := 0.0
	var largest_aim := 0.0
	var largest_veer := 0.0
	for step: int in 2000:
		var time := step * 0.05
		largest_roll = maxf(largest_roll, absf(BoozeRules.camera_roll(time, 1.0)))
		largest_aim = maxf(largest_aim, BoozeRules.aim_sway(time, 1.0).length())
		largest_veer = maxf(largest_veer, absf(BoozeRules.veer_rate(time, 1.0)))
		assert_lte(absf(BoozeRules.camera_roll(time, 0.3)), absf(BoozeRules.camera_roll(time, 1.0)))
	assert_between(rad_to_deg(largest_roll), 6.0, 10.01, "noticeable but not nauseating roll")
	assert_between(rad_to_deg(largest_aim), 2.0, 6.0)
	assert_between(largest_veer, 0.8, 1.41)
	assert_gt(BoozeRules.screen_strength(1.0), BoozeRules.screen_strength(0.3))
	assert_eq(BoozeRules.screen_strength(0.0), 0.0)


func test_random_drinks_cover_every_kind_and_restock_later() -> void:
	var seen := {}
	for step: int in 100:
		seen[BoozeRules.pick_drink(step / 100.0)] = true
	assert_eq(seen.size(), BoozeRules.DRINKS.size())
	assert_eq(BoozeRules.pick_drink(1.0), BoozeRules.DRINKS[BoozeRules.DRINKS.size() - 1])
	assert_eq(BoozeRules.restock_delay(0.0), BoozeRules.RESTOCK_MIN_S)
	assert_eq(BoozeRules.restock_delay(1.0), BoozeRules.RESTOCK_MAX_S)
	for id: String in BoozeRules.DRINKS:
		assert_true(BoozeRules.is_drink(id))
	assert_true(BoozeRules.is_drink("whiskey:1"))
	assert_false(BoozeRules.is_drink("beer"))
	assert_false(BoozeRules.is_drink("luck_cocktail"))


func test_blackout_screen_and_body_follow_each_phase() -> void:
	var phase := BoozeRules.Phase
	assert_eq(BoozeRules.darkness(phase.NONE, 1.0), 0.0)
	assert_lt(BoozeRules.darkness(phase.COLLAPSE, 0.5), 0.1)
	assert_eq(BoozeRules.darkness(phase.COLLAPSE, BoozeRules.COLLAPSE_S), 1.0)
	assert_eq(BoozeRules.darkness(phase.OUT, 0.0), 1.0)
	assert_eq(BoozeRules.darkness(phase.WAKE, 0.2), 1.0, "wake starts black")
	assert_gt(BoozeRules.darkness(phase.WAKE, 2.0), BoozeRules.darkness(phase.WAKE, 1.7), "blink")
	assert_eq(BoozeRules.darkness(phase.WAKE, 4.0), 0.0)
	assert_eq(BoozeRules.lying_target(phase.COLLAPSE, 0.0), 1.0)
	assert_eq(BoozeRules.lying_target(phase.OUT, 9.0), 1.0)
	assert_eq(BoozeRules.lying_target(phase.WAKE, 1.0), 1.0, "still on the floor while waking")
	assert_eq(BoozeRules.lying_target(phase.WAKE, BoozeRules.WAKE_S - 1.0), 0.0, "stands up")
	assert_eq(BoozeRules.lying_target(phase.NONE, 0.0), 0.0)
	assert_eq(BoozeRules.caption(phase.OUT, 0.0), "You blacked out.")
	assert_string_contains(BoozeRules.caption(phase.WAKE, 1.0), "clothes")
	assert_eq(BoozeRules.caption(phase.NONE, 0.0), "")


func test_lying_body_rests_on_its_back_on_the_floor() -> void:
	var hull := 1.8288
	for height: float in [1.0, 1.8288, 3.0]:
		for yaw: float in [0.0, 1.1, PI]:
			var standing := BoozeRules.lying_body(yaw, hull, height, 0.0)
			assert_true(standing.basis.is_equal_approx(Basis(Vector3.UP, yaw)))
			assert_true(standing.origin.is_zero_approx())
			var flat := BoozeRules.lying_body(yaw, hull, height, 1.0)
			var feet := flat * Vector3(0, -hull * 0.5, 0)
			var head := flat * Vector3(0, -hull * 0.5 + height, 0)
			var floor_y := -hull * 0.5
			var lift := height * BoozeRules.LIFT_SHARE
			assert_almost_eq(feet.y, floor_y + lift, 0.001, "feet on the ground")
			assert_almost_eq(head.y, floor_y + lift, 0.001, "head on the ground")
			assert_almost_eq(feet.distance_to(head), height, 0.001)
			# Centred on the capsule so nothing reaches past half a body length.
			var middle := (feet + head) * 0.5
			assert_almost_eq(Vector2(middle.x, middle.z).length(), 0.0, 0.001)
			# Face up, back down: the front (-Z) of the body points at the ceiling.
			assert_true((flat.basis * Vector3.FORWARD).is_equal_approx(Vector3.UP))
			# Head lies behind the facing direction.
			var behind := Basis(Vector3.UP, yaw) * Vector3.BACK
			assert_gt((head - feet).normalized().dot(behind), 0.999)


func test_first_person_lying_eye_is_near_the_floor_and_looks_up() -> void:
	var origin := Vector3(4, 2.14, 10)
	var eye := BoozeRules.lying_eye(origin, 0.0, 1.8288, 1.8288)
	var floor_y := origin.y - 0.9144
	assert_between(eye.origin.y - floor_y, 0.1, 0.35)
	assert_gt((eye.basis * Vector3.FORWARD).y, 0.9)
	assert_lt(Vector2(eye.origin.x - origin.x, eye.origin.z - origin.z).length(), 0.9144)


func test_wake_spots_are_on_island_lanes_clear_of_both_tracks() -> void:
	var hull := 1.8288
	for station: int in 4:
		for side: int in 2:
			for along: float in [0.0, 0.5, 1.0]:
				var spot := BoozeRules.wake_spot(station, side, along, hull)
				var local: Vector3 = spot["local"]
				assert_eq(spot["station"], station)
				assert_between(local.x, 2.0 + 1.0, 14.0 - 1.0, "inside the island")
				assert_almost_eq(local.y - hull * 0.5, BoozeRules.PLATFORM_FLOOR + 0.02, 0.001)
				assert_between(absf(local.z), 0.0, 54.0)
				assert_eq(
					local.x,
					(
						(
							MetroRules.track_offset(side)
							+ MetroRules.platform_recovery(Vector3(0, 0, local.z), side)
						)
						. x
					)
				)
				# Lying parallel to the tracks keeps the whole body on the platform.
				var flat := BoozeRules.lying_body(float(spot["yaw"]), hull, hull, 1.0)
				for point: Vector3 in [Vector3(0, -hull * 0.5, 0), Vector3(0, hull * 0.5, 0)]:
					var world := local + flat * point
					assert_between(world.x, 2.5, 13.5)
					for track: int in 2:
						var relative := world - MetroRules.track_offset(track)
						assert_false(
							MetroRules.train_hits(relative, 0.41, 0.3, MetroRules.DEPART, 30.0)
						)
