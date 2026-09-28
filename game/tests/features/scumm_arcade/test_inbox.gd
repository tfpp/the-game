extends GutTest


func test_pushes_queue_while_worker_is_busy_and_replay_stops_at_checksum() -> void:
	var inbox := ScummArcadeInbox.new()
	var frames: Array = []
	frames.resize(240)
	frames.fill([])
	assert_true(inbox.append(0, frames))
	assert_eq(inbox.take(0).size(), 240)
	frames.resize(30)
	assert_true(inbox.append(240, frames))
	assert_eq(inbox.take(240).size(), 10)
	assert_eq(inbox.take(250).size(), 20)
	assert_eq(inbox.next_tick, 270)


func test_retries_trim_duplicates_reject_gaps_and_bound_memory() -> void:
	var inbox := ScummArcadeInbox.new()
	assert_true(inbox.append(0, [[], [], []]))
	assert_true(inbox.append(1, [[], [], [[0, 20, 30, 0]]]))
	assert_eq(inbox.next_tick, 4)
	assert_false(inbox.append(5, [[]]))
	assert_eq(inbox.next_tick, 4)
	var huge: Array = []
	huge.resize(501)
	assert_false(inbox.append(4, huge))
	assert_eq(inbox.frames.size(), 4)
	assert_eq(inbox.take(0).back(), [[0, 20, 30, 0]])


func test_room_bounds_exclude_casino_and_outside_walls() -> void:
	assert_true(ScummArcadeRoom.contains(ScummArcadeRoom.ARRIVAL))
	assert_true(ScummArcadeRoom.contains(Vector3(-85.4, 0.9144, -0.9)))
	assert_false(ScummArcadeRoom.contains(ScummArcadeRoom.ENTRANCE))
	assert_false(ScummArcadeRoom.contains(Vector3(-80, 8, 0)))
	assert_false(ScummArcadeRoom.contains(Vector3(-90, 1, 0)))
