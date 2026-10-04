class_name CombatHealthState
extends Node
## One server-spawned player's health snapshot, private to their current group.

@export var value := 100.0
var peer_id := 0


func _ready() -> void:
	var entity := NetworkedEntity.new()
	entity.name = "NetworkedEntity"
	entity.replicated_properties = [NodePath(".:value")]
	add_child(entity)


func network_peer_allowed(peer: int) -> bool:
	for service: Node in get_tree().get_nodes_in_group(&"zone_instances"):
		if service.multiplayer == multiplayer:
			return bool(service.call("can_observe_player", peer_id, peer))
	return true
