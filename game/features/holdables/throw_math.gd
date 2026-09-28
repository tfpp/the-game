class_name ThrowMath
extends RefCounted
## Pure geometry for holdables: the toss arc thrown props follow, and the aim
## direction used to pick a landing point. Kept free of scene access so it's
## unit-testable the same way frogs/frog_hop.gd keeps hop math separate.

const ARC_HEIGHT := 1.1


## Position along a toss arc from `from` to `to`, `t` in [0, 1] (clamped), peaking
## `ARC_HEIGHT` above the straight-line path at the midpoint.
static func arc_position(from: Vector3, to: Vector3, t: float) -> Vector3:
	var clamped := clampf(t, 0.0, 1.0)
	var pos := from.lerp(to, clamped)
	pos.y += sin(clamped * PI) * ARC_HEIGHT
	return pos


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
