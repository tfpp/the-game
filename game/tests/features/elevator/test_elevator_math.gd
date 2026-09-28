extends GutTest
## Pure math for the elevator cabs (features/elevator/elevator_math.gd).


func test_relative_offset_is_zero_at_the_cab_origin() -> void:
	var cab := Transform3D(Basis.IDENTITY, Vector3(5, 0, 10))
	var offset := ElevatorMath.relative_offset(Vector3(5, 0, 10), cab)
	assert_true(offset.is_equal_approx(Vector3.ZERO))


func test_relative_offset_and_apply_offset_round_trip() -> void:
	var cab := Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), Vector3(-4, 1, 8))
	var world_pos := Vector3(-2.5, 1, 9.5)
	var offset := ElevatorMath.relative_offset(world_pos, cab)
	var back := ElevatorMath.apply_offset(offset, cab)
	assert_true(back.is_equal_approx(world_pos))


func test_apply_offset_preserves_relative_arrangement_across_rotated_cabs() -> void:
	var origin_cab := Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(30, 0, 29))
	var destination_cab := Transform3D(Basis.IDENTITY, Vector3(0, 0, 300))
	# Two occupants standing 1m apart inside the origin cab.
	var player_a := origin_cab * Vector3(0.3, 0, 0.2)
	var player_b := origin_cab * Vector3(-0.3, 0, 0.2)

	var offset_a := ElevatorMath.relative_offset(player_a, origin_cab)
	var offset_b := ElevatorMath.relative_offset(player_b, origin_cab)
	var arrival_a := ElevatorMath.apply_offset(offset_a, destination_cab)
	var arrival_b := ElevatorMath.apply_offset(offset_b, destination_cab)

	# The gap between the two players is unchanged by the trip, despite the cabs
	# facing different directions in the world.
	assert_almost_eq(arrival_a.distance_to(arrival_b), player_a.distance_to(player_b), 0.0001)
	# And each of them lands exactly where their local offset places them on arrival.
	assert_true(arrival_a.is_equal_approx(destination_cab * Vector3(0.3, 0, 0.2)))
	assert_true(arrival_b.is_equal_approx(destination_cab * Vector3(-0.3, 0, 0.2)))


func test_is_inside_accepts_the_footprint_and_rejects_outside_it() -> void:
	assert_true(ElevatorMath.is_inside(Vector3(0.5, 0.9, -0.5), 1.0, 1.0, 2.3))
	assert_false(ElevatorMath.is_inside(Vector3(1.5, 0.9, 0.0), 1.0, 1.0, 2.3))
	assert_false(ElevatorMath.is_inside(Vector3(0.0, 3.0, 0.0), 1.0, 1.0, 2.3))


func test_is_inside_allows_a_little_slack_below_the_floor() -> void:
	assert_true(ElevatorMath.is_inside(Vector3(0.0, -0.1, 0.0), 1.0, 1.0, 2.3))
	assert_false(ElevatorMath.is_inside(Vector3(0.0, -0.5, 0.0), 1.0, 1.0, 2.3))


func test_door_fraction_opening_goes_from_zero_to_one() -> void:
	assert_eq(ElevatorMath.door_fraction(0.0, 1.1, true), 0.0)
	assert_almost_eq(ElevatorMath.door_fraction(0.55, 1.1, true), 0.5, 0.0001)
	assert_eq(ElevatorMath.door_fraction(5.0, 1.1, true), 1.0)


func test_door_fraction_closing_goes_from_one_to_zero() -> void:
	assert_eq(ElevatorMath.door_fraction(0.0, 1.1, false), 1.0)
	assert_almost_eq(ElevatorMath.door_fraction(0.55, 1.1, false), 0.5, 0.0001)
	assert_eq(ElevatorMath.door_fraction(5.0, 1.1, false), 0.0)


func test_door_leaf_offset_scales_linearly_with_max_offset() -> void:
	assert_almost_eq(ElevatorMath.door_leaf_offset(0.5, 1.0), 0.5, 0.0001)
	assert_eq(ElevatorMath.door_leaf_offset(0.0, 1.0), 0.0)
	assert_eq(ElevatorMath.door_leaf_offset(1.0, 1.0), 1.0)
