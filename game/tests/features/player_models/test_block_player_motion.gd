extends GutTest


func test_idle_walk_run_and_air_states() -> void:
	assert_eq(BlockPlayerMotion.state(Vector3.ZERO, true, 8.0), &"idle")
	assert_eq(BlockPlayerMotion.state(Vector3(0, 0, -2), true, 8.0), &"walk")
	assert_eq(BlockPlayerMotion.state(Vector3(0, 0, -8), true, 8.0), &"run")
	assert_eq(BlockPlayerMotion.state(Vector3(0, 6, -2), false, 8.0), &"jump")
	assert_eq(BlockPlayerMotion.state(Vector3.ZERO, false, 8.0), &"fall")
	assert_eq(BlockPlayerMotion.state(Vector3(0, -4, 0), false, 8.0), &"fall")


func test_running_has_a_faster_and_larger_stride_than_walking() -> void:
	var walk := BlockPlayerMotion.pose(PI * 0.5, Vector3(0, 0, -2), true, 8.0)
	var run := BlockPlayerMotion.pose(PI * 0.5, Vector3(0, 0, -8), true, 8.0)
	assert_gt(float(run["left_leg"]), float(walk["left_leg"]))
	assert_lt(float(run["lean"]), float(walk["lean"]))
	assert_gt(BlockPlayerMotion.phase_step(8, 8, 0.1), BlockPlayerMotion.phase_step(2, 8, 0.1))


func test_opposite_arms_and_legs_and_backwards_stride() -> void:
	var forward := BlockPlayerMotion.pose(PI * 0.5, Vector3(0, 0, -3), true, 8.0)
	var backward := BlockPlayerMotion.pose(PI * 0.5, Vector3(0, 0, 3), true, 8.0)
	assert_eq(forward["left_leg"], -float(forward["right_leg"]))
	assert_lt(float(forward["left_arm"]), 0.0)
	assert_eq(forward["left_leg"], -float(backward["left_leg"]))


func test_strafing_moves_limbs_and_leans_into_the_turn() -> void:
	var pose := BlockPlayerMotion.pose(PI * 0.5, Vector3(4, 0, 0), true, 8.0)
	assert_gt(absf(float(pose["left_leg"])), 0.0)
	assert_lt(float(pose["roll"]), 0.0)


func test_idle_removes_stride_and_jumping_does_not_cycle_legs() -> void:
	var idle := BlockPlayerMotion.pose(PI * 0.5, Vector3.ZERO, true, 8.0)
	assert_eq(float(idle["left_leg"]), 0.0)
	assert_eq(float(idle["right_arm"]), 0.0)
	var first := BlockPlayerMotion.pose(0, Vector3(0, 6, -5), false, 8.0)
	var later := BlockPlayerMotion.pose(PI, Vector3(0, 6, -5), false, 8.0)
	assert_eq(first, later)
