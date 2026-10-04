class_name SlumDestinations
extends RefCounted
## Selects a registered garage or alley destination for a private excursion.
## Optional API filtering keeps separate multiplayer branches independent.


static func pick(tree: SceneTree, api: MultiplayerAPI = null) -> SlumArrivalPoint:
	var points: Array[SlumArrivalPoint] = []
	for node: Node in tree.get_nodes_in_group(&"slum_arrival_points"):
		if node is SlumArrivalPoint and (api == null or node.multiplayer == api):
			points.append(node as SlumArrivalPoint)
	if points.is_empty():
		return null
	return points[randi() % points.size()] as SlumArrivalPoint
