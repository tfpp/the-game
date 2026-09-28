extends GutTest
## Pure patrol math for the penguin feature (features/penguin/penguin_waddle.gd).

const PenguinWaddle := preload("res://features/penguin/penguin_waddle.gd")


func test_position_on_circle_stays_at_the_requested_radius_from_home() -> void:
	var home := Vector3(5, 0, -3)
	for i: int in 12:
		var angle := TAU * i / 12.0
		var pos := PenguinWaddle.position_on_circle(home, 2.0, angle)
		assert_almost_eq(home.distance_to(pos), 2.0, 0.001)
		assert_almost_eq(pos.y, home.y, 0.0001)


func test_position_on_circle_at_zero_angle_is_along_positive_z() -> void:
	var pos := PenguinWaddle.position_on_circle(Vector3.ZERO, 2.0, 0.0)
	assert_almost_eq(pos.x, 0.0, 0.0001)
	assert_almost_eq(pos.z, 2.0, 0.0001)


func test_angular_speed_scales_inversely_with_radius() -> void:
	assert_almost_eq(PenguinWaddle.angular_speed(2.0, 1.0), 0.5, 0.0001)
	assert_almost_eq(PenguinWaddle.angular_speed(1.0, 1.0), 1.0, 0.0001)


func test_angular_speed_is_zero_for_a_degenerate_radius() -> void:
	assert_eq(PenguinWaddle.angular_speed(0.0, 1.0), 0.0)
	assert_eq(PenguinWaddle.angular_speed(-1.0, 1.0), 0.0)


func test_facing_yaw_matches_the_direction_of_travel_around_the_circle() -> void:
	var angle := 0.7
	var epsilon := 0.0005
	var before := PenguinWaddle.position_on_circle(Vector3.ZERO, 2.0, angle - epsilon)
	var after := PenguinWaddle.position_on_circle(Vector3.ZERO, 2.0, angle + epsilon)
	var travel := (after - before).normalized()

	var yaw := PenguinWaddle.facing_yaw(angle)
	var forward := Vector3.BACK.rotated(Vector3.UP, yaw)

	assert_almost_eq(forward.x, travel.x, 0.001)
	assert_almost_eq(forward.z, travel.z, 0.001)


func test_waddle_rock_is_zero_at_the_start_and_oscillates_within_amplitude() -> void:
	assert_almost_eq(PenguinWaddle.waddle_rock(0.0, 2.0, 0.3), 0.0, 0.0001)
	for i: int in 20:
		var t := i * 0.05
		var rock := PenguinWaddle.waddle_rock(t, 2.0, 0.3)
		assert_true(rock >= -0.3 - 0.0001 and rock <= 0.3 + 0.0001)


func test_waddle_rock_scales_with_amplitude() -> void:
	var rock := PenguinWaddle.waddle_rock(0.25, 1.0, 0.5)
	assert_almost_eq(rock, 0.5, 0.0001)


func test_wave_angle_is_zero_at_the_start_and_oscillates_within_amplitude() -> void:
	assert_almost_eq(PenguinWaddle.wave_angle(0.0, 3.0, 0.9), 0.0, 0.0001)
	for i: int in 20:
		var t := i * 0.05
		var wave := PenguinWaddle.wave_angle(t, 3.0, 0.9)
		assert_true(wave >= -0.9 - 0.0001 and wave <= 0.9 + 0.0001)


func test_react_bounce_is_never_negative_and_stays_within_height() -> void:
	for i: int in 20:
		var t := i * 0.05
		var bounce := PenguinWaddle.react_bounce(t, 2.6, 0.22)
		assert_true(bounce >= -0.0001 and bounce <= 0.22 + 0.0001)


func test_react_bounce_touches_the_ground_between_hops() -> void:
	assert_almost_eq(PenguinWaddle.react_bounce(0.0, 2.6, 0.22), 0.0, 0.0001)
