extends GutTest
## Pure train math for the gnomes feature (features/gnomes/gnome_math.gd).

const GnomeMath := preload("res://features/gnomes/gnome_math.gd")


func test_total_distance_adds_spacing_for_every_follower() -> void:
	assert_almost_eq(GnomeMath.total_distance(5.0, 4, 0.4), 6.2, 0.0001)
	assert_almost_eq(GnomeMath.total_distance(5.0, 1, 0.4), 5.0, 0.0001)


func test_total_distance_ignores_a_degenerate_count() -> void:
	assert_almost_eq(GnomeMath.total_distance(5.0, 0, 0.4), 5.0, 0.0001)


func test_leg_duration_divides_distance_by_speed() -> void:
	assert_almost_eq(GnomeMath.leg_duration(10.0, 5.0), 2.0, 0.0001)


func test_leg_duration_is_zero_for_a_degenerate_speed() -> void:
	assert_eq(GnomeMath.leg_duration(10.0, 0.0), 0.0)
	assert_eq(GnomeMath.leg_duration(10.0, -1.0), 0.0)


func test_advance_progress_moves_by_the_fraction_of_the_leg_covered() -> void:
	assert_almost_eq(GnomeMath.advance_progress(0.0, 1.0, 4.0), 0.25, 0.0001)


func test_advance_progress_clamps_to_zero_and_one() -> void:
	assert_eq(GnomeMath.advance_progress(0.0, -1.0, 4.0), 0.0)
	assert_eq(GnomeMath.advance_progress(0.9, 1.0, 4.0), 1.0)


func test_advance_progress_finishes_immediately_for_a_degenerate_duration() -> void:
	assert_eq(GnomeMath.advance_progress(0.0, 0.5, 0.0), 1.0)


func test_follower_distance_matches_the_leader_at_index_zero() -> void:
	assert_almost_eq(GnomeMath.follower_distance(0.5, 6.2, 5.0, 0, 0.4), 3.1, 0.0001)


func test_follower_distance_trails_by_index_times_spacing() -> void:
	var leader := GnomeMath.follower_distance(0.5, 6.2, 5.0, 0, 0.4)
	var second := GnomeMath.follower_distance(0.5, 6.2, 5.0, 1, 0.4)
	assert_almost_eq(leader - second, 0.4, 0.0001)


func test_follower_distance_clamps_to_the_tunnel() -> void:
	assert_eq(GnomeMath.follower_distance(0.0, 6.2, 5.0, 3, 0.4), 0.0)
	assert_eq(GnomeMath.follower_distance(1.0, 6.2, 5.0, 0, 0.4), 5.0)


func test_gnome_visible_only_strictly_between_the_holes() -> void:
	assert_false(GnomeMath.gnome_visible(0.0, 5.0))
	assert_false(GnomeMath.gnome_visible(5.0, 5.0))
	assert_true(GnomeMath.gnome_visible(2.5, 5.0))
