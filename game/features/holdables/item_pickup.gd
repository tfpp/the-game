class_name ItemPickup
extends Node3D
## A generic world pickup for any ItemDefinition (see item_catalog.gd). Reuses the
## existing "Use" interaction (features/interaction): E, or the controller's B/Circle,
## adds the item to equipment or the backpack.

const PICKUP_RANGE := 2.5

## Which ItemCatalog entry this pickup offers. Set per-instance in feature.tscn.
@export var item_id := ""

## Replicated (server -> everyone): once taken, the pickup disappears for good.
@export var net_taken := false

var _last_taken := false

@onready var _mount: Node3D = $Mount


func _ready() -> void:
	var def := ItemCatalog.find(item_id)
	if def != null:
		_mount.add_child(ItemCatalog.create_view(item_id))
	_apply_taken(net_taken)


func _process(_delta: float) -> void:
	if net_taken != _last_taken:
		_apply_taken(net_taken)


func can_use(player: Player) -> bool:
	if net_taken or global_position.distance_to(player.global_position) > PICKUP_RANGE:
		return false
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	return hand != null and hand.inventory().can_collect(item_id)


func interaction_text() -> String:
	var def := ItemCatalog.find(item_id)
	return "Pick up %s" % (def.display_name if def != null else item_id)


func use() -> void:
	request_pickup.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	if not multiplayer.is_server() or net_taken:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	var hand := Hand.for_peer(get_tree(), peer_id)
	if hand == null or not hand.inventory().collect(item_id):
		return
	net_taken = true


func _apply_taken(taken: bool) -> void:
	_last_taken = taken
	visible = not taken
	if taken:
		remove_from_group(&"interactables")
	else:
		add_to_group(&"interactables")


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
