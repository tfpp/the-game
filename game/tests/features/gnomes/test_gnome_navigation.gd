extends GutTest
## Multi-hole routing and player-avoidance math for the gnomes feature
## (features/gnomes/gnome_math.gd).

const GnomeMath := preload("res://features/gnomes/gnome_math.gd")


func test_next_hole_index_never_repeats_the_current_hole() -> void:
	for rng_step in range(10):
		var rng := rng_step / 10.0
		for current in range(3):
			assert_ne(GnomeMath.next_hole_index(current, 3, rng), current)


func test_next_hole_index_stays_within_range() -> void:
	for rng_step in range(10):
		var rng := rng_step / 10.0
		var next := GnomeMath.next_hole_index(1, 4, rng)
		assert_true(next >= 0 and next < 4)


func test_next_hole_index_is_unchanged_with_only_one_hole() -> void:
	assert_eq(GnomeMath.next_hole_index(0, 1, 0.7), 0)


func test_leg_speed_spans_the_jitter_range() -> void:
	assert_almost_eq(GnomeMath.leg_speed(10.0, 0.0), 8.0, 0.0001)
	assert_almost_eq(GnomeMath.leg_speed(10.0, 1.0), 12.0, 0.0001)
	assert_almost_eq(GnomeMath.leg_speed(10.0, 0.5), 10.0, 0.0001)


func test_avoidance_offset_is_zero_with_no_nearby_players() -> void:
	var offset := GnomeMath.avoidance_offset(Vector3.ZERO, Vector3.FORWARD, [Vector3(0, 0, -50)])
	assert_true(offset.is_equal_approx(Vector3.ZERO))


func test_avoidance_offset_pushes_perpendicular_to_travel() -> void:
	var offset := GnomeMath.avoidance_offset(Vector3.ZERO, Vector3(0, 0, -1), [Vector3(1, 0, 0)])
	assert_almost_eq(offset.y, 0.0, 0.0001)
	assert_true(absf(offset.z) < 0.0001)
	assert_true(offset.x < 0.0)


func test_avoidance_offset_grows_stronger_when_closer() -> void:
	var far := GnomeMath.avoidance_offset(Vector3.ZERO, Vector3(0, 0, -1), [Vector3(2.5, 0, 0)])
	var near := GnomeMath.avoidance_offset(Vector3.ZERO, Vector3(0, 0, -1), [Vector3(0.5, 0, 0)])
	assert_true(near.length() > far.length())


func test_avoidance_offset_clamps_multiple_players_to_the_max() -> void:
	var offset := GnomeMath.avoidance_offset(
		Vector3.ZERO, Vector3(0, 0, -1), [Vector3(0.2, 0, 0), Vector3(0.3, 0, 0)]
	)
	assert_true(offset.length() <= GnomeMath.AVOID_MAX_OFFSET + 0.0001)
