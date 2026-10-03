extends GutTest

const Room := preload("res://features/feng_shui/room_harmony.gd")
const FLOOR := Rect2(0, 0, 10, 10)
const ENTRY := Vector2(5, 0)
const BALANCED: Array[float] = [1, 1, 1, 1, 1]


class CountingRoom:
	extends FengShuiRoom
	var computations := 0

	func _compute_evaluation() -> Dictionary:
		computations += 1
		return super._compute_evaluation()


func _room(footprints: Array[Rect2], elements: PackedFloat64Array = BALANCED) -> FengShuiRoom:
	var room := Room.new()
	assert_true(room.set_layout(FLOOR, ENTRY, footprints, elements))
	return room


func test_empty_balanced_room_scores_one_hundred() -> void:
	var room := _room([])
	assert_eq(room.score(), 100.0)
	assert_true(room.evaluation()["valid"])


func test_element_balance_and_unknown_elements() -> void:
	assert_eq(_room([], PackedFloat64Array([1, 0, 0, 0, 0])).score(), 75.0)
	assert_eq(_room([], PackedFloat64Array([0, 0, 0, 0, 0])).score(), 87.5)
	assert_eq(_room([], PackedFloat64Array([10, 10, 10, 10, 10])).score(), 100.0)
	var mixed := _room([], PackedFloat64Array([3, 1, 1, 1, 1]))
	assert_between(mixed.score(), 75.0, 100.0)


func test_clutter_reduces_score_and_filled_room_scores_zero() -> void:
	var room := _room([FLOOR], PackedFloat64Array([1, 0, 0, 0, 0]))
	assert_almost_eq(room.score(), 0.0, 0.00001)
	assert_eq(room.evaluation()["components"]["space"], 0.0)


func test_overlaps_count_once_and_outside_objects_are_clipped() -> void:
	var first := Rect2(0, 7, 4, 3)
	var second := Rect2(2, 7, 4, 3)
	var room := _room([first, first, second, Rect2(20, 20, 2, 2)])
	assert_almost_eq(room.evaluation()["components"]["space"], 0.82, 0.00001)
	var clipped := _room([Rect2(-2, 7, 6, 6)])
	assert_almost_eq(clipped.evaluation()["components"]["space"], 0.88, 0.00001)


func test_centre_is_better_left_open() -> void:
	var central := _room([Rect2(4, 4, 2, 2)])
	var wall := _room([Rect2(0, 4, 2, 2)])
	assert_eq(central.evaluation()["components"]["centre"], 0.0)
	assert_eq(wall.evaluation()["components"]["centre"], 1.0)
	assert_almost_eq(wall.score() - central.score(), 25.0, 0.00001)


func test_entrance_has_one_metre_clearance_gradient() -> void:
	var blocked := _room([Rect2(4, 0, 2, 1)])
	var near := _room([Rect2(4, 0.5, 2, 1)])
	var clear_entry := _room([Rect2(4, 1, 2, 1)])
	assert_eq(blocked.evaluation()["components"]["entrance"], 0.0)
	assert_eq(near.evaluation()["components"]["entrance"], 0.5)
	assert_eq(clear_entry.evaluation()["components"]["entrance"], 1.0)


func test_setup_and_replacement_are_lazy_and_queries_are_cached() -> void:
	var room := CountingRoom.new()
	assert_false(room.evaluation()["valid"])
	assert_eq(room.computations, 0)
	assert_true(room.set_layout(FLOOR, ENTRY, [], BALANCED))
	assert_true(room.set_layout(FLOOR, ENTRY, [FLOOR], BALANCED))
	assert_eq(room.computations, 0)
	assert_eq(room.score(), 25.0)
	room.evaluation()
	room.score()
	assert_eq(room.computations, 1)
	assert_true(room.set_layout(FLOOR, ENTRY, [], BALANCED))
	assert_eq(room.computations, 1)
	assert_eq(room.score(), 100.0)
	assert_eq(room.computations, 2)
	room.clear()
	assert_false(room.evaluation()["valid"])
	assert_eq(room.score(), 0.0)
	assert_eq(room.computations, 2)


func test_layout_and_returned_results_are_defensive_copies() -> void:
	var room := Room.new()
	var footprints: Array[Rect2] = [Rect2(0, 7, 4, 3)]
	var elements := PackedFloat64Array(BALANCED)
	assert_true(room.set_layout(FLOOR, ENTRY, footprints, elements))
	footprints[0] = FLOOR
	elements[0] = 999.0
	assert_almost_eq(room.score(), 97.0, 0.00001)
	var result := room.evaluation()
	result["score"] = -100.0
	result["components"]["space"] = 0.0
	assert_almost_eq(room.score(), 97.0, 0.00001)
	assert_almost_eq(room.evaluation()["components"]["space"], 0.88, 0.00001)


func test_invalid_replacement_preserves_last_good_cache() -> void:
	var room := CountingRoom.new()
	assert_true(room.set_layout(FLOOR, ENTRY, [], BALANCED))
	assert_eq(room.score(), 100.0)
	for bad_floor: Rect2 in [Rect2(), Rect2(0, 0, -1, 10), Rect2(0, 0, INF, 10)]:
		assert_false(room.set_layout(bad_floor, ENTRY, [], BALANCED))
	for bad_entry: Vector2 in [Vector2(-1, 0), Vector2(0, NAN), Vector2(INF, 0)]:
		assert_false(room.set_layout(FLOOR, bad_entry, [], BALANCED))
	for weights: PackedFloat64Array in [
		PackedFloat64Array([1]),
		PackedFloat64Array([-1, 1, 1, 1, 1]),
		PackedFloat64Array([NAN, 1, 1, 1, 1]),
		PackedFloat64Array([INF, 1, 1, 1, 1]),
	]:
		assert_false(room.set_layout(FLOOR, ENTRY, [], weights))
	assert_false(room.set_layout(FLOOR, ENTRY, [Rect2(0, 0, 0, 1)], BALANCED))
	var too_many: Array[Rect2] = []
	too_many.resize(Room.MAX_FOOTPRINTS + 1)
	too_many.fill(FLOOR)
	assert_false(room.set_layout(FLOOR, ENTRY, too_many, BALANCED))
	assert_eq(room.score(), 100.0)
	assert_eq(room.computations, 1)


func test_all_entrance_edges_are_supported() -> void:
	for entrance: Vector2 in [Vector2(0, 5), Vector2(10, 5), Vector2(5, 0), Vector2(5, 10)]:
		var room := Room.new()
		assert_true(room.set_layout(FLOOR, entrance, [], BALANCED))
		assert_eq(room.score(), 100.0)


func test_scores_are_order_independent_and_room_local() -> void:
	var footprints: Array[Rect2] = [Rect2(0, 7, 4, 3), Rect2(2, 7, 4, 3)]
	var score_before := _room(footprints).score()
	footprints.reverse()
	assert_eq(_room(footprints).score(), score_before)
	var offset := Vector2(-34, 600)
	var translated: Array[Rect2] = []
	for rect: Rect2 in footprints:
		translated.append(Rect2(rect.position + offset, rect.size))
	var room := Room.new()
	assert_true(room.set_layout(Rect2(offset, FLOOR.size), ENTRY + offset, translated, BALANCED))
	assert_eq(room.score(), score_before)


func test_crossing_rectangles_and_touching_edges_have_exact_union() -> void:
	var crossed := _room([Rect2(1, 4, 8, 2), Rect2(4, 1, 2, 8)])
	assert_almost_eq(crossed.evaluation()["components"]["space"], 0.72, 0.00001)
	var touching := _room([Rect2(0, 7, 2, 3), Rect2(2, 7, 2, 3)])
	assert_almost_eq(touching.evaluation()["components"]["space"], 0.88, 0.00001)


func test_bounded_maximum_layout_stays_finite_and_deterministic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 480
	var footprints: Array[Rect2] = []
	for index: int in Room.MAX_FOOTPRINTS:
		footprints.append(Rect2(rng.randf_range(-2, 10), rng.randf_range(-2, 10), 2, 2))
	var room := _room(footprints)
	assert_between(room.score(), 0.0, 100.0)
	footprints.reverse()
	assert_almost_eq(_room(footprints).score(), room.score(), 0.00001)


func test_separate_rooms_have_no_shared_cache_or_layout() -> void:
	var first := _room([])
	var second := _room([FLOOR])
	assert_eq(first.score(), 100.0)
	assert_eq(second.score(), 25.0)
	first.clear()
	assert_false(first.evaluation()["valid"])
	assert_eq(second.score(), 25.0)


func test_streamed_room_can_be_scored_without_loading_content() -> void:
	var anchor := StreamedRoom.new()
	anchor.position = Vector3(80, 0, -600)
	var bounds := anchor.bounds
	var floor_rect := Rect2(
		Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)
	)
	var room := Room.new()
	assert_true(room.set_layout(floor_rect, Vector2(0, bounds.position.z), [], BALANCED))
	assert_eq(room.score(), 100.0)
	assert_false(anchor.is_loaded())
	assert_eq(anchor.get_child_count(), 0)
	anchor.free()
