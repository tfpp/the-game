extends RefCounted
## Waits that follow the wall clock instead of game frames.
##
## check.sh runs GUT with `--fixed-fps 60`, so frames, `wait_seconds()` and
## `wait_physics_frames()` advance as fast as the CPU allows. Use these helpers when the
## code under test reads `Time.get_ticks_msec()` (action cooldowns) or depends on real
## I/O such as ENet transport or audio playback. Frames are paced at about 60 per second,
## so game time keeps up with the wall clock while waiting.

const FRAME_MSEC := 16


## Waits at least `seconds` of wall-clock time.
static func wait(tree: SceneTree, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + ceili(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await _frame(tree)


## Waits until `condition` returns true or `timeout_seconds` of wall-clock time pass.
## Returns the condition's final value, so the caller can assert on it.
static func wait_until(tree: SceneTree, condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + ceili(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return bool(condition.call())
		await _frame(tree)
	return true


static func _frame(tree: SceneTree) -> void:
	await tree.physics_frame
	OS.delay_msec(FRAME_MSEC)
