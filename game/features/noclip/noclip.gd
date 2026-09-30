extends Node
## Local flight gated by a server-owned, replicated cheat switch.

const TOGGLE_ACTION := &"toggle_noclip"
## Multiple of the player's normal ground speed while noclipping.
const SPEED_MULTIPLIER := 2.5

@export var cheats_enabled := false

var _active := false
var _flying_player: Player
var _return_position := Vector3.ZERO
var _last_position := Vector3.ZERO


func _ready() -> void:
	Controls.ensure_action(TOGGLE_ACTION, [_key_event(KEY_N)])
	add_to_group(&"noclip")
	Network.mode_changed.connect(_reset)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(TOGGLE_ACTION) or not Controls.gameplay_active():
		return
	get_viewport().set_input_as_handled()
	toggle()


func _physics_process(delta: float) -> void:
	if (
		_active
		and (
			not is_instance_valid(_flying_player)
			or not cheats_enabled
			or _local_player() != _flying_player
		)
	):
		_stop()
	if not _active:
		return
	if not _flying_player.global_position.is_equal_approx(_last_position):
		_stop(false)  # A respawn or room teleport ends flight at its new destination.
		return
	var player := _local_player()
	if player == null:
		_active = false
		return
	var look := Controls.consume_look(delta)
	player.yaw -= look.x
	player.pitch = clampf(player.pitch - look.y, deg_to_rad(-89.0), deg_to_rad(89.0))
	Controls.consume_jump()  # no bunny-hopping while flying
	var wish := fly_direction(player.yaw, player.pitch, Controls.movement())
	var speed := player.movement.max_speed_m() * SPEED_MULTIPLIER
	player.global_position += wish * speed * delta
	_last_position = player.global_position
	player.net_position = player.global_position
	player.velocity = Vector3.ZERO
	player.net_velocity = Vector3.ZERO


## A normalized fly direction from view angles and a 2D input (x = strafe right,
## y = move back, like Controls.movement()). Pitch tilts the forward axis, so looking
## up or down flies that way too, the way Source's noclip cheat behaves.
static func fly_direction(yaw: float, pitch: float, input: Vector2) -> Vector3:
	if input.is_zero_approx():
		return Vector3.ZERO
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var forward := basis * Vector3(0.0, 0.0, -1.0)
	var right := basis * Vector3(1.0, 0.0, 0.0)
	return (forward * -input.y + right * input.x).normalized()


func _set_active(player: Player, active: bool) -> void:
	if active == _active:
		return
	_active = active
	if active:
		_flying_player = player
		_return_position = player.global_position
		_last_position = player.global_position
	player.set_physics_process(not active)
	var collider := player.get_node_or_null("Collider") as CollisionShape3D
	if collider:
		collider.disabled = active
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


func _local_player() -> Player:
	return get_tree().get_first_node_in_group(&"local_player") as Player


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


func toggle() -> String:
	if not cheats_enabled:
		return "Noclip requires sv_cheats 1."
	var player := _local_player()
	if player == null:
		return "Join a game first."
	_set_active(player, not _active)
	return "noclip %d" % int(_active)


@rpc("any_peer", "call_local", "reliable")
func request_cheats(value: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	apply_cheats(sender, value)


func apply_cheats(sender: int, value: int) -> bool:
	if not multiplayer.is_server() or value not in [0, 1]:
		return false
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node is Player and node.name == str(sender) and not node.is_queued_for_deletion():
			cheats_enabled = value == 1
			return true
	return false


func _stop(restore_position: bool = true) -> void:
	if is_instance_valid(_flying_player):
		# Revocation must not leave someone trapped in a wall.
		if restore_position:
			_flying_player.global_position = _return_position
			_flying_player.net_position = _return_position
		_set_active(_flying_player, false)
	_active = false
	_flying_player = null


func _reset(_mode: Network.Mode) -> void:
	_stop()
	cheats_enabled = false
