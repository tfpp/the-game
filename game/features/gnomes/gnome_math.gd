class_name GnomeMath
extends RefCounted
## Pure math for the gnomes feature: single-file "train" spacing as a line of gnomes
## dashes along a navmesh path between holes picked at random from a burrow's set.
## Deterministic given its inputs and free of scene access, so it's unit-testable the
## same way core/movement/source_movement.gd keeps math separate from the node that
## uses it.

const RUN_SPEED := 7.0
const FOLLOW_SPACING := 0.7
const REST_MIN := 1.0
const REST_MAX := 5.5
const GNOME_COUNT := 3
const SPEED_JITTER := 0.2
const AVOID_RADIUS := 3.0
const AVOID_MAX_OFFSET := 1.1


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


## Total length (meters) of a navmesh path, summing each segment between consecutive
## waypoints. Zero for an empty or single-point path.
static func path_total_length(waypoints: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, waypoints.size()):
		total += waypoints[i - 1].distance_to(waypoints[i])
	return total


## World position `distance` meters along a polyline `waypoints`, clamped to the ends
## of the path. Walks the segments accumulating length rather than assuming a single
## straight run, so gnomes can follow a navmesh route around obstacles.
static func position_on_path(waypoints: PackedVector3Array, distance: float) -> Vector3:
	if waypoints.is_empty():
		return Vector3.ZERO
	if waypoints.size() == 1 or distance <= 0.0:
		return waypoints[0]
	var remaining := distance
	for i in range(1, waypoints.size()):
		var seg_start := waypoints[i - 1]
		var seg_end := waypoints[i]
		var seg_len := seg_start.distance_to(seg_end)
		if remaining <= seg_len or i == waypoints.size() - 1:
			var t := remaining / seg_len if seg_len > 0.0 else 0.0
			return seg_start.lerp(seg_end, clampf(t, 0.0, 1.0))
		remaining -= seg_len
	return waypoints[waypoints.size() - 1]


## Normalized direction of travel `distance` meters along `waypoints`, i.e. the
## direction of whichever segment that point falls on. `Vector3.FORWARD` for a path
## too short to have a direction.
static func direction_on_path(waypoints: PackedVector3Array, distance: float) -> Vector3:
	if waypoints.size() < 2:
		return Vector3.FORWARD
	var remaining := distance
	for i in range(1, waypoints.size()):
		var seg_start := waypoints[i - 1]
		var seg_end := waypoints[i]
		var seg_len := seg_start.distance_to(seg_end)
		if remaining <= seg_len or i == waypoints.size() - 1:
			var dir := seg_end - seg_start
			return dir.normalized() if not dir.is_zero_approx() else Vector3.FORWARD
		remaining -= seg_len
	var dir := waypoints[waypoints.size() - 1] - waypoints[waypoints.size() - 2]
	return dir.normalized() if not dir.is_zero_approx() else Vector3.FORWARD


## Whether a gnome `distance` meters into the tunnel should be drawn. A gnome exactly
## at either end is still inside a hole the size of a dog door, so it stays hidden
## until it has fully emerged and before it has fully entered the far one.
static func gnome_visible(distance: float, path_length: float) -> bool:
	return distance > 0.0 and distance < path_length


## Yaw (radians) facing `direction`, using the same forward convention as
## SourceMovement.wish_direction. Zero if `direction` is flat-zero.
static func facing_yaw(direction: Vector3) -> float:
	var flat := direction
	flat.y = 0.0
	if flat.is_zero_approx():
		return 0.0
	flat = flat.normalized()
	return atan2(-flat.x, -flat.z)


## Picks the next hole a leg should run to, favoring holes further from `current` so
## gnomes cross the map instead of shuttling to whatever hole happens to be nearby.
## Weighted by squared distance among every index other than `current`; `rng` is a
## caller-supplied random value in [0, 1) that selects a point in the resulting
## cumulative-weight range (pass `randf()` from game code, a fixed value from tests).
## Never returns `current`, and is unaffected by holes exactly on top of it (weight 0).
static func next_hole_index(current: int, holes: Array[Vector3], rng: float) -> int:
	if holes.size() <= 1:
		return current
	var weights: Array[float] = []
	var total_weight := 0.0
	for i in holes.size():
		var weight := 0.0
		if i != current:
			var dist := holes[current].distance_to(holes[i])
			weight = dist * dist
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0:
		for i in range(holes.size() - 1, -1, -1):
			if i != current:
				return i
		return current
	var target := clampf(rng, 0.0, 1.0) * total_weight
	var cumulative := 0.0
	for i in holes.size():
		cumulative += weights[i]
		if target < cumulative:
			return i
	for i in range(holes.size() - 1, -1, -1):
		if i != current:
			return i
	return current


## Per-leg run speed with a bit of randomness so consecutive legs don't feel
## identical: scales `base_speed` linearly across [1 - SPEED_JITTER, 1 + SPEED_JITTER]
## as `rng` (a caller-supplied value, normally `randf()`) goes from 0 to 1.
static func leg_speed(base_speed: float, rng: float) -> float:
	var t := clampf(rng, 0.0, 1.0)
	return base_speed * (1.0 - SPEED_JITTER + 2.0 * SPEED_JITTER * t)


## Sideways nudge (world-space, y = 0) that steers a gnome at `gnome_pos` away from
## every position in `player_positions` within AVOID_RADIUS, perpendicular to
## `travel_dir` so it reads as a sidestep rather than a slowdown. Contributions from
## multiple nearby players stack, then the total is capped at AVOID_MAX_OFFSET.
static func avoidance_offset(
	gnome_pos: Vector3, travel_dir: Vector3, player_positions: Array[Vector3]
) -> Vector3:
	var flat_dir := travel_dir
	flat_dir.y = 0.0
	var perp := Vector3(-flat_dir.z, 0.0, flat_dir.x)
	perp = perp.normalized() if not perp.is_zero_approx() else Vector3.RIGHT
	var push := Vector3.ZERO
	for player_pos: Vector3 in player_positions:
		var to_gnome := gnome_pos - player_pos
		to_gnome.y = 0.0
		var distance := to_gnome.length()
		if distance <= 0.0001 or distance >= AVOID_RADIUS:
			continue
		var side := 1.0 if perp.dot(to_gnome) >= 0.0 else -1.0
		var strength := (AVOID_RADIUS - distance) / AVOID_RADIUS
		push += perp * side * strength
	if push.length() > AVOID_MAX_OFFSET:
		push = push.normalized() * AVOID_MAX_OFFSET
	return push
