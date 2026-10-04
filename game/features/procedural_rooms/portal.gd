extends GarageDoor
## Preserve GPS door routing while using the shared validated interaction transport.

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	super._ready()
	entity.register_use(_can_enter, _travel, .5)


func _can_enter(player: Player) -> bool:
	return entity.in_range(player) and is_instance_valid(_arrival) and not DevGate.blocks(self)


func _travel(player: Player) -> bool:
	var zones := ZoneInstances.for_node(self)
	if zones != null and _arrival is SlumArrivalPoint:
		return zones.enter_development_zone(player, _arrival as SlumArrivalPoint)
	var runs := get_tree().get_first_node_in_group(&"slum_runs") as SlumRuns
	if runs != null:
		runs.finish(player.get_multiplayer_authority())
	player.server_teleport.rpc_id(
		player.get_multiplayer_authority(),
		_arrival.global_position,
		_arrival.global_basis.get_euler().y
	)
	return true


func use() -> void:
	entity.request_use()


@rpc("any_peer", "call_local", "reliable")
func request_enter() -> void:
	entity.receive_legacy_action(&"use")
