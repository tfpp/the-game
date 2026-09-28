class_name BallPhysics
extends RefCounted
## Pure math for the soccer_ball feature (soccer_ball.gd): gravity, ground/wall
## bounces, rolling friction, being shoved by a player's body, and being kicked by
## gunfire. Kept free of scene access the same way core/movement/source_movement.gd
## and features/holdables/throw_math.gd keep their math separate and unit-tested.

## Real soccer-ball size, in meters.
const RADIUS_M := 0.12

## Free-fall acceleration, matching the vertical pull frogs settle under
## (features/frogs/frog.gd).
const GRAVITY_M_S2 := 18.0

## Fraction of vertical/into-surface speed kept after bouncing off the floor or a wall.
const GROUND_RESTITUTION := 0.5
const WALL_RESTITUTION := 0.55

## Exponential decay rate (per second) applied to horizontal speed: high friction
## while rolling on the ground, a light drag while airborne.
const GROUND_FRICTION_PER_S := 3.0
const AIR_DRAG_PER_S := 0.15

## Below this speed a grounded ball is considered stopped, so it doesn't creep
## forever from tiny amounts of rolling friction.
const REST_SPEED_M_S := 0.12

## An impact slower than this doesn't bounce at all — it just settles. Must clear
## one physics tick's worth of gravity (`GRAVITY_M_S2 / 60`, about 0.3 m/s) with
## margin, or a resting ball would re-trigger a "bounce" every single tick forever,
## since gravity alone re-accelerates it past a smaller cutoff before the next tick.
const MIN_BOUNCE_SPEED_M_S := 0.6

## How hard walking into the ball shoves it: a flat push scaled by how deep the
## player has overlapped it, plus a share of however fast they're closing on it, so
## running into the ball sends it further than just brushing against it.
const BUMP_PUSH_PER_M := 6.0
const BUMP_CARRY_FACTOR := 0.9

## A shot always adds this much speed toward the shot direction, with a bit of
## upward pop so it visibly pings off rather than just sliding.
const KICK_SPEED_M_S := 9.0
const KICK_UP_M_S := 2.0

const MAX_SPEED_M_S := 18.0


## Vertical acceleration for one physics step.
static func apply_gravity(
	velocity: Vector3, delta: float, gravity: float = GRAVITY_M_S2
) -> Vector3:
	return velocity + Vector3.DOWN * gravity * delta


## Exponential drag toward zero, `rate` per second, applied only to the horizontal
## component so it never fights `apply_gravity`.
static func apply_drag(velocity: Vector3, delta: float, rate: float) -> Vector3:
	var decay := exp(-rate * delta)
	return Vector3(velocity.x * decay, velocity.y, velocity.z * decay)


## A grounded ball slower than `rest_speed` stops instead of creeping forever.
static func settle(velocity: Vector3, rest_speed: float = REST_SPEED_M_S) -> Vector3:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < rest_speed:
		return Vector3(0.0, velocity.y, 0.0)
	return velocity


## Reflects a falling `velocity`'s vertical component off the floor, losing
## `1 - restitution` of its speed. Leaves the vertical component untouched if it
## wasn't falling, or zeroes it if the impact was softer than `min_speed` — settling
## instead of bouncing forever at a shrinking amplitude, the same cutoff
## features/holdables/throw_math.gd's `MIN_BOUNCE_HEIGHT` applies to thrown items.
static func bounce_off_floor(
	velocity: Vector3,
	restitution: float = GROUND_RESTITUTION,
	min_speed: float = MIN_BOUNCE_SPEED_M_S
) -> Vector3:
	if velocity.y >= 0.0:
		return velocity
	if velocity.y >= -min_speed:
		return Vector3(velocity.x, 0.0, velocity.z)
	return Vector3(velocity.x, -velocity.y * restitution, velocity.z)


## Reflects `velocity` off a surface with the given `normal`, losing `1 - restitution`
## of the speed driving into it. Leaves `velocity` alone if it isn't heading into the
## surface (e.g. already moving away from it).
static func reflect_off_wall(
	velocity: Vector3, normal: Vector3, restitution: float = WALL_RESTITUTION
) -> Vector3:
	var into := velocity.dot(normal)
	if into >= 0.0:
		return velocity
	return velocity - normal * into * (1.0 + restitution)


## Clamps a velocity's horizontal speed to `max_speed`, leaving its vertical
## component untouched.
static func clamp_horizontal_speed(velocity: Vector3, max_speed: float = MAX_SPEED_M_S) -> Vector3:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() <= max_speed:
		return velocity
	var clamped := flat.normalized() * max_speed
	return Vector3(clamped.x, velocity.y, clamped.z)


## The ball's velocity after a player's body overlaps it: shoved directly away from
## the player, plus a share of however fast they're closing on it. Leaves
## `ball_velocity` unchanged if `actor_position` isn't within `contact_radius`
## (the ball's radius plus the actor's own, i.e. features/holdables/hand.gd never
## needs to know about this — see soccer_ball.gd's `_apply_bumps`).
static func bump_velocity(
	ball_position: Vector3,
	ball_velocity: Vector3,
	actor_position: Vector3,
	actor_velocity: Vector3,
	contact_radius: float,
	push_per_m: float = BUMP_PUSH_PER_M,
	carry_factor: float = BUMP_CARRY_FACTOR,
	max_speed: float = MAX_SPEED_M_S
) -> Vector3:
	var away := Vector3(ball_position.x - actor_position.x, 0.0, ball_position.z - actor_position.z)
	var distance := away.length()
	if distance >= contact_radius:
		return ball_velocity
	var direction := Vector3.FORWARD if away.is_zero_approx() else away / distance
	var overlap := contact_radius - distance
	var closing := maxf(0.0, actor_velocity.dot(direction))
	var push := direction * (overlap * push_per_m + closing * carry_factor)
	var pushed := Vector3(ball_velocity.x + push.x, ball_velocity.y, ball_velocity.z + push.z)
	return clamp_horizontal_speed(pushed, max_speed)


## The ball's velocity after a hitscan hit from `shooter_position`: a fixed kick
## along the shot's direction (approximated as shooter-to-ball, since take_hit only
## carries the attacker's peer id) with some upward pop.
static func kick_velocity(
	velocity: Vector3,
	shooter_position: Vector3,
	ball_position: Vector3,
	kick_speed: float = KICK_SPEED_M_S,
	kick_up_speed: float = KICK_UP_M_S,
	max_speed: float = MAX_SPEED_M_S
) -> Vector3:
	var away := Vector3(
		ball_position.x - shooter_position.x, 0.0, ball_position.z - shooter_position.z
	)
	var direction := Vector3.FORWARD if away.is_zero_approx() else away.normalized()
	var kicked := velocity + direction * kick_speed + Vector3.UP * kick_up_speed
	return clamp_horizontal_speed(kicked, max_speed)


## Incremental "rolling without slipping" spin for having moved `delta_position` this
## frame: a rotation of `distance / radius` radians around the horizontal axis
## perpendicular to the direction of travel. Identity if the ball didn't move.
static func rolling_spin(delta_position: Vector3, radius: float) -> Quaternion:
	var flat := Vector3(delta_position.x, 0.0, delta_position.z)
	var distance := flat.length()
	if distance < 0.0001 or radius <= 0.0:
		return Quaternion.IDENTITY
	var axis := Vector3.UP.cross(flat / distance)
	if axis.is_zero_approx():
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), distance / radius)
