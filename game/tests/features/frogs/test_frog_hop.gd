extends GutTest
## Pure hop math for the frogs feature (features/frogs/frog_hop.gd).

const FrogHop := preload("res://features/frogs/frog_hop.gd")


func test_arc_position_starts_and_ends_on_the_straight_line() -> void:
	var from := Vector3(0, 0, 0)
	var to := Vector3(2, 0, 0)
	assert_eq(FrogHop.arc_position(from, to, 0.0, 0.5), from)
	assert_true(FrogHop.arc_position(from, to, 1.0, 0.5).is_equal_approx(to))


func test_arc_position_peaks_at_the_midpoint() -> void:
	var pos := FrogHop.arc_position(Vector3.ZERO, Vector3(2, 0, 0), 0.5, 0.5)
	assert_almost_eq(pos.y, 0.5, 0.0001)
	assert_almost_eq(pos.x, 1.0, 0.0001)


func test_arc_position_clamps_t_outside_zero_one() -> void:
	var from := Vector3(1, 0, 1)
	var to := Vector3(3, 0, 5)
	assert_eq(FrogHop.arc_position(from, to, -1.0, 0.5), from)
	assert_true(FrogHop.arc_position(from, to, 2.0, 0.5).is_equal_approx(to))


func test_pick_target_stays_at_the_requested_radius_from_home() -> void:
	var home := Vector3(5, 0, -3)
	for i: int in 12:
		var angle := TAU * i / 12.0
		var target := FrogHop.pick_target(home, 2.5, angle, 1.0)
		assert_almost_eq(home.distance_to(target), 2.5, 0.001)
		assert_almost_eq(target.y, home.y, 0.0001)


func test_pick_target_distance_fraction_scales_the_radius() -> void:
	var target := FrogHop.pick_target(Vector3.ZERO, 4.0, 0.0, 0.5)
	assert_almost_eq(Vector3.ZERO.distance_to(target), 2.0, 0.0001)


func test_facing_yaw_matches_source_movements_forward_convention() -> void:
	var yaw := FrogHop.facing_yaw(Vector3.ZERO, Vector3(3, 0, 0))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	assert_almost_eq(forward.x, 1.0, 0.0001)
	assert_almost_eq(forward.z, 0.0, 0.0001)


func test_facing_yaw_of_no_movement_is_zero() -> void:
	assert_eq(FrogHop.facing_yaw(Vector3(1, 0, 1), Vector3(1, 0, 1)), 0.0)


func test_color_for_index_cycles_through_a_distinct_palette() -> void:
	var seen: Array[Color] = []
	for i: int in FrogHop.PALETTE.size():
		var color := FrogHop.color_for_index(i)
		assert_false(seen.has(color), "Palette colors should be distinct")
		seen.append(color)
	assert_eq(FrogHop.color_for_index(FrogHop.PALETTE.size()), FrogHop.PALETTE[0])
