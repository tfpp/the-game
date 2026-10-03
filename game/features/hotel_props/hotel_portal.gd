extends RoomDoor
## Use the shared authenticated interaction transport and streamed arrival preload.

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	super._ready()
	entity.register_use(_can_enter, _travel, 0.5)


func _can_enter(player: Player) -> bool:
	if not is_instance_valid(_arrival):
		_arrival = get_node_or_null(destination) as Marker3D
	return entity.in_range(player) and is_instance_valid(_arrival) and not DevGate.blocks(self)


func _travel(player: Player) -> bool:
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
	var room := destination_room()
	if room != null:
		room.load_room(ARRIVAL_HOLD_MSEC)
	entity.request_use()


@rpc("any_peer", "call_local", "reliable")
func request_enter() -> void:
	entity.receive_legacy_action(&"use")
