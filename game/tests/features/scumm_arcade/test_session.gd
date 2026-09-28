extends GutTest


func test_inputs_are_validated_and_committed_to_immutable_ticks() -> void:
	var session := ScummArcadeSession.new()
	assert_false(session.enqueue([1, -1, 0, 0]))
	assert_false(session.enqueue([1, 320, 0, 0]))
	assert_false(session.enqueue([1, 0, 200, 0]))
	assert_false(session.enqueue([1.0, 0, 0, 0]))
	assert_false(session.enqueue([5, 0, 0, 282]), "F5 must not open an unsynced save menu")
	assert_false(session.enqueue([8, 0, 0, 0]))
	assert_true(session.enqueue([0, 10, 20, 0]))
	assert_true(session.enqueue([0, 12, 22, 0]))
	assert_true(session.enqueue([1, 12, 22, 0]))
	session.advance()
	session.advance()
	assert_eq(session.tick, 2)
	assert_eq(session.batch(0), [[[0, 12, 22, 0], [1, 12, 22, 0]], []])
	var copy := session.batch(0)
	copy[0][0][1] = 300
	assert_eq(session.batch(0)[0][0][1], 12)


func test_late_join_replay_matches_live_sequence_at_batch_boundaries() -> void:
	var session := ScummArcadeSession.new()
	var live: Array = []
	for tick: int in 613:
		if tick % 7 == 0:
			session.enqueue([0, tick % 320, tick % 200, 0])
		session.advance()
		live.append_array(session.batch(tick))
	var late: Array = []
	while late.size() < session.tick:
		late.append_array(session.batch(late.size()))
	assert_eq(late, live)
	assert_eq(session.batch(-1), [])
	assert_eq(session.batch(614), [])


func test_input_flood_is_bounded_and_release_clears_held_buttons() -> void:
	var session := ScummArcadeSession.new()
	for index: int in 50:
		session.enqueue([1, index, 20, 0])
	assert_eq(session.pending.size(), ScummArcadeSession.MAX_PER_TICK)
	session.release_buttons()
	session.advance()
	assert_eq(session.batch(0)[0][0][0], 2)
	assert_eq(session.batch(0)[0][1][0], 4)
	assert_eq(session.event_count, 5)


func test_session_stops_at_limit_without_evicting_replay_history() -> void:
	var session := ScummArcadeSession.new()
	session.tick = ScummArcadeSession.MAX_TICKS - 1
	assert_true(session.enqueue([1, 1, 1, 0]))
	session.advance()
	session.advance()
	assert_true(session.finished())
	assert_false(session.enqueue([1, 1, 1, 0]))
	assert_eq(session.tick, ScummArcadeSession.MAX_TICKS)
	assert_eq(session.batch(session.tick - 1), [[[1, 1, 1, 0]]])
