class_name TrampolineBounce
extends RefCounted
## Pure math for the trampoline feature's launch velocity (see trampoline_pad.gd).
## Kept separate from the scene the same way `core/movement/source_movement.gd`
## separates movement math from the player node.

## Upward launch speed applied even to someone who merely steps on, in m/s.
const BASE_LAUNCH_M_S := 12.0
## Fraction of incoming downward speed added on top of the base launch, so diving
## onto the pad from a fall or jump launches higher than just walking on.
const FALL_GAIN := 0.5
## Upper bound on the launch speed, so a very fast fall can't send someone through
## the ceiling.
const MAX_LAUNCH_M_S := 20.0


## The upward velocity to give a body landing on the trampoline with the given
## vertical velocity (negative = falling).
static func launch_velocity_y(
	incoming_velocity_y: float,
	base_m_s: float = BASE_LAUNCH_M_S,
	fall_gain: float = FALL_GAIN,
	max_m_s: float = MAX_LAUNCH_M_S
) -> float:
	var launch := base_m_s + maxf(0.0, -incoming_velocity_y) * fall_gain
	return minf(launch, max_m_s)
