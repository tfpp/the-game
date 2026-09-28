class_name ElevatorMath
extends RefCounted
## Pure math for features/elevator, kept free of scene access the same way
## features/nyc_ferry/ferry_path.gd separates timeline math from the scene.
##
## The key trick for a "seamless" cab: express an occupant's position in the cab's own
## local space (`relative_offset`), then re-apply that same local offset against the
## destination cab's transform (`apply_offset`). Since the offset is expressed in each
## cab's own axes, this reproduces the group's exact relative arrangement regardless of
## how the two cabs are rotated in the world.


## `global_pos` expressed in `cab_transform`'s local space.
static func relative_offset(global_pos: Vector3, cab_transform: Transform3D) -> Vector3:
	return cab_transform.affine_inverse() * global_pos


## The world position `local_offset` (as produced by `relative_offset`) maps to once
## re-anchored on `cab_transform`.
static func apply_offset(local_offset: Vector3, cab_transform: Transform3D) -> Vector3:
	return cab_transform * local_offset


## Whether a cab-local position sits inside the boarding footprint: within
## `half_width`/`half_depth` horizontally and between the floor and `height` vertically.
## The floor sits at local y 0, so a small negative allowance covers standing jitter.
static func is_inside(
	local_pos: Vector3, half_width: float, half_depth: float, height: float
) -> bool:
	return (
		absf(local_pos.x) <= half_width
		and absf(local_pos.z) <= half_depth
		and local_pos.y >= -0.2
		and local_pos.y <= height
	)


## Door open fraction (0 closed, 1 open) `duration_s` after a slide starts, going
## `opening` (true) or the reverse. A non-positive duration snaps straight to the end.
static func door_fraction(elapsed_s: float, duration_s: float, opening: bool) -> float:
	if duration_s <= 0.0:
		return 1.0 if opening else 0.0
	var t := clampf(elapsed_s / duration_s, 0.0, 1.0)
	return t if opening else 1.0 - t


## Local sideways offset for one door leaf at open fraction `t` (0 closed, 1 fully
## retracted `max_offset` from the doorway centerline).
static func door_leaf_offset(t: float, max_offset: float) -> float:
	return t * max_offset
