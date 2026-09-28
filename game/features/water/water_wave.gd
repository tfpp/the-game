class_name WaterWave
extends RefCounted
## Pure math for the water feature's gentle surface bob (see features/water/water.gd).
## Kept separate from the scene the same way `core/movement/source_movement.gd`
## separates movement math from the player node.


## The water surface's height at `elapsed_s` seconds, bobbing sinusoidally around
## `base_y` by `amplitude_m` every `period_s` seconds.
static func surface_y(
	base_y: float, elapsed_s: float, amplitude_m: float, period_s: float
) -> float:
	return base_y + sin(elapsed_s * TAU / period_s) * amplitude_m
