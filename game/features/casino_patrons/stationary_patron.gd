class_name StationaryPatron
extends StaticBody3D
## Posed casino characters on the player avatar rig, with the roaming patrons'
## weapon contract.

const RESPAWN_DELAY_S := 6.0
const FINISHES := preload("res://features/casino_hub/model_materials.gd")

@export var net_alive := true:
	set(value):
		net_alive = value
		if is_node_ready():
			_present()

var _remaining := 0.0
var _collider: CollisionShape3D
var _entity: NetworkedEntity

@onready var _body: Node3D = $Body


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	add_to_group(&"killable")
	FINISHES.apply_finishes(_body)
	_collider = CollisionShape3D.new()
	_collider.name = "Hitbox"
	var bounds := _model_bounds(_body, Transform3D.IDENTITY)
	if _body.has_method(&"hitbox_bounds"):
		bounds = _body.transform * (_body.call(&"hitbox_bounds") as AABB)
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	_collider.shape = shape
	_collider.position = bounds.get_center()
	add_child(_collider)
	_entity = NetworkedEntity.new()
	_entity.name = "NetworkedEntity"
	_entity.replicated_properties = [NodePath(".:net_alive")]
	_entity.event_received.connect(_on_event)
	_entity.session_reset.connect(_reset_session)
	add_child(_entity)
	_present()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or net_alive:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		net_alive = true


## Only the server's validated weapon path calls this; no client death request exists.
func take_hit(_attacker_peer: int) -> void:
	if not _entity.is_authority() or not net_alive:
		return
	_remaining = RESPAWN_DELAY_S
	net_alive = false
	_entity.send_event(&"death")


func _present() -> void:
	_body.visible = net_alive
	_collider.set_deferred("disabled", not net_alive)


func _on_event(event: StringName, _payload: Dictionary) -> void:
	if event == &"death":
		MeshExplosion.spawn(self, _body)


func _reset_session(_mode: Network.Mode) -> void:
	_remaining = 0.0
	net_alive = true


## Fits the actual mesh bounds unless the body supplies a posed `hitbox_bounds()`.
static func _model_bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform := parent_transform * node.transform
	var bounds := AABB()
	if node is MeshInstance3D:
		bounds = transform * (node as MeshInstance3D).get_aabb()
	for child: Node in node.get_children():
		if child is Node3D:
			var child_bounds := _model_bounds(child, transform)
			if child_bounds.has_volume():
				bounds = bounds.merge(child_bounds) if bounds.has_volume() else child_bounds
	return bounds
