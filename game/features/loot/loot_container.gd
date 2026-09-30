class_name LootContainer
extends Node3D
## A generic searchable object (car, dumpster, locker, crate...). Use opens a
## stash menu. The server rolls contents once; each drag claims one item into a
## chosen backpack slot. Other players see the same remaining contents.
## A searched container stays searched until `reset()`, which lets the next
## search roll fresh loot.

const GROUP := &"loot_containers"
const SEARCH_LEASE_MSEC := 3000

@export var loot_table: LootTable
## Shown in the prompt: "Search <noun>".
@export var noun := "container"
@export var search_range := 3.0

## Replicated (server -> everyone).
@export var net_searched := false
@export var net_contents := PackedStringArray()
## Current stash viewers, independent of whether loot was rolled previously.
@export var net_active_searchers := 0

## Server-only randomness; tests may replace it with a seeded generator.
var rng := RandomNumberGenerator.new()
var _searchers: Dictionary[int, int] = {}
var _prune_in := 0.0

@onready var _entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"interactables")
	_entity.interaction_range = search_range
	_entity.register_use(can_use, _search)
	_entity.register_action(&"take", _validate_take, _take)
	_entity.register_action(&"search_keepalive", _validate_keepalive, _keepalive)
	_entity.register_action(&"search_end", _validate_end, _end)
	_entity.session_reset.connect(_reset_search_session)
	multiplayer.peer_disconnected.connect(_forget_searcher)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _searchers.is_empty():
		return
	_prune_in -= delta
	if _prune_in > 0:
		return
	_prune_in = .25
	for peer: int in _searchers.keys():
		if (
			Time.get_ticks_msec() - _searchers[peer] > SEARCH_LEASE_MSEC
			or not _entity.in_range(_entity.player_for_peer(peer))
		):
			_forget_searcher(peer)


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
	_clear_searchers()


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


func _search(player: Player) -> bool:
	if not net_searched:
		regenerate()
	var peer := player.get_multiplayer_authority()
	# A player can only actively view one stash at a time.
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node != self:
			(node as LootContainer)._forget_searcher(peer)
	_searchers[peer] = Time.get_ticks_msec()
	net_active_searchers = _searchers.size()
	return true


func request_keep_searching() -> void:
	_entity.request_action(&"search_keepalive")


func request_stop_searching() -> void:
	_entity.request_action(&"search_end")


func _validate_keepalive(peer: int, payload: Dictionary) -> bool:
	return (
		payload.is_empty()
		and _searchers.has(peer)
		and _entity.in_range(_entity.player_for_peer(peer))
	)


func _keepalive(peer: int, _payload: Dictionary) -> bool:
	_searchers[peer] = Time.get_ticks_msec()
	return true


func _validate_end(_peer: int, payload: Dictionary) -> bool:
	return payload.is_empty()


func _end(peer: int, _payload: Dictionary) -> bool:
	_forget_searcher(peer)
	return true


func _forget_searcher(peer: int) -> void:
	if not multiplayer.is_server():
		return
	_searchers.erase(peer)
	net_active_searchers = _searchers.size()


func _clear_searchers() -> void:
	_searchers.clear()
	net_active_searchers = 0


func _reset_search_session(_mode: Network.Mode) -> void:
	_clear_searchers()


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
