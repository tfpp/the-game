class_name DrinkSpot
extends Node3D
## One counter or tabletop spot the server keeps stocked with a random drink.
## Use (E / B / Circle / touch USE) collects it into the hand or backpack through
## the ordinary inventory; the spot refills with another random drink later.

## Catalog ID currently standing here, or "" while empty. Replicated on change.
@export var net_item := ""

var _restock_in := 0.0
var _shown := "-"
var _rng := RandomNumberGenerator.new()

@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var _mount: Node3D = $Mount


func _ready() -> void:
	add_to_group(&"booze_spots")
	_rng.randomize()
	entity.register_use(can_use, _collect)
	entity.session_reset.connect(_reset)
	_show(net_item)


func _process(delta: float) -> void:
	if net_item != _shown:
		_show(net_item)
	if multiplayer.is_server() and net_item.is_empty():
		_restock_in -= delta
		if _restock_in <= 0.0:
			restock()


## Server: put a new random drink here.
func restock() -> void:
	if multiplayer.is_server():
		net_item = BoozeRules.pick_drink(_rng.randf())


func can_use(player: Player) -> bool:
	if net_item.is_empty() or not entity.in_range(player):
		return false
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	return hand != null and hand.inventory().can_collect(net_item)


func interaction_text() -> String:
	return ItemCatalog.pickup_text(net_item)


func use() -> void:
	entity.request_use()


func _collect(player: Player) -> bool:
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	if net_item.is_empty() or hand == null or not hand.inventory().collect(net_item):
		return false
	net_item = ""
	_restock_in = BoozeRules.restock_delay(_rng.randf())
	return true


func _reset(_mode: Network.Mode) -> void:
	restock()


func _show(id: String) -> void:
	_shown = id
	for child: Node in _mount.get_children():
		_mount.remove_child(child)
		child.queue_free()
	var definition := ItemCatalog.find(id)
	if definition != null:
		_mount.add_child(ItemCatalog.create_view(id))
		_mount.position.y = definition.ground_clearance
		add_to_group(&"interactables")
	else:
		remove_from_group(&"interactables")
