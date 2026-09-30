class_name Crouch
extends Node
## Toggle crouching (C / right-stick click). The owning client applies its own
## slower speed, lower eyes and shorter capsule at once, like the rest of its
## client-authoritative movement, and asks the server to publish the state so
## everyone sees the crouch pose and garage enemies notice the player later.
## Read other peers' state with `is_crouching(peer)` (group `crouching`).

const ACTION := &"crouch"
## Crouch-walking speed as a fraction of normal speed (Source ducks at 1/3).
const SPEED_SCALE := 0.34
## Crouched collision capsule height as a fraction of standing height.
const HEIGHT_SCALE := 0.72
## Crouched eye height, in Source units above the hull bottom (standing is 64).
const EYE_HEIGHT := 46.0
## How quickly the camera lowers and rises (per second, exponential).
const EYE_SPEED := 14.0
## Fraction of an enemy's usual noticing distance at which a crouched player is seen.
const NOTICE_SCALE := 0.5

## Replicated (server -> everyone): peer id -> true for crouching players.
@export var crouched: Dictionary = {}

var _local_crouched := false
var _player: Player
var _standing_eye := 64.0

@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"crouching")
	entity.register_action(ACTION, _valid_crouch, _apply_crouch)
	entity.session_reset.connect(func(_mode: Network.Mode) -> void: crouched = {})
	multiplayer.peer_disconnected.connect(_remove_peer)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_STICK
	Controls.ensure_action(ACTION, [key, pad])


func _unhandled_input(event: InputEvent) -> void:
	if (
		not event.is_action_pressed(ACTION)
		or event.is_echo()
		or not Controls.gameplay_active()
		or _player == null
	):
		return
	if _seated():
		return
	get_viewport().set_input_as_handled()
	set_crouched(not _local_crouched)


## Whether `peer` is crouching. Your own state is predicted locally; everyone
## else's comes from the server.
func is_crouching(peer: int) -> bool:
	if is_instance_valid(_player) and peer == _player.get_multiplayer_authority():
		return _local_crouched
	return bool(crouched.get(peer, false))


## Local player only. Standing up is refused while something is overhead.
func set_crouched(value: bool) -> bool:
	if not is_instance_valid(_player) or value == _local_crouched:
		return false
	if not value and blocked_overhead(_player):
		return false
	_local_crouched = value
	_apply_speed(_player, value)
	entity.request_action(ACTION, {"crouched": value})
	return true


func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player != _player:
		_adopt(player)
	if not is_instance_valid(_player):
		return
	var target := EYE_HEIGHT if _local_crouched else _standing_eye
	var t := 1.0 - exp(-EYE_SPEED * delta)
	_player.movement.eye_height = lerpf(_player.movement.eye_height, target, t)


## A new local player (join or respawn) always starts standing.
func _adopt(player: Player) -> void:
	if is_instance_valid(_player):
		if _local_crouched:
			_apply_speed(_player, false)
		_player.movement.eye_height = _standing_eye
	var was_crouched := _local_crouched
	_local_crouched = false
	_player = player
	if player == null:
		return
	# Each player must own its resource; never modify the scene's shared default.
	player.movement = player.movement.duplicate() as MovementConfig
	_standing_eye = player.movement.eye_height
	if was_crouched:
		entity.request_action(ACTION, {"crouched": false})


## Ratio changes compose with other speed modifiers such as the gnome tunnels.
static func _apply_speed(player: Player, value: bool) -> void:
	var scale := SPEED_SCALE if value else 1.0 / SPEED_SCALE
	player.movement.max_speed *= scale


## True when a standing capsule would not fit above the crouched player's feet.
static func blocked_overhead(player: Player) -> bool:
	var collider := player.get_node_or_null("Collider") as CollisionShape3D
	var capsule := collider.shape as CapsuleShape3D if collider else null
	if capsule == null or not player.is_inside_tree():
		return false
	var standing := capsule.height / HEIGHT_SCALE
	var bottom := collider.global_position.y - capsule.height * 0.5
	var probe := CapsuleShape3D.new()
	probe.radius = capsule.radius * 0.95
	probe.height = standing - 0.04
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(
		Basis.IDENTITY,
		Vector3(
			collider.global_position.x,
			bottom + 0.02 + probe.height * 0.5,
			collider.global_position.z
		)
	)
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	return not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _seated() -> bool:
	var seating := get_tree().get_first_node_in_group(&"seating")
	return seating != null and bool(seating.call("is_seated", _player.get_multiplayer_authority()))


func _valid_crouch(_peer: int, payload: Dictionary) -> bool:
	return payload.size() == 1 and payload.get("crouched") is bool


func _apply_crouch(peer: int, payload: Dictionary) -> bool:
	var next := crouched.duplicate()
	if bool(payload["crouched"]):
		if not _player_exists(peer):
			return false
		next[peer] = true
	else:
		next.erase(peer)
	crouched = next
	return true


func _player_exists(peer: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node.get_multiplayer_authority() == peer and not node.is_queued_for_deletion():
			return true
	return false


func _remove_peer(peer: int) -> void:
	if multiplayer.is_server() and crouched.has(peer):
		var next := crouched.duplicate()
		next.erase(peer)
		crouched = next
