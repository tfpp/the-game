class_name ScummArcadePointer
extends RefCounted
## Maps a camera ray onto the actual, tilted cabinet screen.

const SIZE := Vector2(1.18, 0.885)
const MISS := Vector2i(-1, -1)


static func project(screen: Transform3D, origin: Vector3, direction: Vector3) -> Vector2i:
	var inverse := screen.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	if local_direction.z >= -0.00001:
		return MISS
	var distance := -local_origin.z / local_direction.z
	if distance < 0:
		return MISS
	var hit := local_origin + local_direction * distance
	if absf(hit.x) > SIZE.x / 2 or absf(hit.y) > SIZE.y / 2:
		return MISS
	return Vector2i(
		clampi(int((hit.x / SIZE.x + 0.5) * 320), 0, 319),
		clampi(int((0.5 - hit.y / SIZE.y) * 200), 0, 199)
	)
