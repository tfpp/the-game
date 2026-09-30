extends GutTest

const Capture := preload("res://features/profiler/frame_capture.gd")


func test_disabled_and_first_boundary_do_not_record_a_frame() -> void:
	var capture := Capture.new()
	capture.boundary(1000, 1)
	capture.mark("ignored", 1500)
	assert_true(capture.frames.is_empty())
	capture.enabled = true
	capture.boundary(10000, 2)
	assert_true(capture.frames.is_empty())
	capture.boundary(20000, 3)
	assert_eq(capture.frames[0]["id"], 2)
	assert_eq(capture.frames[0]["duration_ms"], 10.0)


func test_exact_budget_is_not_a_miss_and_traces_are_captured_not_live() -> void:
	var capture := Capture.new()
	capture.enabled = true
	capture.budget_ms = 10.0
	capture.boundary(1000, 10)
	capture.mark("Physics tick begins", 4000)
	capture.boundary(11000, 11)
	assert_true(capture.misses.is_empty())
	capture.mark("RenderingServer pre-draw", 13000)
	capture.mark("RenderingServer post-draw", 14000)
	capture.boundary(22000, 12)
	assert_eq(capture.misses.size(), 1)
	var frame: Dictionary = capture.misses[0]
	assert_eq(frame["id"], 11)
	assert_eq(frame["budget_ms"], 10.0)
	assert_eq(frame["events"][1]["offset_ms"], 2.0)
	capture.mark("later frame", 23000)
	capture.budget_ms = 20.0
	assert_eq(frame["events"].size(), 3)
	assert_eq(frame["budget_ms"], 10.0)
	var text := Capture.trace_text(frame)
	assert_string_contains(text, "RenderingServer pre-draw")
	assert_string_contains(text, "Next process frame boundary")
	assert_string_contains(text, "Not script call stacks")


func test_retention_and_event_work_are_bounded() -> void:
	var capture := Capture.new()
	capture.enabled = true
	capture.budget_ms = 1.0
	for frame: int in range(301):
		capture.boundary(frame * 2000, frame)
	assert_eq(capture.frames.size(), Capture.GRAPH_LIMIT)
	assert_eq(capture.misses.size(), Capture.MISS_LIMIT)
	assert_eq(capture.total_misses, 300)
	assert_eq(capture.misses[0]["id"], 180)
	for index: int in range(200):
		capture.mark("tick", 600000 + index)
	capture.boundary(602000, 301)
	assert_eq(capture.misses[-1]["events"].size(), Capture.EVENT_LIMIT)
	assert_gt(capture.misses[-1]["dropped"], 0)


func test_restart_excludes_disabled_time_and_clear_resets_everything() -> void:
	var capture := Capture.new()
	capture.enabled = true
	capture.boundary(1000, 1)
	capture.boundary(21000, 2)
	capture.enabled = false
	capture.boundary(1000000, 3)
	capture.mark("ignored", 1000010)
	capture.restart_interval()
	capture.enabled = true
	capture.boundary(2000000, 4)
	assert_eq(capture.frames.size(), 1)
	capture.boundary(2002000, 5)
	assert_eq(capture.frames[-1]["duration_ms"], 2.0)
	capture.reset()
	assert_true(capture.frames.is_empty())
	assert_true(capture.misses.is_empty())
	assert_eq(capture.total_misses, 0)
	assert_true(capture.enabled)


func test_invalid_landmark_and_nonpositive_intervals_are_ignored() -> void:
	var capture := Capture.new()
	capture.enabled = true
	capture.mark("before first boundary", 100)
	capture.boundary(1000, 1)
	capture.mark("before interval", 999)
	capture.boundary(1000, 2)
	assert_true(capture.frames.is_empty())
	assert_eq(capture._events.size(), 1)
