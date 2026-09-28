extends GutTest
## Pure toss math for the holdables feature (features/holdables/throw_math.gd).

const ThrowMath := preload("res://features/holdables/throw_math.gd")


func test_arc_position_starts_and_ends_on_the_straight_line() -> void:
	var from := Vector3(0, 1, 0)
	var to := Vector3(4, 1, 0)
	assert_eq(ThrowMath.arc_position(from, to, 0.0), from)
	assert_true(ThrowMath.arc_position(from, to, 1.0).is_equal_approx(to))


func test_arc_position_peaks_above_the_midpoint() -> void:
	var pos := ThrowMath.arc_position(Vector3.ZERO, Vector3(4, 0, 0), 0.5)
	assert_almost_eq(pos.x, 2.0, 0.0001)
	assert_almost_eq(pos.y, ThrowMath.ARC_HEIGHT, 0.0001)


func test_arc_position_clamps_t_outside_zero_one() -> void:
	var from := Vector3(1, 0, 1)
	var to := Vector3(3, 0, 5)
	assert_eq(ThrowMath.arc_position(from, to, -1.0), from)
	assert_true(ThrowMath.arc_position(from, to, 2.0).is_equal_approx(to))


func test_aim_direction_at_zero_faces_negative_z() -> void:
	var dir := ThrowMath.aim_direction(0.0, 0.0)
	assert_true(dir.is_equal_approx(Vector3(0, 0, -1)))


func test_aim_direction_pitch_tilts_up_and_down() -> void:
	var up := ThrowMath.aim_direction(0.0, deg_to_rad(45.0))
	assert_true(up.y > 0.5)
	var down := ThrowMath.aim_direction(0.0, deg_to_rad(-45.0))
	assert_true(down.y < -0.5)


func test_toss_target_ignores_vertical_aim_and_keeps_the_flat_distance() -> void:
	var origin := Vector3(0, 2, 0)
	var direction := Vector3(0, -1, -1)  # looking down and forward
	var result := ThrowMath.toss_target(origin, direction, 3.0)
	assert_almost_eq(result.y, origin.y, 0.0001)
	assert_almost_eq(origin.distance_to(result), 3.0, 0.0001)


func test_toss_target_falls_back_to_forward_when_aim_is_straight_down() -> void:
	var result := ThrowMath.toss_target(Vector3.ZERO, Vector3.DOWN, 2.0)
	assert_true(result.is_equal_approx(Vector3.FORWARD * 2.0))


func test_arc_position_accepts_a_custom_peak_height() -> void:
	var pos := ThrowMath.arc_position(Vector3.ZERO, Vector3(2, 0, 0), 0.5, 0.2)
	assert_almost_eq(pos.y, 0.2, 0.0001)


func test_bounce_height_decreases_as_weight_increases() -> void:
	var light := ThrowMath.bounce_height(0.0, 0)
	var medium := ThrowMath.bounce_height(
		ThrowMath.BOUNCE_BASE_HEIGHT * ThrowMath.BOUNCE_WEIGHT_DIVISOR * 0.5, 0
	)
	assert_gt(light, medium)
	assert_gt(medium, 0.0)


func test_bounce_height_is_zero_for_a_heavy_enough_item() -> void:
	var weight := ThrowMath.BOUNCE_BASE_HEIGHT * ThrowMath.BOUNCE_WEIGHT_DIVISOR
	assert_eq(ThrowMath.bounce_height(weight, 0), 0.0)
	assert_eq(ThrowMath.bounce_height(weight * 2.0, 0), 0.0)


func test_bounce_height_decays_with_each_bounce() -> void:
	var first := ThrowMath.bounce_height(0.0, 0)
	var second := ThrowMath.bounce_height(0.0, 1)
	assert_almost_eq(second, first * ThrowMath.BOUNCE_DECAY, 0.0001)


func test_bounce_distance_decays_with_each_bounce() -> void:
	assert_almost_eq(ThrowMath.bounce_distance(0), ThrowMath.BOUNCE_DISTANCE, 0.0001)
	assert_almost_eq(
		ThrowMath.bounce_distance(1), ThrowMath.BOUNCE_DISTANCE * ThrowMath.BOUNCE_DECAY, 0.0001
	)
