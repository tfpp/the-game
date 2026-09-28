class_name FrogHop
extends RefCounted
## Pure math for the frogs feature: hop arcs, target selection, facing, and color
## assignment. Deterministic given its inputs and free of scene access, so it's
## unit-testable the same way core/movement/source_movement.gd keeps math separate
## from the node that uses it.

const HOP_RADIUS := 2.5
const HOP_HEIGHT := 0.4
const HOP_DURATION := 0.35
const REST_MIN := 0.6
const REST_MAX := 2.4

const PALETTE: Array[Color] = [
	Color(0.25, 0.75, 0.3),
	Color(0.45, 0.55, 0.15),
	Color(0.15, 0.45, 0.2),
	Color(0.75, 0.75, 0.25),
	Color(0.5, 0.38, 0.18),
	Color(0.35, 0.65, 0.5),
]


## Position along a hop arc from `from` to `to`, `t` in [0, 1] (clamped), peaking
## `height` above the straight-line path at the midpoint.
static func arc_position(from: Vector3, to: Vector3, t: float, height: float) -> Vector3:
	var clamped := clampf(t, 0.0, 1.0)
	var pos := from.lerp(to, clamped)
	pos.y += sin(clamped * PI) * height
	return pos


## A point `distance_fraction` (0-1) of `radius` away from `home`, in the direction
## `angle` (radians, around +Y).
static func pick_target(
	home: Vector3, radius: float, angle: float, distance_fraction: float
) -> Vector3:
	var offset := (
		Vector3(sin(angle), 0.0, cos(angle)) * radius * clampf(distance_fraction, 0.0, 1.0)
	)
	return home + offset


## Yaw (radians) facing from `from` toward `to`, using the same forward convention as
## SourceMovement.wish_direction. Zero if the two points coincide.
static func facing_yaw(from: Vector3, to: Vector3) -> float:
	var direction := to - from
	direction.y = 0.0
	if direction.is_zero_approx():
		return 0.0
	direction = direction.normalized()
	return atan2(-direction.x, -direction.z)


## A distinct color for the given spawn index, cycling through the palette.
static func color_for_index(index: int) -> Color:
	return PALETTE[index % PALETTE.size()]
