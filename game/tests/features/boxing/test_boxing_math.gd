extends GutTest
## Pure punch rules (features/boxing/boxing_math.gd) and the fist swing curve.


func test_a_quick_click_is_a_jab() -> void:
	assert_false(BoxingMath.is_power(0.1))
	assert_eq(BoxingMath.strength(0.1), BoxingMath.JAB_STRENGTH)


func test_holding_winds_up_a_power_punch_that_grows_to_full() -> void:
	assert_true(BoxingMath.is_power(BoxingMath.JAB_MAX_HOLD_S))
	assert_almost_eq(
		BoxingMath.strength(BoxingMath.JAB_MAX_HOLD_S), BoxingMath.MIN_POWER_STRENGTH, 0.001
	)
	assert_gt(BoxingMath.strength(0.6), BoxingMath.MIN_POWER_STRENGTH)
	assert_almost_eq(BoxingMath.strength(5.0), BoxingMath.MAX_POWER_STRENGTH, 0.001)


func test_a_full_power_punch_knocks_down_and_a_jab_does_not() -> void:
	assert_gte(BoxingMath.strength(BoxingMath.FULL_CHARGE_S), HumanoidTarget.KNOCKDOWN_DAZE)
	assert_lt(BoxingMath.JAB_STRENGTH, HumanoidTarget.KNOCKDOWN_DAZE)
	assert_gte(BoxingMath.MIN_POWER_STRENGTH, HumanoidTarget.KNOCK_AWAY_MIN_STRENGTH)
	assert_lt(BoxingMath.JAB_STRENGTH, HumanoidTarget.KNOCK_AWAY_MIN_STRENGTH)


func test_push_direction_is_forward_for_the_yaw() -> void:
	assert_almost_eq(BoxingMath.push_direction(0.0), Vector3(0, 0, -1), Vector3.ONE * 0.001)
	assert_almost_eq(BoxingMath.push_direction(PI * 0.5), Vector3(-1, 0, 0), Vector3.ONE * 0.001)


func test_knock_away_is_a_small_distance() -> void:
	var far := BoxingMath.slide_distance(
		HumanoidTarget.KNOCK_AWAY_SPEED, HumanoidTarget.SLIDE_FRICTION
	)
	assert_between(far, 1.5, 4.0)


func test_fist_swing_snaps_out_and_returns() -> void:
	assert_almost_eq(BoxingFists.swing_reach(0.0), 0.0, 0.001)
	assert_almost_eq(BoxingFists.swing_reach(0.35), 0.45, 0.001)
	assert_almost_eq(BoxingFists.swing_reach(1.0), 0.0, 0.001)
