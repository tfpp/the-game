class_name ThrownItem
extends Node3D
## A generic thrown or dropped item: arcs from `from` to a landing point, then bounces
## a few times — fewer and lower the heavier the item is (see throw_math.gd's
## `bounce_height`) — before settling as a new pickup so anyone can grab it again, the
## same item just back on the ground. Spawned by the holdables feature (holdables.gd)
## when a PROP item is thrown or any held item is dropped (see hand.gd's `_toss`).
##
## Server-authoritative flight, like frogs/frog.gd: the server integrates the arc and
## publishes `net_position`/`net_landed`; other peers only smooth toward them.

const FLIGHT_DURATION_S := 0.6
const BOUNCE_DURATION_S := 0.3
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
var instance_id := -1

var _elapsed := 0.0
var _last_landed := false

## The flight segment currently being animated: the initial throw arc, then each
## successive (shorter, lower) bounce.
var _seg_from := Vector3.ZERO
var _seg_to := Vector3.ZERO
var _seg_height := ThrowMath.ARC_HEIGHT
var _seg_duration := FLIGHT_DURATION_S
var _bounce_index := 0

@onready var _mount: Node3D = $Mount
@onready var _entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	($Sync as MultiplayerSynchronizer).add_visibility_filter(network_peer_allowed)
	($Sync as MultiplayerSynchronizer).update_visibility()
	_entity.register_use(can_use, _collect)
	position = from
	net_position = from
	_seg_from = from
	_seg_to = to
	var def := ItemCatalog.find(item_id)
	if def != null:
		_mount.add_child(ItemCatalog.create_view(item_id))
		_mount.position.y = def.ground_clearance
	if not multiplayer.is_server():
		set_physics_process(false)
	_apply_landed(net_landed)


func _physics_process(delta: float) -> void:
	if not net_landed:
		_advance(delta)


func _advance(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / _seg_duration
	if t >= 1.0:
		_advance_segment()
	else:
		net_position = ThrowMath.arc_position(_seg_from, _seg_to, t, _seg_height)


## The current segment finished: start the next, smaller bounce, or settle for good
## once this item's weight says it wouldn't bounce meaningfully higher.
func _advance_segment() -> void:
	net_position = _seg_to
	var height := ThrowMath.bounce_height(_weight(), _bounce_index)
	if height < ThrowMath.MIN_BOUNCE_HEIGHT:
		net_landed = true
		return
	var direction := _seg_to - _seg_from
	direction.y = 0.0
	direction = Vector3.FORWARD if direction.is_zero_approx() else direction.normalized()
	var flat := _seg_to + direction * ThrowMath.bounce_distance(_bounce_index)
	_seg_from = _seg_to
	_seg_to = _floor_point(flat)
	_seg_height = height
	_seg_duration = BOUNCE_DURATION_S
	_elapsed = 0.0
	_bounce_index += 1


func _weight() -> float:
	var def := ItemCatalog.find(item_id)
	return def.weight if def != null else 1.0


## Snaps a bounce's flat target down to the floor beneath it, the same way hand.gd's
## `_landing_point` finds the original throw's landing spot.
func _floor_point(flat: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		flat + Vector3.UP * 10.0, flat + Vector3.DOWN * 10.0
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else flat


func _process(delta: float) -> void:
	if net_landed != _last_landed:
		_apply_landed(net_landed)
	if multiplayer.is_server():
		position = net_position
		return
	var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	position = position.lerp(net_position, t)


func can_use(player: Player) -> bool:
	if (
		not net_landed
		or is_queued_for_deletion()
		or not network_peer_allowed(player.get_multiplayer_authority())
		or global_position.distance_to(player.global_position) > PICKUP_RANGE
	):
		return false
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	return hand != null and hand.inventory().can_collect(item_id)


func interaction_text() -> String:
	return ItemCatalog.pickup_text(item_id)


func interaction_color() -> Color:
	return ItemCatalog.item_color(item_id)


func use() -> void:
	_entity.request_use()


@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	_entity.receive_legacy_action(&"use")


func network_peer_allowed(peer: int) -> bool:
	for service: Node in get_tree().get_nodes_in_group(&"zone_instances"):
		if service.multiplayer == multiplayer:
			return bool(service.call("can_observe_zone", instance_id, peer))
	return instance_id == -1 or peer == MultiplayerPeer.TARGET_PEER_SERVER


func _collect(player: Player) -> bool:
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	if hand == null or not hand.inventory().collect(item_id):
		return false
	queue_free()
	return true


func _apply_landed(landed: bool) -> void:
	_last_landed = landed
	if landed:
		add_to_group(&"interactables")
	else:
		remove_from_group(&"interactables")
