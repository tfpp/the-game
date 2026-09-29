extends GutTest
## Tests pure math and target rules for the wandering bird feature.


func test_arc_height_clamps_within_bounds() -> void:
	assert_almost_eq(BirdFlight.arc_height(0.0), BirdFlight.MIN_ARC_HEIGHT, 0.01)
	assert_almost_eq(BirdFlight.arc_height(2.0), BirdFlight.MIN_ARC_HEIGHT, 0.01)
	assert_gt(BirdFlight.arc_height(10.0), BirdFlight.MIN_ARC_HEIGHT)
	assert_almost_eq(BirdFlight.arc_height(100.0), BirdFlight.MAX_ARC_HEIGHT, 0.01)


func test_flight_position_endpoints_and_peak() -> void:
	var start := Vector3(0.0, 1.0, 0.0)
	var dest := Vector3(10.0, 1.0, 0.0)
	var arc := 2.0

	var at_start := BirdFlight.flight_position(start, dest, 0.0, arc)
	assert_almost_eq(at_start.x, 0.0, 0.001)
	assert_almost_eq(at_start.y, 1.0, 0.001)

	var at_mid := BirdFlight.flight_position(start, dest, 0.5, arc)
	assert_almost_eq(at_mid.x, 5.0, 0.001)
	assert_almost_eq(at_mid.y, 1.0 + arc, 0.001)

	var at_end := BirdFlight.flight_position(start, dest, 1.0, arc)
	assert_almost_eq(at_end.x, 10.0, 0.001)
	assert_almost_eq(at_end.y, 1.0, 0.001)


func test_flight_velocity_direction() -> void:
	var start := Vector3(0.0, 0.0, 0.0)
	var dest := Vector3(10.0, 0.0, 0.0)
	var arc := 2.0

	var vel_start := BirdFlight.flight_velocity(start, dest, 0.0, arc)
	assert_gt(vel_start.y, 0.0, "Climbing upward at takeoff")

	var vel_mid := BirdFlight.flight_velocity(start, dest, 0.5, arc)
	assert_almost_eq(vel_mid.y, 0.0, 0.001, "Level flight at arc apex")

	var vel_end := BirdFlight.flight_velocity(start, dest, 1.0, arc)
	assert_lt(vel_end.y, 0.0, "Descending toward landing")


func test_facing_angles_forward_and_pitch() -> void:
	var fwd := Vector3(0.0, 0.0, -5.0)
	var angles_fwd := BirdFlight.facing_angles(fwd)
	assert_almost_eq(angles_fwd.x, 0.0, 0.01, "Yaw is 0 for -Z forward vector")
	assert_almost_eq(angles_fwd.y, 0.0, 0.01, "Pitch is 0 for level flight")

	var right := Vector3(5.0, 0.0, 0.0)
	var angles_right := BirdFlight.facing_angles(right)
	assert_almost_eq(angles_right.x, -PI * 0.5, 0.01, "Yaw rotates -90 deg for +X vector")

	var climbing := Vector3(0.0, 5.0, -5.0)
	var angles_climb := BirdFlight.facing_angles(climbing)
	assert_gt(angles_climb.y, 0.0, "Positive pitch when climbing upward")


func test_wing_flapping_and_resting() -> void:
	var flapping_a := BirdFlight.wing_angle(0.1, true)
	var flapping_b := BirdFlight.wing_angle(0.2, true)
	assert_ne(flapping_a, flapping_b)
	assert_lt(absf(flapping_a), BirdFlight.FLAP_AMPLITUDE + 0.001)

	var resting := BirdFlight.wing_angle(0.5, false)
	assert_lt(absf(resting), 0.1, "Resting wing motion is very small")


func test_bank_angle_proportional_to_yaw_rate() -> void:
	var bank_none := BirdFlight.bank_angle(0.0, 0.1)
	assert_almost_eq(bank_none, 0.0, 0.001)

	var bank_left := BirdFlight.bank_angle(0.5, 0.1)
	assert_lt(bank_left, 0.0, "Banks into turn")

	var bank_right := BirdFlight.bank_angle(-0.5, 0.1)
	assert_gt(bank_right, 0.0, "Banks opposite into opposite turn")


func test_perch_offset_scales_for_tall_vs_small_targets() -> void:
	var tall := Node3D.new()
	var small := Node3D.new()
	small.add_to_group(&"frogs")
	autofree(tall)
	autofree(small)

	var offset_tall := BirdFlight.perch_offset(tall, 0.0)
	var offset_small := BirdFlight.perch_offset(small, 0.0)

	assert_gt(offset_tall.y, offset_small.y, "Higher perch on humanoid than frog")


func test_select_next_target_from_player_picks_npc_or_other_player() -> void:
	var p1 := Node3D.new()
	var p2 := Node3D.new()
	var npc1 := Node3D.new()
	var npc2 := Node3D.new()
	autofree(p1)
	autofree(p2)
	autofree(npc1)
	autofree(npc2)

	var players: Array[Node3D] = [p1, p2]
	var npcs: Array[Node3D] = [npc1, npc2]

	# From p1, candidates are [p2, npc1, npc2]
	var picked_a := BirdFlight.select_next_target(p1, players, npcs, 0.0)
	var picked_b := BirdFlight.select_next_target(p1, players, npcs, 0.4)
	var picked_c := BirdFlight.select_next_target(p1, players, npcs, 0.8)

	assert_ne(picked_a, p1, "Never picks current player if others exist")
	assert_ne(picked_b, p1)
	assert_ne(picked_c, p1)

	var valid_pool: Array[Node3D] = [p2, npc1, npc2]
	assert_true(valid_pool.has(picked_a))
	assert_true(valid_pool.has(picked_b))
	assert_true(valid_pool.has(picked_c))


func test_select_next_target_from_npc_picks_player_or_other_npc() -> void:
	var p1 := Node3D.new()
	var npc1 := Node3D.new()
	var npc2 := Node3D.new()
	autofree(p1)
	autofree(npc1)
	autofree(npc2)

	var players: Array[Node3D] = [p1]
	var npcs: Array[Node3D] = [npc1, npc2]

	# From npc1, candidates are [p1, npc2]
	var picked_1 := BirdFlight.select_next_target(npc1, players, npcs, 0.1)
	var picked_2 := BirdFlight.select_next_target(npc1, players, npcs, 0.9)

	assert_ne(picked_1, npc1, "Never picks same NPC")
	assert_ne(picked_2, npc1)
	var valid_pool: Array[Node3D] = [p1, npc2]
	assert_true(valid_pool.has(picked_1))
	assert_true(valid_pool.has(picked_2))


func test_select_next_target_with_no_current_target_prefers_active_player() -> void:
	var p1 := Node3D.new()
	var npc1 := Node3D.new()
	autofree(p1)
	autofree(npc1)

	var picked := BirdFlight.select_next_target(null, [p1], [npc1], 0.5)
	assert_eq(picked, p1, "Initial target is active player")
