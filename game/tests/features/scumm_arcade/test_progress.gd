extends GutTest

const SAVE := "user://scumm-arcade-test/progress.sav"
var store: ScummArcadeProgressStore


func before_each() -> void:
	_clean()
	store = ScummArcadeProgressStore.new(SAVE)


func after_each() -> void:
	_clean()


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(SAVE + suffix)


func _played() -> ScummArcadeSession:
	var session := ScummArcadeSession.new()
	for tick: int in 613:
		if tick % 7 == 0:
			session.enqueue([1, tick % 320, tick % 200, 0])
		session.advance()
	return session


func test_disk_checkpoint_restores_exact_replay_and_releases_held_inputs() -> void:
	var original := _played()
	original.enqueue([0, 17, 18, 0])
	assert_true(store.save_progress(original, "runtime-a"))
	var restored := store.load_progress("runtime-a")
	assert_not_null(restored)
	assert_eq(restored.tick, original.tick)
	assert_eq(restored.event_count, original.event_count)
	for start: int in [0, 250, 500]:
		assert_eq(restored.batch(start), original.batch(start))
	assert_eq(restored.pending[0][0], 2)
	assert_eq(restored.pending[1][0], 4)
	assert_eq(restored.pending.size(), 5)
	assert_null(store.load_progress("different-runtime"))


func test_corruption_and_missing_primary_recover_previous_complete_save() -> void:
	var session := _played()
	assert_true(store.save_progress(session, "runtime-a"))
	session.advance()
	assert_true(store.save_progress(session, "runtime-a"))
	var file := FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_string("interrupted write")
	file.close()
	assert_eq(store.load_progress("runtime-a").tick, 613)
	DirAccess.remove_absolute(SAVE)
	assert_eq(store.load_progress("runtime-a").tick, 613)


func test_changed_payload_fails_digest_check_without_backup() -> void:
	assert_true(store.save_progress(_played(), "runtime-a"))
	var file := FileAccess.open(SAVE, FileAccess.READ_WRITE)
	file.seek(44)
	file.store_8(255)
	file.close()
	assert_null(store.load_progress("runtime-a"))
	assert_false(store.failure.is_empty())


func test_restore_rejects_invalid_ticks_events_and_unbounded_history() -> void:
	assert_null(ScummArcadeSession.restore({"tick": -1, "history": {}}))
	assert_null(ScummArcadeSession.restore({"tick": 180001, "history": {}}))
	assert_null(ScummArcadeSession.restore({"tick": 1.0, "history": {}}))
	assert_null(ScummArcadeSession.restore({"tick": 1, "history": {1: [[1, 1, 1, 0]]}}))
	assert_null(ScummArcadeSession.restore({"tick": 1, "history": {0: [[5, 1, 1, 999]]}}))
	assert_null(ScummArcadeSession.restore({"tick": 1, "history": {0: "invalid"}}))
	var events: Array = []
	for index: int in 13:
		events.append([1, index, 1, 0])
	assert_null(ScummArcadeSession.restore({"tick": 1, "history": {0: events}}))


func test_reset_replaces_saved_progress_and_release_respects_event_limit() -> void:
	assert_true(store.save_progress(_played(), "runtime-a"))
	assert_true(store.save_progress(ScummArcadeSession.new(), "runtime-a"))
	assert_eq(store.load_progress("runtime-a").tick, 0)
	var session := ScummArcadeSession.new()
	session.event_count = ScummArcadeSession.MAX_EVENTS - 1
	session.release_buttons()
	session.advance()
	assert_eq(session.event_count, ScummArcadeSession.MAX_EVENTS)
