extends GutTest


func test_turning_lags_then_settles_without_changing_aim() -> void:
	var motion := FirstPersonMotion.new()
	motion.advance(Vector2.ZERO, Vector3.ZERO, 0.01)
	var pose := motion.advance(Vector2(0.04, 0.02), Vector3.ZERO, 0.01)
	assert_gt(pose.origin.x, 0.0)
	assert_lt(pose.origin.y, 0.0)
	assert_false(pose.basis.is_equal_approx(Basis.IDENTITY))
	for frame: int in 120:
		pose = motion.advance(Vector2(0.04, 0.02), Vector3.ZERO, 1.0 / 60.0)
	assert_almost_eq(pose.origin, Vector3.ZERO, Vector3.ONE * 0.00001)


func test_yaw_wrap_does_not_create_a_large_sway() -> void:
	var wrapped := FirstPersonMotion.new()
	var continuous := FirstPersonMotion.new()
	wrapped.advance(Vector2(PI - 0.01, 0.0), Vector3.ZERO, 0.01)
	continuous.advance(Vector2.ZERO, Vector3.ZERO, 0.01)
	var pose := wrapped.advance(Vector2(-PI + 0.01, 0.0), Vector3.ZERO, 0.01)
	var expected := continuous.advance(Vector2(0.02, 0.0), Vector3.ZERO, 0.01)
	assert_almost_eq(pose.origin, expected.origin, Vector3.ONE * 0.00001)


func test_bob_uses_horizontal_velocity_in_every_direction_and_settles_at_rest() -> void:
	var forward := FirstPersonMotion.new()
	var strafe := FirstPersonMotion.new()
	var pose := Transform3D.IDENTITY
	for frame: int in 30:
		pose = forward.advance(Vector2.ZERO, Vector3(0, 0, -8), 1.0 / 60.0)
		var sideways := strafe.advance(Vector2.ZERO, Vector3(8, 0, 0), 1.0 / 60.0)
		assert_almost_eq(pose.origin.y, sideways.origin.y, 0.00001)
	assert_gt(pose.origin.length(), 0.001)
	for frame: int in 120:
		pose = forward.advance(Vector2.ZERO, Vector3.ZERO, 1.0 / 60.0)
	assert_almost_eq(pose.origin, Vector3.ZERO, Vector3.ONE * 0.00001)


func test_vertical_momentum_lags_rising_and_falling_then_settles() -> void:
	var motion := FirstPersonMotion.new()
	var pose := Transform3D.IDENTITY
	for frame: int in 120:
		pose = motion.advance(Vector2.ZERO, Vector3(0, 8, 0), 1.0 / 60.0)
	assert_lt(pose.origin.y, -0.01, "Rising lowers the handheld, even without horizontal bob")
	assert_almost_eq(pose.origin.x, 0.0, 0.00001)
	assert_almost_eq(pose.origin.z, 0.0, 0.00001)
	for frame: int in 120:
		pose = motion.advance(Vector2.ZERO, Vector3(0, -8, 0), 1.0 / 60.0)
	assert_gt(pose.origin.y, 0.01, "Falling raises the handheld")
	for frame: int in 120:
		pose = motion.advance(Vector2.ZERO, Vector3.ZERO, 1.0 / 60.0)
	assert_almost_eq(pose.origin, Vector3.ZERO, Vector3.ONE * 0.00001)
	motion.reset()
	assert_eq(motion.camera_motion, Transform3D.IDENTITY)
	assert_eq(motion.advance(Vector2.ZERO, Vector3.ZERO, 1.0 / 60.0), Transform3D.IDENTITY)


func test_motion_is_consistent_at_different_render_rates() -> void:
	var slow := FirstPersonMotion.new()
	var fast := FirstPersonMotion.new()
	slow.advance(Vector2.ZERO, Vector3.ZERO, 0.0)
	fast.advance(Vector2.ZERO, Vector3.ZERO, 0.0)
	var a := Transform3D.IDENTITY
	var b := Transform3D.IDENTITY
	for frame: int in 30:
		a = slow.advance(Vector2((frame + 1) / 30.0, 0.0), Vector3(0, 0, -8), 1.0 / 30.0)
	for frame: int in 144:
		b = fast.advance(Vector2((frame + 1) / 144.0, 0.0), Vector3(0, 0, -8), 1.0 / 144.0)
	assert_almost_eq(a.origin, b.origin, Vector3.ONE * 0.004)
	assert_almost_eq(a.basis.get_euler(), b.basis.get_euler(), Vector3.ONE * 0.001)
