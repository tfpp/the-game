extends Node3D
## Static complimentary burger counter; delivered food belongs to PlayerInventory.

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _serve, 1.0)


func can_use(player: Player) -> bool:
	return entity.in_range(player) and to_local(player.net_position).z > 0.65


func interaction_text() -> String:
	var hand := Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	if hand != null and not hand.inventory().can_collect("wendys_burger"):
		return "Wendy's — make room in your hand or backpack"
	return "Wendy's — order a cheeseburger — FREE"


func use() -> void:
	entity.request_use()


func _serve(player: Player) -> bool:
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	return hand != null and hand.inventory().collect("wendys_burger")
