class_name SlumDestinations
extends RefCounted
## Picks one of the registered slum maps (see slum_arrival_point.gd) for a player to be
## sent to. Only the Parking Garage is registered today, so this always returns it, but
## every caller already goes through this one chokepoint instead of a hardcoded
## NodePath — swapping the random pick below for a real one is the only change the
## Golden Crown elevator will need once a second slum exists.


static func pick(tree: SceneTree) -> SlumArrivalPoint:
	var points := tree.get_nodes_in_group(&"slum_arrival_points")
	if points.is_empty():
		return null
	return points[randi() % points.size()] as SlumArrivalPoint
