class_name ProceduralSlidingDoor
extends Node3D
## One door per joined opening. Uses the existing authoritative interaction service.

const Kit := preload("res://features/procedural_rooms/example_kit.gd")
const STEEL := preload("res://features/procedural_rooms/materials/grey.tres")
const HAZARD := preload("res://features/procedural_rooms/materials/hazard.tres")
const LIFT := preload("res://features/procedural_rooms/materials/elevator.tres")
@export var net_open := false
var _amount := 0.0
var _leaves: Array[Node3D] = []
@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"prototype_doors")
	add_to_group(&"interactables")
	for side: float in [-1.0, 1.0]:
		Kit.box(
			self,
			"Frame%s" % side,
			Vector3(0.16, 3.15, 0.24),
			Vector3(side * 1.58, 1.575, 0),
			HAZARD
		)
		var leaf := Node3D.new()
		leaf.name = "Leaf%s" % side
		add_child(leaf)
		Kit.box(leaf, "Panel", Vector3(1.49, 2.98, 0.14), Vector3(0, 1.49, 0), STEEL)
		Kit.box(leaf, "Stripe", Vector3(1.49, 0.18, 0.015), Vector3(0, 0.75, -0.08), HAZARD, false)
		Kit.box(leaf, "Window", Vector3(0.68, 0.5, 0.015), Vector3(0, 2.25, -0.08), LIFT, false)
		_leaves.append(leaf)
	Kit.box(self, "Track", Vector3(3.32, 0.16, 0.24), Vector3(0, 3.08, 0), HAZARD)
	entity.register_use(_can_use, _toggle, 0.45)
	entity.session_reset.connect(_reset)
	_update_leaves()


func _physics_process(delta: float) -> void:
	if not net_open and _amount > 0 and multiplayer.is_server() and occupied():
		net_open = true
	_amount = move_toward(_amount, 1.0 if net_open else 0.0, delta / 0.35)
	_update_leaves()


func _update_leaves() -> void:
	for index: int in _leaves.size():
		_leaves[index].position.x = (-1.0 if index == 0 else 1.0) * (0.75 + _amount * 1.65)


func occupied() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		var point := to_local(player.net_position)
		if absf(point.x) < 1.95 and absf(point.z) < 0.75 and point.y > -0.5 and point.y < 3.9:
			return true
	return false


func _can_use(player: Player) -> bool:
	return entity.in_range(player) and (not net_open or not occupied())


func _toggle(_player: Player) -> bool:
	net_open = not net_open
	return true


func use() -> void:
	entity.request_use()


func can_use(player: Player) -> bool:
	return _can_use(player)


func interaction_text() -> String:
	return "Close garage door" if net_open else "Open garage door"


func _reset(_mode: Network.Mode) -> void:
	net_open = false
	_amount = 0
	_update_leaves()
