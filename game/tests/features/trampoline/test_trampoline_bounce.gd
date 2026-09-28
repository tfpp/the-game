extends GutTest
## Pure launch-velocity math for the trampoline feature (features/trampoline/trampoline_bounce.gd).

const TrampolineBounce := preload("res://features/trampoline/trampoline_bounce.gd")


func test_launch_velocity_is_at_least_the_base_speed_when_standing_still() -> void:
	assert_almost_eq(TrampolineBounce.launch_velocity_y(0.0, 12.0, 0.5, 20.0), 12.0, 0.0001)


func test_launch_velocity_ignores_upward_incoming_velocity() -> void:
	assert_almost_eq(TrampolineBounce.launch_velocity_y(5.0, 12.0, 0.5, 20.0), 12.0, 0.0001)


func test_launch_velocity_grows_with_fall_speed() -> void:
	assert_almost_eq(TrampolineBounce.launch_velocity_y(-10.0, 12.0, 0.5, 20.0), 17.0, 0.0001)


func test_launch_velocity_is_capped() -> void:
	assert_almost_eq(TrampolineBounce.launch_velocity_y(-100.0, 12.0, 0.5, 20.0), 20.0, 0.0001)


func test_default_arguments_match_the_named_constants() -> void:
	assert_almost_eq(
		TrampolineBounce.launch_velocity_y(-4.0),
		TrampolineBounce.BASE_LAUNCH_M_S + 4.0 * TrampolineBounce.FALL_GAIN,
		0.0001
	)
