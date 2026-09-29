class_name SwingDoor
extends Node3D
## Always-present, server-owned door. Clients request Use; Sync includes late joiners.

enum State { CLOSED = 0, OPEN_IN = 1, OPEN_OUT = -1, LOCKED = 2 }

const SWING_SECONDS := 0.35
const Geometry := preload("res://features/world_builder/geometry.gd")
const Joinery := preload("res://features/world_builder/joinery.gd")

static var _leaf_scene: PackedScene

@export var door_label := "Door"
@export var width := 1.8
@export var height := 2.6
@export var key_id := ""
@export_enum("classic", "modern", "deco", "concrete") var kit_id := "classic"
@export var net_state: State = State.CLOSED

var _pivot: Node3D
var _last_state := -99
var _angle := 0.0
var _next_denied_sound := 0

@onready var _entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"swing_doors")
	net_state = State.CLOSED if key_id.is_empty() else State.LOCKED
	_pivot = Node3D.new()
	_pivot.name = "Hinge"
	_pivot.position.x = -width / 2 + 0.04
	add_child(_pivot)
	var leaf := (
		_leaf().instantiate() as Node3D
		if kit_id == "classic"
		else preload("res://features/room_kits/pieces.gd").door(kit_id)
	)
	leaf.scale = Vector3((width - 0.08) / 1.8, (height - 0.04) / 2.6, 1)
	_pivot.add_child(leaf)
	_entity.register_use(can_use, _toggle, SWING_SECONDS + 0.1)
	_entity.session_reset.connect(_reset)
	_entity.event_received.connect(_event)
	_apply_state(true)


func _physics_process(delta: float) -> void:
	if net_state != _last_state:
		_apply_state(false)
	_angle = move_toward(_angle, target_angle(), (PI / 2) * delta / SWING_SECONDS)
	_pivot.rotation.y = _angle


func target_angle() -> float:
	return -PI / 2 * net_state if net_state in [State.OPEN_IN, State.OPEN_OUT] else 0.0


func can_use(player: Player) -> bool:
	return _entity.in_range(player)


func interaction_text() -> String:
	return "Use door"


func use() -> void:
	request_use()


func request_use() -> void:
	_entity.request_use()


func _toggle(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	if net_state == State.LOCKED and not _has_key(peer):
		if Time.get_ticks_msec() >= _next_denied_sound:
			_next_denied_sound = Time.get_ticks_msec() + 400
			_entity.send_event(&"sound", {"cue": &"door_locked"}, peer)
		return false
	var opening := net_state in [State.CLOSED, State.LOCKED]
	var side: int = (
		(1 if to_local(player.net_position).z <= 0 else -1) if opening else int(net_state)
	)
	if _swing_occupied(side):
		return false
	if net_state == State.LOCKED:
		_entity.send_event(&"sound", {"cue": &"door_unlock"})
	net_state = (State.OPEN_IN if side == 1 else State.OPEN_OUT) if opening else State.CLOSED
	_entity.send_event(&"sound", {"cue": &"door_open" if opening else &"door_close"})
	return true


func _event(event: StringName, payload: Dictionary) -> void:
	if event != &"sound":
		return
	var cue := StringName(str(payload.get("cue", "")))
	if cue in [&"door_open", &"door_close", &"door_locked", &"door_unlock"]:
		GameAudio.play_at(self, cue, global_position + Vector3.UP * 1.2)


func _has_key(peer: int) -> bool:
	var hand := Hand.for_peer(get_tree(), peer)
	return hand != null and hand.inventory().has_key(key_id)


func _swing_occupied(side: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		var point := to_local(player.net_position)
		if point.y < -0.5 or point.y > height + 0.9:
			continue
		var offset := Vector2(point.x + width / 2 - 0.04, point.z * side)
		var radius := player.movement.hull_radius_m() + 0.1
		if offset.x >= -radius and offset.y >= -radius and offset.length() < width + radius:
			return true
	return false


func _apply_state(instant: bool) -> void:
	_last_state = net_state
	if instant:
		_angle = target_angle()
		_pivot.rotation.y = _angle


func _reset(_mode: Network.Mode) -> void:
	_next_denied_sound = 0
	net_state = State.CLOSED if key_id.is_empty() else State.LOCKED
	_apply_state(true)


static func _leaf() -> PackedScene:
	if _leaf_scene != null:
		return _leaf_scene
	var geometry := Geometry.new()
	geometry.materials = preload("res://features/world_builder/materials.gd").create("hotel")
	for material: StandardMaterial3D in geometry.materials.values():
		# Moving leaves cannot share the static room lightmap; retain readable wood grain.
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color *= Color(0.7, 0.65, 0.55, 1)
	Joinery.door(geometry, Vector3.ZERO, Basis.IDENTITY, 1.8, 2.6)
	var leaf := Node3D.new()
	leaf.name = "Leaf"
	geometry.finish(leaf)
	_leaf_scene = PackedScene.new()
	_leaf_scene.pack(leaf)
	leaf.free()
	return _leaf_scene
