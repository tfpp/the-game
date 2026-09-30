class_name PenguinWaddle
extends RefCounted
## Pure math for the penguin feature: circular patrol and the cosmetic waddle rock.
## Deterministic given its inputs and free of scene access, so it's unit-testable the
## same way core/movement/source_movement.gd keeps math separate from the node that
## uses it.

const PATROL_RADIUS := 2.0
const WALK_SPEED := 0.7
const WADDLE_FREQUENCY := 2.4
const WADDLE_AMPLITUDE := 0.35

## How close (meters) a player in penguin costume must be for the NPC to notice and
## react — see `Penguin._reacting_to_nearby_penguin_player` in penguin.gd.
const REACT_RADIUS := 4.0
const WAVE_FREQUENCY := 3.0
const WAVE_AMPLITUDE := 0.9
const BOUNCE_FREQUENCY := 2.6
const BOUNCE_HEIGHT := 0.22

## How close (meters) the two penguin NPCs must be for the happy couple reaction
## (hop and wave) — see `Penguin._near_spouse` in penguin.gd.
const COUPLE_RADIUS := 2.0


## Position on the patrol circle of the given `radius` around `home`, at `angle`
## radians (0 at +Z, increasing toward +X).
static func position_on_circle(home: Vector3, radius: float, angle: float) -> Vector3:
	return home + Vector3(sin(angle), 0.0, cos(angle)) * radius


## Angular speed (radians/second) for walking the circle at `walk_speed` (m/s).
## Zero if `radius` isn't positive, so a degenerate patrol doesn't spin forever.
static func angular_speed(radius: float, walk_speed: float) -> float:
	if radius <= 0.0:
		return 0.0
	return walk_speed / radius


## Yaw (radians) facing the direction of travel at `angle` on the patrol circle,
## using the model's +Z forward direction (belly, beak and toes).
static func facing_yaw(angle: float) -> float:
	return atan2(cos(angle), -sin(angle))


## Side-to-side rocking angle (radians) for the cosmetic waddle, at `elapsed` seconds.
static func waddle_rock(elapsed: float, frequency: float, amplitude: float) -> float:
	return sin(elapsed * TAU * frequency) * amplitude


## Flipper swing angle (radians) for the "wave hello" reaction, oscillating around
## zero the same way `waddle_rock` does, just at its own frequency/amplitude.
static func wave_angle(elapsed: float, frequency: float, amplitude: float) -> float:
	return sin(elapsed * TAU * frequency) * amplitude


## Vertical offset (meters, always >= 0) for the "excited hop" reaction: a bounce
## off the ground and back, repeating at `frequency` Hz up to `height`.
static func react_bounce(elapsed: float, frequency: float, height: float) -> float:
	return absf(sin(elapsed * TAU * frequency)) * height
