extends GutTest


func test_fall_is_a_no_op_at_zero_gravity_scale() -> void:
	var velocity := Vector3(10, 0, 0)
	assert_eq(ProjectileMath.fall(velocity, 0.0, 0.5), velocity)


func test_fall_pulls_velocity_downward_over_time() -> void:
	var velocity := ProjectileMath.fall(Vector3(10, 0, 0), 1.0, 1.0)
	assert_eq(velocity.x, 10.0)
	assert_lt(velocity.y, 0.0)


func test_bounce_reflects_and_loses_energy() -> void:
	var incoming := Vector3(1, -1, 0)
	var reflected := ProjectileMath.bounce(incoming, Vector3.UP)
	assert_gt(reflected.y, 0.0, "bouncing off the floor should send it back up")
	assert_lt(reflected.length(), incoming.length(), "a bounce should lose energy")


func test_should_settle_below_threshold() -> void:
	assert_true(ProjectileMath.should_settle(Vector3(0.1, 0.1, 0.0)))
	assert_false(ProjectileMath.should_settle(Vector3(5.0, 0.0, 0.0)))


func test_splash_damage_falls_off_linearly_to_zero_at_the_radius() -> void:
	assert_eq(ProjectileMath.splash_damage(0.0, 4.0, 100.0), 100.0)
	assert_eq(ProjectileMath.splash_damage(2.0, 4.0, 100.0), 50.0)
	assert_eq(ProjectileMath.splash_damage(4.0, 4.0, 100.0), 0.0)
	assert_eq(ProjectileMath.splash_damage(10.0, 4.0, 100.0), 0.0)
	assert_eq(ProjectileMath.splash_damage(1.0, 0.0, 100.0), 0.0)
