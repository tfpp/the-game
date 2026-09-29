class_name ClimbableLadder
extends Node3D
## Server validates mounting; the owning player moves along the ladder and syncs normally.

const SPEED := 2.0
const TRANSITION_SECONDS := 0.3

@export var bottom_y := -5.0
@export var top_y := 1.0
@export var top_landing := Vector3(0, 1, 1.9)
@export var bottom_landing := Vector3(0, -5, -0.5)
@export var access_door: NodePath

var _player: Player
var _transition := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _exiting := false
var _previous_physics := true

@onready var _top: NetworkedInteraction = $TopUse
@onready var _bottom: NetworkedInteraction = $BottomUse


func _ready() -> void:
	add_to_group(&"interactables")
	_top.interaction_offset = top_landing
	_bottom.interaction_offset = bottom_landing
	for endpoint: NetworkedInteraction in [_top, _bottom]:
		endpoint.register_use(_can_mount, _mount, 0.5)
		endpoint.event_received.connect(_event)
	Network.mode_changed.connect(_reset)


func can_use(player: Player) -> bool:
	return (
		_player == null
		and _can_mount(player)
		and (_top.in_range(player) or _bottom.in_range(player))
	)


func interaction_text() -> String:
	return "Climb ladder"


func use() -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if not can_use(player):
		return
	if (
		player.net_position.distance_to(to_global(top_landing))
		< player.net_position.distance_to(to_global(bottom_landing))
	):
		_top.request_use()
	else:
		_bottom.request_use()


func _can_mount(player: Player) -> bool:
	if player == null:
		return false
	if player.net_position.y < global_position.y + (top_y + bottom_y) / 2:
		return true
	var door := get_node_or_null(access_door) as SwingDoor
	return door == null or door.net_state in [SwingDoor.State.OPEN_IN, SwingDoor.State.OPEN_OUT]


func _mount(player: Player) -> bool:
	_top.send_event(&"mount", {}, player.get_multiplayer_authority())
	return true


func _event(event: StringName, _payload: Dictionary) -> void:
	if event != &"mount" or _player != null:
		return
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	if _player == null:
		return
	_previous_physics = _player.is_physics_processing()
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	var local := to_local(_player.net_position)
	var y := top_y if local.y > (top_y + bottom_y) / 2 else bottom_y
	_transition_to(to_global(Vector3(0, y, 0)), false)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = null
		return
	var look := Controls.consume_look(delta)
	_player.yaw -= look.x
	_player.pitch = clampf(_player.pitch - look.y, deg_to_rad(-89.0), deg_to_rad(89.0))
	Controls.consume_jump()
	_player._reset_input()
	var previous := _player.global_position
	if _transition < 1.0:
		_transition = minf(1, _transition + delta / TRANSITION_SECONDS)
		_player.global_position = _from.lerp(_to, smoothstep(0, 1, _transition))
		if _transition >= 1 and _exiting:
			_publish(previous, delta)
			_release()
			return
	elif Controls.gameplay_active():
		var input := -Controls.movement().y
		_climb(input, delta)
	_publish(previous, delta)


func _climb(input: float, delta: float) -> void:
	var point := to_local(_player.global_position)
	point.y = clampf(point.y + input * SPEED * delta, bottom_y, top_y)
	_player.global_position = to_global(point)
	if input > 0 and point.y >= top_y:
		_transition_to(to_global(top_landing), true)
	elif input < 0 and point.y <= bottom_y:
		_transition_to(to_global(bottom_landing), true)


func _publish(previous: Vector3, delta: float) -> void:
	_player.net_position = _player.global_position
	_player.net_velocity = (_player.global_position - previous) / maxf(delta, 0.001)
	_player.net_yaw = _player.yaw
	_player.net_pitch = _player.pitch


func _transition_to(at: Vector3, exiting: bool) -> void:
	_from = _player.global_position
	_to = at
	_transition = 0
	_exiting = exiting


func _release() -> void:
	if is_instance_valid(_player):
		_player.velocity = Vector3.ZERO
		_player.net_velocity = Vector3.ZERO
		_player.set_physics_process(_previous_physics)
	_player = null


func _reset(_mode: Network.Mode) -> void:
	_release()


func _exit_tree() -> void:
	_release()
