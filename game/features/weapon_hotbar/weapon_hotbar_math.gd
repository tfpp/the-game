class_name WeaponHotbarMath
extends RefCounted
## Pure hotbar/recoil math for features/weapon_hotbar, kept free of scene access so
## it's unit-testable the same way features/holdables/throw_math.gd keeps toss math
## separate from hand.gd.


## Recoil strength remaining at `elapsed_s` into a `duration_s` kick: 1 at the shot,
## eased down to 0 by the end (quadratic, so it snaps back fast then settles slow).
static func recoil_ease(elapsed_s: float, duration_s: float) -> float:
	if duration_s <= 0.0:
		return 0.0
	var remaining := 1.0 - clampf(elapsed_s / duration_s, 0.0, 1.0)
	return remaining * remaining


## Local-space kick layered on top of a weapon view's rest pose: a backward and
## slightly upward punch that eases back to identity as `ease` falls to 0.
static func recoil_transform(kick_m: float, ease: float) -> Transform3D:
	var offset := Vector3(0.0, kick_m * 0.2, kick_m) * ease
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(kick_m * 40.0) * ease)
	return Transform3D(tilt, offset)


## Recoil distance for a shot dealing `damage`: harder-hitting guns kick more,
## clamped to a range that still reads as a snappy flinch rather than a wobble.
static func kick_for_damage(damage: float) -> float:
	return clampf(damage * 0.0045 + 0.035, 0.045, 0.15)


## Index of the next non-empty `backpack` slot, cycling from `current` in `direction`
## (+1 or -1) and wrapping around; -1 if every slot is empty.
static func next_slot(backpack: PackedStringArray, current: int, direction: int) -> int:
	var occupied: Array[bool] = []
	for id: String in backpack:
		occupied.append(not id.is_empty())
	return next_occupied(occupied, current, direction)


## Index of the next `true` entry in `occupied`, cycling from `current` in `direction`
## (+1 or -1) and wrapping around; -1 if nothing is occupied. The general form of
## `next_slot`, also used to cycle in an extra non-backpack slot (features/gun_machine's
## rig) alongside the backpack.
static func next_occupied(occupied: Array[bool], current: int, direction: int) -> int:
	var count := occupied.size()
	if count == 0:
		return -1
	for step: int in count:
		var index := posmod(current + direction * (step + 1), count)
		if occupied[index]:
			return index
	return -1
