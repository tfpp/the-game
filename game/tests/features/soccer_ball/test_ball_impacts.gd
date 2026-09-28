extends GutTest
## Pure math for the soccer_ball feature's player bumps, gun kicks and rolling spin
## (features/soccer_ball/ball_physics.gd). Gravity/drag/bounce math lives in
## test_ball_physics.gd — split so neither file trips gdlint's public-method cap.

const BallPhysics := preload("res://features/soccer_ball/ball_physics.gd")


func test_bump_velocity_pushes_the_ball_away_from_an_overlapping_player() -> void:
	var result := BallPhysics.bump_velocity(
		Vector3.ZERO, Vector3.ZERO, Vector3(0.2, 0, 0), Vector3.ZERO, 0.5, 6.0, 0.9, 18.0
	)
	assert_lt(result.x, 0.0, "A player standing to the +X side should shove the ball toward -X")
	assert_almost_eq(result.y, 0.0, 0.0001)


func test_bump_velocity_ignores_a_player_out_of_range() -> void:
	var unchanged := Vector3(1, -2, 3)
	var result := BallPhysics.bump_velocity(
		Vector3.ZERO, unchanged, Vector3(5, 0, 0), Vector3.ZERO, 0.5
	)
	assert_eq(result, unchanged)


func test_bump_velocity_adds_a_share_of_the_players_closing_speed() -> void:
	var slow := BallPhysics.bump_velocity(
		Vector3.ZERO, Vector3.ZERO, Vector3(0.4, 0, 0), Vector3.ZERO, 0.5, 6.0, 0.9, 18.0
	)
	var fast := BallPhysics.bump_velocity(
		Vector3.ZERO, Vector3.ZERO, Vector3(0.4, 0, 0), Vector3(-5, 0, 0), 0.5, 6.0, 0.9, 18.0
	)
	assert_lt(fast.x, slow.x, "Running into the ball should shove it harder than standing still")


func test_kick_velocity_adds_speed_away_from_the_shooter_with_upward_pop() -> void:
	var result := BallPhysics.kick_velocity(
		Vector3.ZERO, Vector3(-1, 0, 0), Vector3.ZERO, 9.0, 2.0, 18.0
	)
	assert_almost_eq(result.x, 9.0, 0.0001)
	assert_almost_eq(result.y, 2.0, 0.0001)
	assert_almost_eq(result.z, 0.0, 0.0001)


func test_kick_velocity_is_capped_by_max_speed() -> void:
	var result := BallPhysics.kick_velocity(
		Vector3(20, 0, 0), Vector3(-1, 0, 0), Vector3.ZERO, 9.0, 2.0, 12.0
	)
	assert_almost_eq(Vector3(result.x, 0, result.z).length(), 12.0, 0.0001)


func test_rolling_spin_is_identity_when_the_ball_did_not_move() -> void:
	assert_eq(BallPhysics.rolling_spin(Vector3.ZERO, 0.12), Quaternion.IDENTITY)


func test_rolling_spin_rotates_by_distance_over_radius() -> void:
	var spin := BallPhysics.rolling_spin(Vector3(0.24, 0, 0), 0.12)
	assert_almost_eq(spin.get_angle(), 2.0, 0.0001)
