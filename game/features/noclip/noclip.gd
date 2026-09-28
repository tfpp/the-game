extends Node
## Lets any player toggle noclip (no collision, free fly) by pressing V.
##
## Player movement is already client-authoritative (see game/AGENTS.md), so this only
## ever drives the local player's own node; nothing here needs the server involved.

const TOGGLE_ACTION := &"toggle_noclip"
## Multiple of the player's normal ground speed while noclipping.
const SPEED_MULTIPLIER := 2.5

var _active := false


func _ready() -> void:
	Controls.ensure_action(TOGGLE_ACTION, [_key_event(KEY_V)])


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(TOGGLE_ACTION) or not Controls.gameplay_active():
		return
	var player := _local_player()
	if player == null:
		return
	get_viewport().set_input_as_handled()
	_set_active(player, not _active)


func _physics_process(delta: float) -> void:
	if not _active:
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
