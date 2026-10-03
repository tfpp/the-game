class_name VipDoor
extends GarageDoor
## Reuses the existing GPS portal contract. The inherited CSG is only the unique
## door leaf, never room architecture; all use paths delegate to the shared component.

@export var exiting := false
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var club: VipLounge = get_parent()


func _ready() -> void:
	super._ready()
	entity.interaction_range = USE_RANGE_M
	entity.register_use(can_use, _travel, 0.75)


func interaction_text() -> String:
	if exiting:
		return "Return to the casino floor"
	return "Examine the mirror — $2,000 balance required; entry is free"


func can_use(player: Player) -> bool:
	return (
		player != null
		and entity.in_range(player)
		and (exiting or club.eligible(player.get_multiplayer_authority()))
	)


func use() -> void:
	entity.request_use()


@rpc("any_peer", "call_local", "reliable")
func request_enter() -> void:
	entity.receive_legacy_action(&"use")


func _travel(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var arrival := get_node_or_null(destination) as Marker3D
	if arrival == null:
		return false
	if exiting:
		club.leave(peer)
		entity.send_event(&"arrival", {"text": "Your secret is safe with us."}, peer)
	elif not club.enter(player, entity):
		return false
	player.server_teleport.rpc_id(peer, arrival.global_position, arrival.global_rotation.y)
	return true
