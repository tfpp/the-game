class_name FrogHop
extends RefCounted
## Pure math for the frogs feature: hop arcs, target selection, facing, and color
## assignment. Deterministic given its inputs and free of scene access, so it's
## unit-testable the same way core/movement/source_movement.gd keeps math separate
## from the node that uses it.

const HOP_RADIUS := 2.5

## Trampoline-style rebound off a hop that struck a surface: shorter and springier
## than a normal hop, mirroring features/trampoline/trampoline_bounce.gd's "give a
## boost even off a glancing hit" feel.
const BOUNCE_DISTANCE_SCALE := 0.7
const BOUNCE_HEIGHT_GAIN := 1.15

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


## Fixed, distinct profiles travel with each spawn, including to late joiners.
static func profile_for_index(index: int) -> Dictionary:
	var sizes: Array[float] = [0.65, 0.85, 1.0, 1.2, 1.4, 0.95]
	var distances: Array[float] = [0.85, 1.4, 1.8, 2.2, 2.6, 1.65]
	var slot := posmod(index, sizes.size())
	return {
		"size": sizes[slot],
		"distance": distances[slot],
		"height": 0.35 + sizes[slot] * 0.25,
		"duration": 0.32 + sizes[slot] * 0.12,
		"rest": 0.65 + float(slot) * 0.22,
	}


static func escape_direction(from: Vector3, threat: Vector3, fallback: Vector3) -> Vector3:
	var away := (from - threat) * Vector3(1, 0, 1)
	if away.is_zero_approx():
		return fallback.normalized()
	return away.normalized()


## Horizontal direction a hop rebounds in after striking a surface with the given
## normal, like a ball off a trampoline: mirrored across the surface, so a
## head-on hit bounces straight back and a glancing one deflects at an oblique
## angle. Both vectors are flattened to the XZ plane; near-vertical normals (e.g.
## landing flat on a floor) fall back to reversing the incoming direction.
static func bounce_direction(incoming: Vector3, normal: Vector3) -> Vector3:
	var flat_incoming := incoming * Vector3(1, 0, 1)
	if flat_incoming.is_zero_approx():
		flat_incoming = Vector3.FORWARD
	flat_incoming = flat_incoming.normalized()
	var flat_normal := normal * Vector3(1, 0, 1)
	if flat_normal.is_zero_approx():
		return -flat_incoming
	flat_normal = flat_normal.normalized()
	var reflected := flat_incoming - 2.0 * flat_incoming.dot(flat_normal) * flat_normal
	return reflected.normalized() if not reflected.is_zero_approx() else -flat_incoming
