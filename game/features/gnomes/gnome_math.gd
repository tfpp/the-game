class_name GnomeMath
extends RefCounted
## Pure math for the gnomes feature: single-file "train" spacing as a line of gnomes
## dashes between two holes. Deterministic given its inputs and free of scene access,
## so it's unit-testable the same way core/movement/source_movement.gd keeps math
## separate from the node that uses it.

const RUN_SPEED := 10.5
const FOLLOW_SPACING := 0.4
const REST_MIN := 1.5
const REST_MAX := 4.5
const GNOME_COUNT := 4


## Total distance (meters) the leader must cover for the whole line to clear a
## `path_length`-meter tunnel: the tunnel itself, plus the spacing behind it needed for
## the last of `count` gnomes (each trailing the one ahead by `spacing`) to also reach
## the far hole.
static func total_distance(path_length: float, count: int, spacing: float) -> float:
	return path_length + maxf(count - 1, 0) * spacing


## Seconds to cover `total_dist` meters at `speed` m/s. Guards against a non-positive
## speed by returning 0, so callers never divide by zero.
static func leg_duration(total_dist: float, speed: float) -> float:
	if speed <= 0.0:
		return 0.0
	return total_dist / speed


## Advances the leader's progress (0 = at the starting hole, 1 = the whole line has
## cleared the tunnel) by `delta` seconds along a leg that takes `duration` seconds end
## to end. Clamped to [0, 1]; a non-positive duration finishes the leg immediately.
static func advance_progress(progress: float, delta: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(progress + delta / duration, 0.0, 1.0)


## Distance (meters) into the tunnel for the gnome at `index` (0 = leader), trailing
## the leader by `index * spacing` so the group runs single file. Clamped to
## [0, path_length]: a gnome whose turn hasn't come yet waits at the starting hole, and
## one that has already crossed waits at the far one.
static func follower_distance(
	progress: float, total_dist: float, path_length: float, index: int, spacing: float
) -> float:
	var head_distance := progress * total_dist
	return clampf(head_distance - index * spacing, 0.0, path_length)


## World position `distance` meters into the tunnel from `hole_a` to `hole_b` (or the
## reverse, if `forward` is false), `path_length` meters long.
static func gnome_position(
	hole_a: Vector3, hole_b: Vector3, forward: bool, distance: float, path_length: float
) -> Vector3:
	var start := hole_a if forward else hole_b
	var end := hole_b if forward else hole_a
	var t := distance / path_length if path_length > 0.0 else 0.0
	return start.lerp(end, t)


## Whether a gnome `distance` meters into the tunnel should be drawn. A gnome exactly
## at either end is still inside a hole the size of a dog door, so it stays hidden
## until it has fully emerged and before it has fully entered the far one.
static func gnome_visible(distance: float, path_length: float) -> bool:
	return distance > 0.0 and distance < path_length


## Yaw (radians) facing the direction of travel through the tunnel, using the same
## forward convention as SourceMovement.wish_direction. Zero if the holes coincide.
static func facing_yaw(hole_a: Vector3, hole_b: Vector3, forward: bool) -> float:
	var direction := (hole_b - hole_a) if forward else (hole_a - hole_b)
	direction.y = 0.0
	if direction.is_zero_approx():
		return 0.0
	direction = direction.normalized()
	return atan2(-direction.x, -direction.z)
