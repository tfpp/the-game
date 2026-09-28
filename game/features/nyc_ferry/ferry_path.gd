class_name NycFerryPath
extends RefCounted
## Pure timeline math for the NYC ferry's back-and-forth route, kept separate from the
## scene the same way `core/movement/source_movement.gd` separates movement math from
## the player node.
##
## The route is a straight line `route_length_m` long. The ferry waits `dock_wait_s` at
## each end, crosses at `speed_mps`, waits at the other end, and repeats forever.


## Distance travelled from dock A (0) toward dock B (`route_length_m`) at `elapsed_s`
## seconds since the schedule started.
static func distance_along_route(
	elapsed_s: float, route_length_m: float, speed_mps: float, dock_wait_s: float
) -> float:
	var leg_s := route_length_m / speed_mps
	var cycle_s := 2.0 * (leg_s + dock_wait_s)
	var phase_s := fmod(elapsed_s, cycle_s)
	if phase_s < 0.0:
		phase_s += cycle_s
	if phase_s < dock_wait_s:
		return 0.0
	phase_s -= dock_wait_s
	if phase_s < leg_s:
		return phase_s * speed_mps
	phase_s -= leg_s
	if phase_s < dock_wait_s:
		return route_length_m
	phase_s -= dock_wait_s
	return route_length_m - phase_s * speed_mps
