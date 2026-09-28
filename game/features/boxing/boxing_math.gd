class_name BoxingMath
extends RefCounted
## Pure punch rules for features/boxing, kept separate so they're unit-tested
## without a scene (like features/holdables/throw_math.gd).

## A click released sooner than this is a jab; holding longer winds up a power punch.
const JAB_MAX_HOLD_S := 0.25
## Holding this long charges a power punch to full strength.
const FULL_CHARGE_S := 1.0
## Punch strength: 1.0 is enough on its own to knock a dummy down.
const JAB_STRENGTH := 0.25
const MIN_POWER_STRENGTH := 0.5
const MAX_POWER_STRENGTH := 1.0
## Damage to players, scaled by strength (a full power punch deals 25).
const PLAYER_DAMAGE_AT_FULL := 25.0


static func is_power(held_s: float) -> bool:
	return held_s >= JAB_MAX_HOLD_S


## 0 for a jab, then MIN..MAX_POWER_STRENGTH as the hold approaches FULL_CHARGE_S.
static func strength(held_s: float) -> float:
	if not is_power(held_s):
		return JAB_STRENGTH
	var amount := clampf((held_s - JAB_MAX_HOLD_S) / (FULL_CHARGE_S - JAB_MAX_HOLD_S), 0.0, 1.0)
	return lerpf(MIN_POWER_STRENGTH, MAX_POWER_STRENGTH, amount)


## Charge shown while winding up, 0..1.
static func charge(held_s: float) -> float:
	return clampf(held_s / FULL_CHARGE_S, 0.0, 1.0)


## Horizontal unit direction a punch pushes along, from the puncher's yaw
## (forward is -Z).
static func push_direction(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Distance a sliding body travels at `speed` under constant `friction` (m/s²).
static func slide_distance(speed: float, friction: float) -> float:
	return speed * speed / (2.0 * friction)
