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
