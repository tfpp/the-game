class_name ProjectileMath
extends RefCounted
## Pure motion for gun_machine projectiles: gravity-affected flight, bounces and
## splash falloff, kept free of scene access the same way
## features/holdables/throw_math.gd keeps its arcs separate from thrown_item.gd.

## Matches core/movement's Source-style gravity (MovementConfig.gravity_m()), so a
## grenade falls at the same rate a player does.
const GRAVITY_MPS2 := 800.0 * MovementConfig.UNIT_TO_METERS
## Fraction of speed kept after a bounce, so each one is weaker than the last.
const BOUNCE_RESTITUTION := 0.55
## Bounces slower than this settle instead of continuing to hop forever.
const MIN_BOUNCE_SPEED := 1.0


## Velocity after `delta` seconds of `gravity_scale` gravity (0 = unaffected, like a
## laser or a fast rifle round; 1 = falls exactly like a player).
static func fall(velocity: Vector3, gravity_scale: float, delta: float) -> Vector3:
	return velocity - Vector3.UP * GRAVITY_MPS2 * gravity_scale * delta


## Reflects `velocity` off a surface with the given (normalized) `normal`, losing
## energy to BOUNCE_RESTITUTION so a grenade's bounces get lower and shorter.
static func bounce(velocity: Vector3, normal: Vector3) -> Vector3:
	return (velocity - 2.0 * velocity.dot(normal) * normal) * BOUNCE_RESTITUTION


## Whether a bounced projectile is slow enough to settle instead of hopping again.
static func should_settle(velocity: Vector3) -> bool:
	return velocity.length() < MIN_BOUNCE_SPEED


## Damage at `distance` meters from an explosion of `radius` and `max_damage`,
## falling off linearly to 0 at the edge and beyond — direct hits still deal full
## `max_damage` regardless of this falloff.
static func splash_damage(distance: float, radius: float, max_damage: float) -> float:
	if radius <= 0.0 or distance >= radius:
		return 0.0
	return max_damage * (1.0 - distance / radius)


## How far (in meters) an explosion of `radius` and `max_force` shoves someone
## standing `distance` meters away, falling off linearly to 0 at the edge — the same
## shape as `splash_damage`, so a blast that barely grazes you barely moves you.
static func splash_force(distance: float, radius: float, max_force: float) -> float:
	if radius <= 0.0 or distance >= radius:
		return 0.0
	return max_force * (1.0 - distance / radius)
