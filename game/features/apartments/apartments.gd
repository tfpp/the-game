class_name Apartments
extends Node3D
## The server owns reservations; public peer-to-unit assignments contain no account IDs.

const FLOOR_SCENE := preload("res://features/apartments/floor.tscn")
const UNITS_PER_FLOOR := 10

@export var assignments: Dictionary = {}
var _reservations: Dictionary = {}

@onready var floors: Node3D = $Floors
@onready var _spawner: MultiplayerSpawner = $Spawner


func _ready() -> void:
	add_to_group(&"apartments")
	_spawner.spawn_function = _spawn_floor
	Network.mode_changed.connect(_reset)
	multiplayer.peer_disconnected.connect(_disconnected)


static func floor_number(unit: int) -> int:
	return (unit - 1) / UNITS_PER_FLOOR + 1


static func unit_label(unit: int) -> String:
	return "%d%02d" % [floor_number(unit), (unit - 1) % UNITS_PER_FLOOR + 1]


func unit_for(peer: int) -> int:
	return int(assignments.get(peer, 0))


func floor_for(peer: int) -> StreamedRoom:
	var unit := unit_for(peer)
	if unit == 0:
		return null
	return floors.get_node_or_null("Floor%d" % floor_number(unit)) as StreamedRoom


## A unit's room in its floor's local space, matching `interior.gd`: five rooms each
## side of the corridor, 6 m wide, from the doorway wall (z ±2) to the window (z ±9).
static func unit_bounds(unit: int) -> AABB:
	var slot := (unit - 1) % UNITS_PER_FLOOR
	var x := -12.0 + (slot % 5) * 6.0
	var near := -9.0 if slot < 5 else 2.0
	return AABB(Vector3(x - 3.0, -0.5, near), Vector3(6.0, 4.0, 7.0))


## True when `global_point` is inside `peer`'s assigned unit (not just on its floor).
func in_unit(peer: int, global_point: Vector3) -> bool:
	var floor_node := floor_for(peer)
	return (
		floor_node != null
		and unit_bounds(unit_for(peer)).has_point(floor_node.to_local(global_point))
	)


## No peer or unit is accepted from the client. Calls are serialized on the server.
func claim(peer: int) -> int:
	if not multiplayer.is_server():
		return 0
	var player := player_for(peer)
	var desk := get_node("Lobby/Desk") as Node3D
	if player == null or player.net_position.distance_to(desk.global_position) > 2.5:
		return 0
	var key := _resident_key(peer)
	if not _reservations.has(key):
		var unit := 1
		while _reservations.values().has(unit):
			unit += 1
		_reservations[key] = unit
	var assigned := int(_reservations[key])
	while floors.get_child_count() < floor_number(assigned):
		_spawner.spawn(floors.get_child_count() + 1)
	var next := assignments.duplicate()
	next[peer] = assigned
	assignments = next
	return assigned


func player_for(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer:
			return player
	return null


func _resident_key(peer: int) -> String:
	var account: Dictionary = Network.peer_accounts.get(peer, {})
	var id := int(account.get("account_id", 0))
	return "account:%d" % id if id > 0 else "guest:%d" % peer


func _spawn_floor(data: Variant) -> Node:
	var number := int(data)
	var floor_node := FLOOR_SCENE.instantiate() as StreamedRoom
	floor_node.name = "Floor%d" % number
	floor_node.position = Vector3(200, number * 6, 1200)
	floor_node.set_meta(&"floor_number", number)
	return floor_node


func _disconnected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	_reservations.erase("guest:%d" % peer)
	var next := assignments.duplicate()
	next.erase(peer)
	assignments = next
	# Keep existing floors so other occupants never lose their floor or return route.


func _reset(_mode: Network.Mode) -> void:
	assignments = {}
	_reservations.clear()
	for child: Node in floors.get_children():
		floors.remove_child(child)
		child.queue_free()
