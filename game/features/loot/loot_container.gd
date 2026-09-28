class_name LootContainer
extends Node3D
## A generic searchable object (car, dumpster, locker, crate...). Use it once to
## search: the server rolls `loot_table` and hands out whatever fits in the
## searcher's inventory. Leftovers stay inside for anyone to take with Use.
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


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"interactables")


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
	return global_position.distance_to(player.global_position) <= search_range


func interaction_text() -> String:
	if not net_searched:
		return "Search %s" % noun
	if net_contents.is_empty():
		return "Searched %s (empty)" % noun
	var def := ItemCatalog.find(net_contents[0])
	return "Take %s (%d left)" % [def.display_name if def != null else "item", net_contents.size()]


func use() -> void:
	if not net_searched or not net_contents.is_empty():
		request_search.rpc_id(1)


## Searches an unsearched container, or takes leftovers from a searched one.
## Claims run on the server one at a time, so an item can only be taken once.
@rpc("any_peer", "call_local", "reliable")
func request_search() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	var hand := Hand.for_peer(get_tree(), peer_id)
	if player == null or hand == null or not can_use(player):
		return
	if not net_searched:
		regenerate()
	var left := PackedStringArray()
	for id: String in net_contents:
		if not hand.inventory().collect(id):
			left.append(id)
	if left != net_contents:
		net_contents = left


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
