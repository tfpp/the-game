extends GutTest

const LOUNGE := AABB(Vector3(-5, -1, -604), Vector3(10, 5, 8))
const CELLAR := AABB(Vector3(36, -1, -604), Vector3(8, 4.6, 8))


func _links() -> Array[Dictionary]:
	return [
		{"from": Vector3(-6, 1, 32), "to": Vector3(-2, 1, -597), "label": "Enter the lounge"},
		{"from": Vector3(-2, 1, -596), "to": Vector3(-6, 1, 30), "label": "Back to the casino"},
		{"from": Vector3(2, 1, -603.9), "to": Vector3(40, 1, -597), "label": "Enter the cellar"},
		{"from": Vector3(40, 1, -596), "to": Vector3(2, 1, -603), "label": "Back to the lounge"},
	]


func test_region_prefers_the_smallest_containing_area() -> void:
	var big := AABB(Vector3(-100, -10, -100), Vector3(200, 20, 200))
	var regions: Array[AABB] = [big, LOUNGE]
	assert_eq(GpsRoute.region_of(regions, Vector3(0, 0, 0)), 0)
	assert_eq(GpsRoute.region_of(regions, Vector3(0, 0, -600)), 1)
	assert_eq(GpsRoute.region_of(regions, Vector3(0, 0, 600)), -1)
	regions = [LOUNGE, CELLAR]
	assert_eq(GpsRoute.region_of(regions, Vector3(0, 0, -600)), 0)
	assert_eq(GpsRoute.region_of(regions, Vector3(40, 0, -600)), 1)


func test_routes_through_a_chain_of_doors() -> void:
	var regions: Array[AABB] = [LOUNGE, CELLAR]
	var casino := Vector3(0, 0, 0)
	var cellar := Vector3(40, 0, -599)
	var hop := GpsRoute.next_hop(regions, _links(), casino, cellar)
	assert_eq(hop["door"], "Enter the lounge", "First leave the casino through the booth")
	assert_eq(hop["position"], Vector3(-6, 1, 32))
	hop = GpsRoute.next_hop(regions, _links(), Vector3(0, 0, -600), cellar)
	assert_eq(hop["door"], "Enter the cellar")
	hop = GpsRoute.next_hop(regions, _links(), Vector3(40, 0, -600), casino)
	assert_eq(hop["door"], "Back to the lounge", "Routes work in reverse too")
	hop = GpsRoute.next_hop(regions, _links(), Vector3(39, 0, -600), cellar)
	assert_eq(hop["door"], "", "Same room walks straight there")
	assert_eq(hop["position"], cellar)


func test_unreachable_region_falls_back_to_a_straight_line() -> void:
	var regions: Array[AABB] = [LOUNGE, CELLAR]
	var no_links: Array[Dictionary] = []
	var hop := GpsRoute.next_hop(regions, no_links, Vector3.ZERO, Vector3(40, 0, -599))
	assert_eq(hop["door"], "")


func test_grid_path_goes_around_a_wall_through_its_gap() -> void:
	# A wall along z = 0 from x = -20 to 3, open to the east of x = 3.
	var walls := PackedVector2Array([Vector2(-20, 0), Vector2(3, 0)])
	var path := GpsRoute.grid_path(walls, Vector2(0, 5), Vector2(0, -5))
	assert_gt(path.size(), 2, "Needs at least one corner")
	assert_eq(path[0], Vector2(0, 5))
	assert_almost_eq(path[path.size() - 1].distance_to(Vector2(0, -5)), 0.0, 0.5)
	for index: int in range(1, path.size()):
		var crossing: Variant = Geometry2D.segment_intersects_segment(
			path[index - 1], path[index], walls[0], walls[1]
		)
		assert_null(crossing, "Leg %d must not cross the wall" % index)
	assert_gt(GpsRoute.length(path), 10.0)


func test_open_ground_is_a_straight_line() -> void:
	var path := GpsRoute.grid_path(PackedVector2Array(), Vector2.ZERO, Vector2(8, -6))
	assert_eq(path.size(), 2)
	assert_almost_eq(GpsRoute.length(path), 10.0, 0.5)


func test_far_goal_ends_with_a_straight_leg_past_the_grid() -> void:
	var path := GpsRoute.grid_path(PackedVector2Array(), Vector2.ZERO, Vector2(0, -500))
	assert_eq(path[path.size() - 1], Vector2(0, -500))


func test_turn_direction_seen_from_above_with_north_up() -> void:
	var north := Vector2(0, -1)
	assert_eq(GpsRoute.turn(north, Vector2(1, 0)), "right", "North then east turns right")
	assert_eq(GpsRoute.turn(north, Vector2(-1, 0)), "left")
	assert_eq(GpsRoute.turn(north, Vector2(0.1, -1)), "straight")


func test_instructions() -> void:
	var corner := PackedVector2Array([Vector2(0, 0), Vector2(0, -12), Vector2(5, -12)])
	assert_eq(GpsRoute.instruction(corner, "", "Kaaba"), "Turn right in 12 m")
	var line := PackedVector2Array([Vector2(0, 0), Vector2(0, -20)])
	assert_eq(GpsRoute.instruction(line, "", "Kaaba"), "Continue to Kaaba, 20 m")
	assert_eq(
		GpsRoute.instruction(line, "Enter the lounge", "Wine Cellar"), "Enter the lounge in 20 m"
	)


func test_arrival_needs_the_same_storey() -> void:
	assert_true(GpsRoute.arrived(Vector3(1, 0.9, 1), Vector3(0, 0, 0)))
	assert_false(GpsRoute.arrived(Vector3(5, 0, 0), Vector3(0, 0, 0)))
	assert_false(GpsRoute.arrived(Vector3(0, -1.5, -10), Vector3(0, 3.2, -10)), "Under the gallery")
