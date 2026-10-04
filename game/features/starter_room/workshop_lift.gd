class_name WorkshopLift
extends Node3D
## Server-owned shared service lift. Arms and van use the same replicated height.

const MAX_HEIGHT := 1.95
const SPEED := .65
const EPSILON := .005
@export var van_path: NodePath
@export var net_height := 0.0
@export var net_target_height := 0.0
@export var net_obstructed := false
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var van: OperationsVan = get_node(van_path)
@onready var arms: Node3D = $Arms


func _ready() -> void:
	$Control.add_to_group(&"interactables")
	van.workshop_lift = self
	entity.register_use(can_use, _toggle, .25)
	entity.session_reset.connect(_reset)
	_apply_pose()


func _physics_process(delta: float) -> void:
	if (
		multiplayer.multiplayer_peer == null
		or (
			multiplayer.multiplayer_peer.get_connection_status()
			!= MultiplayerPeer.CONNECTION_CONNECTED
		)
	):
		return
	if multiplayer.is_server():
		if net_target_height < net_height and _bay_occupied():
			net_target_height = net_height
			net_obstructed = true
		net_height = move_toward(net_height, net_target_height, SPEED * delta)
	_apply_pose()


func grounded() -> bool:
	return net_height <= EPSILON and net_target_height <= EPSILON


func moving() -> bool:
	return absf(net_height - net_target_height) > EPSILON


func interaction_text() -> String:
	if moving():
		return "Workshop lift · stop"
	if net_obstructed:
		return "Workshop lift · clear bay to lower"
	return "Workshop lift · raise van" if grounded() else "Workshop lift · lower van"


func can_use(player: Player) -> bool:
	return entity.in_range(player) and not van.has_pending_trips()


func use() -> void:
	entity.request_use()


func _toggle(_player: Player) -> bool:
	if moving():
		net_target_height = net_height
		net_obstructed = false
		return true
	var target := MAX_HEIGHT if grounded() else 0.0
	if target < net_height and _bay_occupied():
		net_obstructed = true
		return false
	net_obstructed = false
	net_target_height = target
	return true


func _bay_occupied() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		var at := to_local(player.net_position)
		# Include capsule radius around the van, wheels and support-arm sweep.
		if (
			absf(at.x) < 2.25
			and at.z > -2.95
			and at.z < 2.95
			and at.y < net_height + 2.0
			and at.y > -.5
		):
			return true
	return false


func _apply_pose() -> void:
	arms.position.y = net_height
	(van.get_node("Model") as Node3D).position.y = net_height
	(van.get_node("RouteMap") as Node3D).position.y = 1.3 + net_height
	(van.get_node("Stash") as Node3D).position.y = 1.05 + net_height


func _reset(_mode: Network.Mode) -> void:
	# Preserve a raised pose instead of lowering onto newly connected players.
	net_target_height = net_height
	net_obstructed = false
