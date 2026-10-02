class_name ItemPickup
extends Node3D
## A generic world pickup for any ItemDefinition (see item_catalog.gd). Reuses the
## existing "Use" interaction (features/interaction): E, or the controller's B/Circle,
## adds the item to equipment or the backpack.

const PICKUP_RANGE := NetworkedInteraction.DEFAULT_RANGE

## Which ItemCatalog entry this pickup offers. Set per-instance in feature.tscn.
@export var item_id := ""

## Replicated (server -> everyone): once taken, the pickup disappears for good.
@export var net_taken := false

var _last_taken := false

@onready var _mount: Node3D = $Mount
@onready var _entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	var def := ItemCatalog.find(item_id)
	if def != null:
		_mount.add_child(ItemCatalog.create_view(item_id))
	_apply_taken(net_taken)
	_entity.register_use(can_use, _collect)


func _process(_delta: float) -> void:
	if net_taken != _last_taken:
		_apply_taken(net_taken)


func can_use(player: Player) -> bool:
	if net_taken or not _entity.in_range(player):
		return false
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	return hand != null and hand.inventory().can_collect(item_id)


func interaction_text() -> String:
	return ItemCatalog.pickup_text(item_id)


func interaction_color() -> Color:
	return ItemCatalog.item_color(item_id)


func use() -> void:
	_entity.request_use()


## Kept for existing callers; new interactions call use() or the entity component.
@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	_entity.receive_legacy_action(&"use")


func _collect(player: Player) -> bool:
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	if hand == null or not hand.inventory().collect(item_id):
		return false
	net_taken = true
	return true


func _apply_taken(taken: bool) -> void:
	_last_taken = taken
	visible = not taken
	if taken:
		remove_from_group(&"interactables")
	else:
		add_to_group(&"interactables")
