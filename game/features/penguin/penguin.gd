extends Node3D
## A decorative penguin that waddles in a slow circle around its spawn point forever.
##
## Server-authoritative like the rest of shared state (see game/AGENTS.md): the server
## (or the offline peer, which is its own server) advances the patrol angle in
## `_physics_process` and publishes `net_position`/`net_yaw`, which Sync
## (MultiplayerSynchronizer) replicates to every client. Non-authoritative peers only
## smooth toward the replicated values. The cosmetic side-to-side rock runs locally on
## every peer since it doesn't need to match exactly. The patrol math itself lives in
## penguin_waddle.gd so it's unit-testable on its own.

const REMOTE_SMOOTHING := 12.0

## Replicated state (server -> everyone). See the synchronizer config in feature.tscn.
@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0

var _home := Vector3.ZERO
var _angle := 0.0
var _elapsed := 0.0

@onready var _body: Node3D = $Body


func _ready() -> void:
	_home = position
	net_position = position
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	_angle += (
		PenguinWaddle.angular_speed(PenguinWaddle.PATROL_RADIUS, PenguinWaddle.WALK_SPEED) * delta
	)
	position = PenguinWaddle.position_on_circle(_home, PenguinWaddle.PATROL_RADIUS, _angle)
	net_position = position
	net_yaw = PenguinWaddle.facing_yaw(_angle)


func _process(delta: float) -> void:
	_elapsed += delta
	if not multiplayer.is_server():
		var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
		position = position.lerp(net_position, t)
	_body.rotation.y = net_yaw
	_body.rotation.z = PenguinWaddle.waddle_rock(
		_elapsed, PenguinWaddle.WADDLE_FREQUENCY, PenguinWaddle.WADDLE_AMPLITUDE
	)
