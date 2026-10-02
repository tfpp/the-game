class_name SafeZone
extends Node3D
## A shared Golden Crown volume where players can't hurt each other or fire guns.
## Combat and the gun features query `covers()`; this node owns no state.

## Local extent; the feature root sits at the origin, so this is the world box.
@export var bounds := AABB()


func _enter_tree() -> void:
	add_to_group(&"safe_zones")


func contains(point: Vector3) -> bool:
	return bounds.has_point(to_local(point))


## True when any safe zone in `tree` contains `point`.
static func covers(tree: SceneTree, point: Vector3) -> bool:
	for node: Node in tree.get_nodes_in_group(&"safe_zones"):
		var zone := node as SafeZone
		if zone != null and zone.contains(point):
			return true
	return false


## True when `peer_id`'s player stands in a safe zone. Unknown peers are unprotected.
static func covers_peer(tree: SceneTree, peer_id: int) -> bool:
	for node: Node in tree.get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player != null and player.get_multiplayer_authority() == peer_id:
			return covers(tree, player.global_position)
	return false
