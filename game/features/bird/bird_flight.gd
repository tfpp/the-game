class_name BirdFlight
extends RefCounted
## Pure mathematics and rules for the bird's flight paths, bank/pitch orientation,
## wing flapping, perch offsets, and candidate target selection.
## Kept free of scene dependencies so GUT tests can check them directly.

const ARRIVAL_DISTANCE := 1.2
const CRUISE_SPEED := 6.5
const REST_MIN_S := 1.5
const REST_MAX_S := 3.0
const MIN_ARC_HEIGHT := 0.8
const MAX_ARC_HEIGHT := 3.2
const ARC_DISTANCE_FACTOR := 0.2
const FLAP_RATE := 14.0
const FLAP_AMPLITUDE := 0.6
const MAX_BANK := 0.5
const MAX_PITCH := 0.65
const DEFAULT_PERCH_HEIGHT := 1.55
const REMOTE_SMOOTHING := 12.0

const DEFAULT_PERCHES: Array[Vector3] = [
	Vector3(0.0, 1.8, 0.0),
	Vector3(5.0, 2.2, -4.0),
	Vector3(-5.0, 2.2, 4.0),
	Vector3(8.0, 2.0, 6.0),
	Vector3(-8.0, 2.0, -6.0),
]


## Computes the upward arc peak for a flight of horizontal distance `distance`.
static func arc_height(distance: float) -> float:
	return clampf(distance * ARC_DISTANCE_FACTOR, MIN_ARC_HEIGHT, MAX_ARC_HEIGHT)


## Evaluates 3D position along a parabolic arc between `start` and `dest`
## at `progress` (0.0 to 1.0).
static func flight_position(start: Vector3, dest: Vector3, progress: float, arc: float) -> Vector3:
	var p := clampf(progress, 0.0, 1.0)
	var linear_pos := start.lerp(dest, p)
	var lift := 4.0 * arc * p * (1.0 - p)
	return linear_pos + Vector3(0.0, lift, 0.0)


## Tangent velocity vector at `progress` along the arc (derivative of flight_position).
static func flight_velocity(start: Vector3, dest: Vector3, progress: float, arc: float) -> Vector3:
	var p := clampf(progress, 0.0, 1.0)
	var linear_vel := dest - start
	var lift_vel := 4.0 * arc * (1.0 - 2.0 * p)
	return linear_vel + Vector3(0.0, lift_vel, 0.0)


## Returns Vector2(yaw, pitch) in radians pointing along `velocity`.
## Standard Godot model faces -Z.
static func facing_angles(velocity: Vector3) -> Vector2:
	if velocity.is_zero_approx():
		return Vector2.ZERO
	var yaw := atan2(-velocity.x, -velocity.z)
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var pitch := clampf(atan2(velocity.y, horiz_speed), -MAX_PITCH, MAX_PITCH)
	return Vector2(yaw, pitch)


## Wing rotation angle on Z axis during flapping or resting.
static func wing_angle(
	elapsed: float, is_flying: bool, flap_rate: float = FLAP_RATE, flap_amp: float = FLAP_AMPLITUDE
) -> float:
	if is_flying:
		return sin(elapsed * flap_rate) * flap_amp
	return sin(elapsed * 2.5) * 0.05


## Bank (roll) angle into turn based on delta yaw.
static func bank_angle(yaw_change: float, delta: float) -> float:
	if delta <= 0.0001:
		return 0.0
	var yaw_rate := yaw_change / delta
	return clampf(-yaw_rate * 0.25, -MAX_BANK, MAX_BANK)


## Hover/perch offset relative to a target node's position.
static func perch_offset(target: Node3D, angle_seed: float = 0.0) -> Vector3:
	if target == null:
		return Vector3(0.0, DEFAULT_PERCH_HEIGHT, 0.0)
	var is_small := false
	if target.is_in_group(&"frogs") or target.is_in_group(&"gnomes"):
		is_small = true
	var h := 0.45 if is_small else DEFAULT_PERCH_HEIGHT
	var radius := 0.4 if is_small else 0.65
	var angle := angle_seed * TAU
	return Vector3(cos(angle) * radius, h, sin(angle) * radius)


## Filters an array of nodes to only include alive/valid Node3Ds.
static func clean_targets(nodes: Array) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for item: Variant in nodes:
		var node := item as Node3D
		if node != null and is_instance_valid(node):
			var alive_prop: Variant = node.get("net_alive")
			if alive_prop == null or bool(alive_prop):
				result.append(node)
	return result


## Selects the next target according to the wandering rule:
## - If no current target: pick active player (or first available player), else an NPC.
## - If current target is a player: pick from [other players, all NPCs].
## - If current target is an NPC: pick from [all players, other NPCs].
## Uses `rng_val` in [0.0, 1.0) to select randomly.
static func select_next_target(
	current: Node3D, players: Array[Node3D], npcs: Array[Node3D], rng_val: float = 0.0
) -> Node3D:
	var valid_players := clean_targets(players)
	var valid_npcs := clean_targets(npcs)

	if current == null or not is_instance_valid(current):
		if not valid_players.is_empty():
			return valid_players[0]
		if not valid_npcs.is_empty():
			return valid_npcs[0]
		return null

	var candidates: Array[Node3D] = []
	var is_player := valid_players.has(current)

	if is_player:
		for p: Node3D in valid_players:
			if p != current:
				candidates.append(p)
		candidates.append_array(valid_npcs)
	else:
		candidates.append_array(valid_players)
		for n: Node3D in valid_npcs:
			if n != current:
				candidates.append(n)

	if candidates.is_empty():
		if is_instance_valid(current):
			return current
		if not valid_players.is_empty():
			return valid_players[0]
		if not valid_npcs.is_empty():
			return valid_npcs[0]
		return null

	var idx := int(floor(clampf(rng_val, 0.0, 0.9999) * candidates.size()))
	return candidates[idx]
