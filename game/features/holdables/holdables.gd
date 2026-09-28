extends Node3D
## Generic item-in-hand system: pickups (item_pickup.gd) hand items to hands
## (hand.gd) through the existing Use interaction, and a hand's primary action
## fires/eats/throws depending on the held item's ItemDefinition.Category. New items
## are just a `.tres` + view scene (see item_catalog.gd) and a pickup placed below —
## no new code. See README.md.
##
## Server-authoritative spawning like core/game/game.gd's players and
## features/frogs/frogs.gd's frogs: the server spawns a Hand per connected peer (so
## everyone, including late joiners, sees the same replicated node) and a ThrownItem
## whenever a PROP item is thrown.

const HAND_SCENE := preload("res://features/holdables/hand.tscn")
const THROWN_ITEM_SCENE := preload("res://features/holdables/thrown_item.tscn")

var _next_thrown_id := 0

@onready var _hands: Node3D = $Hands
@onready var _hand_spawner: MultiplayerSpawner = $HandSpawner
@onready var _thrown: Node3D = $Thrown
@onready var _thrown_spawner: MultiplayerSpawner = $ThrownSpawner


func _ready() -> void:
	add_to_group(&"holdables_root")
	_hand_spawner.spawn_function = _spawn_hand
	_thrown_spawner.spawn_function = _spawn_thrown_item
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)


## Server: called by a Hand (hand.gd's `_throw`) when a PROP item is thrown.
func spawn_thrown_item(item_id: String, from: Vector3, to: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_next_thrown_id += 1
	_thrown_spawner.spawn({"id": _next_thrown_id, "item_id": item_id, "from": from, "to": to})


func _on_mode_changed(_mode: Network.Mode) -> void:
	_clear(_hands)
	_clear(_thrown)
	if Network.is_authoritative():
		_hand_spawner.spawn(_hand_data(multiplayer.get_unique_id()))


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_hand_spawner.spawn(_hand_data(peer_id))


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var node := _hands.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


## Runs on every peer (spawn_function), so authority is set identically everywhere.
func _spawn_hand(data: Variant) -> Node:
	var info := data as Dictionary
	var peer_id: int = info["peer"]
	var hand := HAND_SCENE.instantiate() as Hand
	hand.name = str(peer_id)
	hand.peer_id = peer_id
	hand.skin_index = int(info.get("skin_index", PlayerSkin.index_for_id(peer_id)))
	return hand


func _spawn_thrown_item(data: Variant) -> Node:
	var info := data as Dictionary
	var item := THROWN_ITEM_SCENE.instantiate() as ThrownItem
	item.name = "Thrown%d" % int(info["id"])
	item.item_id = info["item_id"]
	item.from = info["from"]
	item.to = info["to"]
	return item


func _clear(container: Node3D) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _hand_data(peer_id: int) -> Dictionary:
	var account: Dictionary = Network.peer_accounts.get(peer_id, {})
	var account_id := int(account.get("account_id", 0))
	var identity := account_id if account_id > 0 else peer_id
	return {"peer": peer_id, "skin_index": PlayerSkin.index_for_id(identity)}
