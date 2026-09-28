class_name ThrowMath
extends RefCounted
## Pure geometry for holdables: the toss arc thrown props follow, and the aim
## direction used to pick a landing point. Kept free of scene access so it's
## unit-testable the same way frogs/frog_hop.gd keeps hop math separate.

const ARC_HEIGHT := 1.1

## Peak height of the first bounce for a weightless item; heavier items subtract from
## this (see `bounce_height`).
const BOUNCE_BASE_HEIGHT := 0.5
## Every this many kg of weight cancels one meter of bounce height.
const BOUNCE_WEIGHT_DIVISOR := 2.0
## Each successive bounce keeps this fraction of the previous one's height/distance.
const BOUNCE_DECAY := 0.45
## Bounces peaking below this height aren't worth animating; the item settles instead.
const MIN_BOUNCE_HEIGHT := 0.05
## Horizontal travel of the first bounce.
const BOUNCE_DISTANCE := 0.9


## Position along a toss arc from `from` to `to`, `t` in [0, 1] (clamped), peaking
## `height` above the straight-line path at the midpoint.
static func arc_position(
	from: Vector3, to: Vector3, t: float, height: float = ARC_HEIGHT
) -> Vector3:
	var clamped := clampf(t, 0.0, 1.0)
	var pos := from.lerp(to, clamped)
	pos.y += sin(clamped * PI) * height
	return pos


## Peak height of the `bounce_index`th bounce (0 = the first bounce after landing) for
## an item of the given `weight`: heavier items barely bounce, light ones keep hopping.
static func bounce_height(weight: float, bounce_index: int) -> float:
	var base := maxf(BOUNCE_BASE_HEIGHT - weight / BOUNCE_WEIGHT_DIVISOR, 0.0)
	return base * pow(BOUNCE_DECAY, bounce_index)


## Horizontal travel of the `bounce_index`th bounce, decaying the same way its height does.
static func bounce_distance(bounce_index: int) -> float:
	return BOUNCE_DISTANCE * pow(BOUNCE_DECAY, bounce_index)


## Forward look direction from view angles, matching Player's yaw/pitch convention
## (yaw/pitch of zero looks down -Z).
static func aim_direction(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0.0, 0.0, -1.0)


## A flat toss target `distance` ahead of `origin` along `direction`'s horizontal
## component, ignoring vertical aim so a toss lands roughly where the thrower is
## looking without needing the world's floor height up front (callers can still
## raycast down from the result to place it exactly).
static func toss_target(origin: Vector3, direction: Vector3, distance: float) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.is_zero_approx():
		flat = Vector3.FORWARD
	return origin + flat.normalized() * distance
