class_name ThrownItem
extends Node3D
## A generic thrown prop: arcs from `from` to a landing point, then sits there as a new
## pickup so anyone can grab it again — the same PROP item, just back on the ground.
## Spawned by the holdables feature (holdables.gd) when a PROP-category item's primary
## action fires (see hand.gd's `_throw`).
##
## Server-authoritative flight, like frogs/frog.gd: the server integrates the arc and
## publishes `net_position`/`net_landed`; other peers only smooth toward them.

const FLIGHT_DURATION_S := 0.6
const REMOTE_SMOOTHING := 16.0
const PICKUP_RANGE := 2.5

## Replicated (server -> everyone). See the synchronizer config in thrown_item.tscn.
@export var net_position := Vector3.ZERO
@export var net_landed := false

## Set from spawn data (see holdables.gd), identically on every peer, before this node
## enters the tree, so they don't need their own synchronizer properties.
var item_id := ""
var from := Vector3.ZERO
var to := Vector3.ZERO

var _elapsed := 0.0
var _last_landed := false

@onready var _mount: Node3D = $Mount


func _ready() -> void:
	position = from
	net_position = from
	var def := ItemCatalog.find(item_id)
	if def != null and def.view_scene != null:
		_mount.add_child(def.view_scene.instantiate())
	if not multiplayer.is_server():
		set_physics_process(false)
	_apply_landed(net_landed)


func _physics_process(delta: float) -> void:
	if net_landed:
		return
	_elapsed += delta
	var t := _elapsed / FLIGHT_DURATION_S
	if t >= 1.0:
		net_position = to
		net_landed = true
	else:
		net_position = ThrowMath.arc_position(from, to, t)


func _process(delta: float) -> void:
	if net_landed != _last_landed:
		_apply_landed(net_landed)
	if multiplayer.is_server():
		position = net_position
		return
	var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	position = position.lerp(net_position, t)


func can_use(player: Player) -> bool:
	if not net_landed or global_position.distance_to(player.global_position) > PICKUP_RANGE:
		return false
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	return hand != null and hand.net_item_id.is_empty()


func interaction_text() -> String:
	var def := ItemCatalog.find(item_id)
	return "Pick up %s" % (def.display_name if def != null else item_id)


func use() -> void:
	request_pickup.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	if not multiplayer.is_server() or not net_landed:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	var hand := Hand.for_peer(get_tree(), peer_id)
	if hand == null or not hand.try_equip(item_id):
		return
	queue_free()


func _apply_landed(landed: bool) -> void:
	_last_landed = landed
	if landed:
		add_to_group(&"interactables")
	else:
		remove_from_group(&"interactables")


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
