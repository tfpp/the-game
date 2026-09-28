extends GutTest
## Path-following, hole-choice and player-avoidance math for the gnomes feature
## (features/gnomes/gnome_math.gd).

const GnomeMath := preload("res://features/gnomes/gnome_math.gd")


func test_next_hole_index_never_repeats_the_current_hole() -> void:
	var holes: Array[Vector3] = [Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(0, 0, 5)]
	for rng_step in range(10):
		var rng := rng_step / 10.0
		for current in range(3):
			assert_ne(GnomeMath.next_hole_index(current, holes, rng), current)


func test_next_hole_index_stays_within_range() -> void:
	var holes: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(0, 0, 5), Vector3(-5, 0, -5)
	]
	for rng_step in range(10):
		var rng := rng_step / 10.0
		var next := GnomeMath.next_hole_index(1, holes, rng)
		assert_true(next >= 0 and next < 4)


func test_next_hole_index_is_unchanged_with_only_one_hole() -> void:
	assert_eq(GnomeMath.next_hole_index(0, [Vector3.ZERO], 0.7), 0)


func test_next_hole_index_favors_the_farther_hole() -> void:
	# From the origin, hole 1 is far away and hole 2 is close; a low rng roll should
	# still land on the close hole (it keeps a nonzero share) but a high roll should
	# almost always land on the far one, since weight scales with squared distance.
	var holes: Array[Vector3] = [Vector3(0, 0, 0), Vector3(20, 0, 0), Vector3(1, 0, 0)]
	var far_count := 0
	var samples := 200
	for i in samples:
		if GnomeMath.next_hole_index(0, holes, i / float(samples)) == 1:
			far_count += 1
	assert_true(far_count > samples * 0.9)


func test_path_total_length_sums_segments() -> void:
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 4)])
	assert_almost_eq(GnomeMath.path_total_length(path), 7.0, 0.0001)


func test_position_on_path_walks_segments() -> void:
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 4)])
	assert_true(GnomeMath.position_on_path(path, 0.0).is_equal_approx(Vector3(0, 0, 0)))
	assert_true(GnomeMath.position_on_path(path, 3.0).is_equal_approx(Vector3(3, 0, 0)))
	assert_true(GnomeMath.position_on_path(path, 5.0).is_equal_approx(Vector3(3, 0, 2)))
	assert_true(GnomeMath.position_on_path(path, 100.0).is_equal_approx(Vector3(3, 0, 4)))


func test_direction_on_path_matches_the_current_segment() -> void:
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 4)])
	assert_true(GnomeMath.direction_on_path(path, 1.0).is_equal_approx(Vector3(1, 0, 0)))
	assert_true(GnomeMath.direction_on_path(path, 4.0).is_equal_approx(Vector3(0, 0, 1)))


func test_facing_yaw_of_zero_direction_is_zero() -> void:
	assert_almost_eq(GnomeMath.facing_yaw(Vector3.ZERO), 0.0, 0.0001)


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
