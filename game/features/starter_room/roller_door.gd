class_name GarageRollerDoor
extends Node3D
## Shared motor shutter with stop control and automatic obstruction reversal.

const HEIGHT := 3.2
const SPEED := .8
@export var net_height := 0.0
@export var net_target := 0.0
var _material: ShaderMaterial
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var leaf: Node3D = $Leaf


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _toggle, .3)
	_material = ($Leaf/Model as MeshInstance3D).material_override.duplicate() as ShaderMaterial
	($Leaf/Model as MeshInstance3D).material_override = _material
	_pose()


func interaction_text() -> String:
	if moving():
		return "Roller door · stop"
	return "Roller door · open" if net_height < .01 else "Roller door · close"


func can_use(player: Player) -> bool:
	return entity.in_range(player)


func use() -> void:
	entity.request_use()


func moving() -> bool:
	return absf(net_target - net_height) > .005


func _toggle(_player: Player) -> bool:
	net_target = net_height if moving() else HEIGHT if net_height < .01 else 0.0
	return true


func _physics_process(delta: float) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.is_server():
		if net_target < net_height and obstructed():
			net_target = HEIGHT
		net_height = move_toward(net_height, net_target, SPEED * delta)
	_pose()


func obstructed() -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.8, 2.9, 1.1)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform.translated_local(Vector3(0, 1.5, 0))
	query.exclude = [($Leaf/Body as StaticBody3D).get_rid(), ($Boundary as StaticBody3D).get_rid()]
	# Opening walls sit outside this narrower clear span.
	shape.size.x = 3.8
	return not get_world_3d().direct_space_state.intersect_shape(query).is_empty()


func _pose() -> void:
	leaf.position.y = net_height
	_material.set_shader_parameter("lift_height", net_height)
