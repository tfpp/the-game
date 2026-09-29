class_name LootContainer
extends Node3D
## A generic searchable object (car, dumpster, locker, crate...). Use opens a
## stash menu. The server rolls contents once; each drag claims one item into a
## chosen backpack slot. Other players see the same remaining contents.
## A searched container stays searched until `reset()`, which lets the next
## search roll fresh loot.

const GROUP := &"loot_containers"

@export var loot_table: LootTable
## Shown in the prompt: "Search <noun>".
@export var noun := "container"
@export var search_range := 3.0

## Replicated (server -> everyone).
@export var net_searched := false
@export var net_contents := PackedStringArray()

## Server-only randomness; tests may replace it with a seeded generator.
var rng := RandomNumberGenerator.new()

@onready var _entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"interactables")
	_entity.interaction_range = search_range
	_entity.register_use(can_use, _search)
	_entity.register_action(&"take", _validate_take, _take)


## Server-only: every container under `tree` becomes unsearched, so the next
## search rerolls its loot. For slum travel between visits.
static func reset_all(tree: SceneTree) -> void:
	for node: Node in tree.get_nodes_in_group(GROUP):
		(node as LootContainer).reset()


## Server-only: forgets the search and any leftover loot.
func reset() -> void:
	if not multiplayer.is_server():
		return
	net_searched = false
	net_contents = PackedStringArray()


## Server-only: rolls new contents right away and marks the container searched.
func regenerate() -> void:
	if not multiplayer.is_server():
		return
	net_contents = loot_table.roll(rng) if loot_table != null else PackedStringArray()
	net_searched = true


func can_use(player: Player) -> bool:
	return _entity.in_range(player)


func interaction_text() -> String:
	if not net_searched:
		return "Search %s" % noun
	if net_contents.is_empty():
		return "Searched %s (empty)" % noun
	return "Open %s stash (%d items)" % [noun, net_contents.size()]


func use() -> void:
	request_search()
	var screen := get_tree().get_first_node_in_group(&"inventory_screen")
	if screen != null:
		screen.call("open_stash", self)


## Searching reveals contents. It does not automatically collect them.
func request_search() -> void:
	_entity.request_use()


func _search(_player: Player) -> bool:
	if not net_searched:
		regenerate()
	return true


## The expected ID prevents a stale drag index from taking a different item
## after another player removes one from this shared stash.
func request_take(index: int, backpack_slot: int, expected_id: String) -> void:
	_entity.request_action(&"take", {"index": index, "slot": backpack_slot, "id": expected_id})


func _validate_take(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 3:
		return false
	if not payload.has_all(["index", "slot", "id"]):
		return false
	if (
		typeof(payload["index"]) != TYPE_INT
		or typeof(payload["slot"]) != TYPE_INT
		or typeof(payload["id"]) != TYPE_STRING
	):
		return false
	var player := _entity.player_for_peer(peer)
	var hand := Hand.for_peer(get_tree(), peer)
	if not _entity.in_range(player) or hand == null or not net_searched:
		return false
	var index: int = payload["index"]
	var slot: int = payload["slot"]
	var id: String = payload["id"]
	return (
		index >= 0
		and index < net_contents.size()
		and net_contents[index] == id
		and slot >= 0
		and slot < PlayerInventory.CAPACITY
		and hand.inventory().backpack[slot].is_empty()
	)


func _take(peer: int, payload: Dictionary) -> bool:
	var index: int = payload["index"]
	var slot: int = payload["slot"]
	var id: String = payload["id"]
	var hand := Hand.for_peer(get_tree(), peer)
	if hand == null or not hand.inventory().collect_into_slot(id, slot):
		return false
	var remaining := net_contents.duplicate()
	remaining.remove_at(index)
	net_contents = remaining
	return true
