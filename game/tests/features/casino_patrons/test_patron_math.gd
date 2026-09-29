extends GutTest
## Pure rules of features/casino_patrons: facing, route stepping and personal space.


func test_facing_yaw_points_the_minus_z_model_along_the_heading() -> void:
	for heading: Vector3 in [
		Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3(1, 0, 1).normalized()
	]:
		var forward := Basis(Vector3.UP, PatronMath.facing_yaw(heading)) * Vector3.FORWARD
		assert_almost_eq(forward.distance_to(heading), 0.0, 0.001, "faces %s" % heading)


func test_waypoints_loop_around() -> void:
	assert_eq(PatronMath.next_waypoint(0, 4), 1)
	assert_eq(PatronMath.next_waypoint(3, 4), 0)
	assert_eq(PatronMath.next_waypoint(1, 2), 0)


func test_only_a_close_player_ahead_is_in_the_way() -> void:
	var at := Vector3(0, -1.5, 0)
	assert_true(PatronMath.is_in_the_way(at, Vector3.FORWARD, Vector3(0, 0, -0.6)))
	assert_false(PatronMath.is_in_the_way(at, Vector3.FORWARD, Vector3(0, 0, 0.6)), "behind")
	assert_false(PatronMath.is_in_the_way(at, Vector3.FORWARD, Vector3(0, 0, -2.0)), "far")


func test_every_route_is_on_the_gaming_floor_and_routes_differ() -> void:
	var starts: Array[Vector3] = []
	for index: int in PatronMath.ROUTES.size():
		var points := PatronMath.route(index)
		assert_gte(points.size(), 2)
		for point: Vector3 in points:
			assert_eq(point.y, PatronMath.FLOOR_Y)
		for other: Vector3 in starts:
			assert_gt(other.distance_to(points[0]), 3.0, "patrons start apart")
		starts.append(points[0])
