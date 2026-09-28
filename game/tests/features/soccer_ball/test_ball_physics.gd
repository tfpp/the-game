extends GutTest
## Pure motion math for the soccer_ball feature (features/soccer_ball/ball_physics.gd):
## gravity, drag, settling, and bouncing off the floor or a wall. Player bumps, gun
## kicks and the rolling spin live in test_ball_impacts.gd — split so neither file
## trips gdlint's public-method cap.

const BallPhysics := preload("res://features/soccer_ball/ball_physics.gd")


func test_gravity_pulls_velocity_down() -> void:
	var result := BallPhysics.apply_gravity(Vector3.ZERO, 0.5, 10.0)
	assert_eq(result, Vector3(0, -5, 0))


func test_gravity_leaves_horizontal_velocity_alone() -> void:
	var result := BallPhysics.apply_gravity(Vector3(3, 0, -2), 0.5, 10.0)
	assert_eq(result, Vector3(3, -5, -2))


func test_drag_decays_horizontal_speed_over_time() -> void:
	var result := BallPhysics.apply_drag(Vector3(10, -4, 0), 1.0, 1.0)
	assert_almost_eq(result.x, 10.0 * exp(-1.0), 0.0001)
	assert_almost_eq(result.z, 0.0, 0.0001)


func test_drag_never_touches_vertical_speed() -> void:
	var result := BallPhysics.apply_drag(Vector3(10, -4, 5), 1.0, 100.0)
	assert_eq(result.y, -4.0)


func test_settle_zeroes_a_slow_horizontal_creep() -> void:
	var result := BallPhysics.settle(Vector3(0.01, -1.0, 0.01), 0.12)
	assert_eq(result, Vector3(0, -1.0, 0))


func test_settle_leaves_a_real_roll_alone() -> void:
	var rolling := Vector3(2.0, 0.0, 0.0)
	assert_eq(BallPhysics.settle(rolling, 0.12), rolling)


func test_bounce_off_floor_flips_and_scales_downward_speed() -> void:
	var result := BallPhysics.bounce_off_floor(Vector3(1, -4, 0), 0.5)
	assert_eq(result, Vector3(1, 2, 0))


func test_bounce_off_floor_ignores_a_ball_already_rising() -> void:
	var rising := Vector3(1, 3, 0)
	assert_eq(BallPhysics.bounce_off_floor(rising, 0.5), rising)


func test_bounce_off_floor_settles_on_a_soft_impact_instead_of_bouncing() -> void:
	var result := BallPhysics.bounce_off_floor(Vector3(2, -0.3, 0), 0.5, 0.6)
	assert_eq(result, Vector3(2, 0.0, 0))


func test_bounce_off_floor_still_bounces_a_real_impact() -> void:
	var result := BallPhysics.bounce_off_floor(Vector3(2, -4.0, 0), 0.5, 0.6)
	assert_almost_eq(result.y, 2.0, 0.0001)


func test_reflect_off_wall_mirrors_speed_driving_into_it() -> void:
	# Hitting a wall facing -X head on at speed 4 should bounce back along +X.
	var result := BallPhysics.reflect_off_wall(Vector3(-4, 0, 0), Vector3(1, 0, 0), 1.0)
	assert_almost_eq(result.x, 4.0, 0.0001)


func test_reflect_off_wall_loses_speed_to_restitution() -> void:
	var result := BallPhysics.reflect_off_wall(Vector3(-4, 0, 0), Vector3(1, 0, 0), 0.5)
	assert_almost_eq(result.x, 2.0, 0.0001)


func test_reflect_off_wall_ignores_motion_moving_away() -> void:
	var leaving := Vector3(4, 0, 0)
	assert_eq(BallPhysics.reflect_off_wall(leaving, Vector3(1, 0, 0), 0.5), leaving)


func test_clamp_horizontal_speed_caps_fast_horizontal_motion() -> void:
	var result := BallPhysics.clamp_horizontal_speed(Vector3(30, 5, 0), 10.0)
	assert_almost_eq(Vector3(result.x, 0, result.z).length(), 10.0, 0.0001)
	assert_eq(result.y, 5.0)


func test_clamp_horizontal_speed_leaves_slow_motion_alone() -> void:
	var slow := Vector3(1, 5, 1)
	assert_eq(BallPhysics.clamp_horizontal_speed(slow, 10.0), slow)
