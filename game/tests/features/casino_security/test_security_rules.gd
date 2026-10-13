extends GutTest
## Pure security rules: offences, jurisdiction, grabbing, dispatch, and the poses
## of a carried and thrown body.


func test_known_offences_have_names_and_callouts() -> void:
	for offence: StringName in [&"firearm", &"assault", &"security", &"vandalism"]:
		assert_true(SecurityRules.is_offence(offence))
		assert_false(SecurityRules.offence_name(offence).is_empty())
		assert_ne(SecurityRules.callout(offence), "Freeze.", "%s has its own line" % offence)
	assert_false(SecurityRules.is_offence(&"breathing"))
	assert_eq(SecurityRules.offence_name(&"breathing"), "Causing trouble")


func test_jurisdiction_is_the_main_hall_only() -> void:
	assert_true(SecurityRules.in_jurisdiction(Vector3(0, 0.9, -16)), "crown spawn")
	assert_true(SecurityRules.in_jurisdiction(Vector3(5, -0.3, 0)), "gaming pit")
	assert_false(SecurityRules.in_jurisdiction(Vector3(-29, 7.0, 0)), "mariachi balcony")
	assert_false(SecurityRules.in_jurisdiction(Vector3(0, 0.9, 25)), "south corridor")
	assert_false(SecurityRules.in_jurisdiction(Vector3(0, 0.9, -600)), "lounge room")
	assert_false(SecurityRules.in_jurisdiction(Vector3(0, -6, 0)), "garage below")


func test_grab_needs_the_guard_close_and_not_far_below() -> void:
	var guard := Vector3(0, 0, 0)
	assert_true(SecurityRules.can_grab(guard, Vector3(0.8, 0, 0.3)))
	assert_false(SecurityRules.can_grab(guard, Vector3(1.7, 0, 0)), "too far")
	assert_true(SecurityRules.can_grab(guard, Vector3(0.6, 0.85, 0)), "standing on a table")
	assert_false(SecurityRules.can_grab(guard, Vector3(0.6, 2.5, 0)), "up on a balcony")
	assert_false(SecurityRules.can_grab(guard, Vector3(0.6, -1.25, 0)), "down in the pit")


func test_nearest_free_guard_answers() -> void:
	var at: Array[Vector3] = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(3, 0, 0)]
	assert_eq(SecurityRules.pick_guard(at, [true, true, true], Vector3(4, 0, 0)), 2)
	assert_eq(SecurityRules.pick_guard(at, [true, true, false], Vector3(4, 0, 0)), 0)
	assert_eq(SecurityRules.pick_guard(at, [false, false, false], Vector3(4, 0, 0)), -1)


func test_carried_body_lies_over_the_right_shoulder_head_down_the_back() -> void:
	var guard := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 0, -2))
	var body := SecurityRules.carry_body(guard)
	var local := guard.affine_inverse() * body
	assert_almost_eq(local.origin, SecurityRules.CARRY_SHOULDER, Vector3.ONE * 0.001)
	assert_gt(local.origin.x, 0.0, "right shoulder (+X for a -Z facing guard)")
	assert_gt(local.origin.y, 1.5, "up on the shoulder")
	var head := local.basis.y
	assert_gt(head.z, 0.9, "head points behind the guard")
	assert_lt(head.y, -0.1, "and droops down the back")
	assert_gt(local.basis.z.y, 0.9, "body +Z up, so the belly (-Z) lies on the shoulder")
	assert_almost_eq(local.basis.determinant(), 1.0, 0.001, "a proper rotation")
	assert_eq(SecurityRules.carry_point(guard), body.origin)


func test_lift_goes_from_standing_to_the_shoulder() -> void:
	var guard := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var start := Transform3D(Basis.IDENTITY, Vector3(0, 0.9, -0.9))
	assert_almost_eq(
		SecurityRules.lifted_body(start, guard, 0.0).origin, start.origin, Vector3.ONE * 0.001
	)
	var top := SecurityRules.lifted_body(start, guard, 1.0)
	assert_almost_eq(top.origin, SecurityRules.carry_body(guard).origin, Vector3.ONE * 0.001)
	assert_gt(SecurityRules.lifted_body(start, guard, 0.5).origin.y, start.origin.y)


func test_flight_arcs_from_the_shoulder_into_the_cab_and_tumbles() -> void:
	var from := SecurityRules.carry_body(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	var to := Vector3(0, 1.0, 3.0)
	assert_almost_eq(
		SecurityRules.flight_body(from, to, 0.0).origin, from.origin, Vector3.ONE * 0.001
	)
	var mid := SecurityRules.flight_body(from, to, SecurityRules.FLIGHT_S * 0.5)
	assert_gt(mid.origin.y, lerpf(from.origin.y, to.y, 0.5), "arcs upward")
	var end := SecurityRules.flight_body(from, to, SecurityRules.FLIGHT_S * 3.0)
	assert_almost_eq(end.origin, to, Vector3.ONE * 0.001)
	assert_lt(end.basis.y.dot(from.basis.y), -0.9, "half a somersault on the way")


func test_screen_fades_out_through_the_throw_and_back_in_on_landing() -> void:
	assert_eq(SecurityRules.darkness(SecurityRules.Phase.HELD, 3.0), 0.0)
	assert_eq(SecurityRules.darkness(SecurityRules.Phase.CARRIED, 3.0), 0.0)
	assert_eq(SecurityRules.darkness(SecurityRules.Phase.THROWN, 0.0), 0.0)
	assert_eq(SecurityRules.darkness(SecurityRules.Phase.THROWN, SecurityRules.FLIGHT_S), 1.0)
	assert_eq(SecurityRules.darkness(SecurityRules.Phase.LANDED, 0.0), 1.0)
	assert_eq(SecurityRules.darkness(SecurityRules.Phase.LANDED, 2.0), 0.0)
	assert_string_contains(
		SecurityRules.caption(SecurityRules.Phase.LANDED, &"vandalism"), "Spray-painting"
	)
	assert_eq(SecurityRules.caption(SecurityRules.Phase.NONE, &"firearm"), "")


func test_guard_pose_and_pace_follow_its_state() -> void:
	var posted := SecurityRules.guard_pose(SecurityRules.GuardState.POSTED, 2.0)
	assert_eq(posted["arms"], 1.0, "arms crossed on watch")
	assert_eq(posted["carry"], 0.0)
	var carrying := SecurityRules.guard_pose(SecurityRules.GuardState.CARRYING, 0.5)
	assert_eq(carrying["carry"], 1.0)
	var released := SecurityRules.guard_pose(
		SecurityRules.GuardState.THROWING, SecurityRules.THROW_S
	)
	assert_eq(released["carry"], 0.0, "hands empty after the throw")
	assert_gt(SecurityRules.speed_for(SecurityRules.GuardState.RESPONDING), 4.0, "jogs over")
	assert_lt(
		SecurityRules.speed_for(SecurityRules.GuardState.CARRYING),
		SecurityRules.speed_for(SecurityRules.GuardState.RESPONDING)
	)
	assert_eq(SecurityRules.speed_for(SecurityRules.GuardState.LIFTING), 0.0)
