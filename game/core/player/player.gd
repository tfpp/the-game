class_name Player
extends CharacterBody3D
## First-person player with Source-style movement.
##
## Networking: movement is CLIENT-AUTHORITATIVE. The owning peer is this node's
## multiplayer authority. It simulates movement in _physics_process at the fixed
## tick (64 Hz) and publishes `net_*` properties, which the MultiplayerSynchronizer
## replicates to the server and the other peers. Other peers render a smoothed
## puppet. Everything else (spawning, despawning, game state) is server-authoritative.

signal jumped

## Exponential smoothing rate for remote puppets (higher = snappier).
const REMOTE_SMOOTHING := 20.0

@export var movement: MovementConfig = MovementConfig.new()

## Replicated state (owner -> everyone). See the synchronizer config in player.tscn.
@export var net_position := Vector3.ZERO
@export var net_velocity := Vector3.ZERO
@export var net_yaw := 0.0
@export var net_pitch := 0.0

## Account display name, set by the server when spawning. Shown above remote players.
var display_name := ""

## View angles in radians. Yaw rotates around +Y; pitch is clamped to +-89 degrees.
var yaw := 0.0
var pitch := 0.0

var _jump_queued := false

@onready var _camera: Camera3D = $Camera
@onready var _collider: CollisionShape3D = $Collider
@onready var _body: Node3D = $Body


func _ready() -> void:
	add_to_group(&"players")
	_configure_hull()
	if is_local():
		add_to_group(&"local_player")
		Controls.input_reset.connect(_reset_input)
		net_position = global_position
		_camera.top_level = true
		_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_camera.current = true
		_body.visible = false
		_update_camera()
	else:
		# Puppets are moved by replication, not physics; skip interpolation to avoid fighting it.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_camera.current = false
		_camera.queue_free()
		set_physics_process(false)
		global_position = net_position
		_add_nameplate()


func is_local() -> bool:
	return is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or not Controls.gameplay_active():
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var look := Controls.look_radians_per_count()
		yaw -= motion.screen_relative.x * look
		pitch = clampf(pitch - motion.screen_relative.y * look, deg_to_rad(-89.0), deg_to_rad(89.0))
	# Only presses count (echo/held repeats don't), so jumps must be timed.
	if event.is_action_pressed("jump"):
		_jump_queued = true


func _physics_process(delta: float) -> void:
	var input := Controls.movement()
	var look := Controls.consume_look(delta)
	yaw -= look.x
	pitch = clampf(pitch - look.y, deg_to_rad(-89.0), deg_to_rad(89.0))
	var extra_jump := Controls.consume_jump()
	_jump_queued = Controls.gameplay_active() and (_jump_queued or extra_jump)
	var movement_yaw := yaw
	var third_person := get_tree().get_first_node_in_group(&"third_person_camera")
	if third_person != null:
		movement_yaw = third_person.movement_yaw(self)
	var wish_dir := SourceMovement.wish_direction(movement_yaw, input)

	var result := SourceMovement.step(
		velocity, wish_dir, is_on_floor(), _jump_queued, movement, delta, input.length()
	)
	# The queued press is consumed this tick either way: no jump buffering.
	_jump_queued = false
	velocity = result.velocity
	move_and_slide()

	net_position = global_position
	net_velocity = velocity
	net_yaw = yaw
	net_pitch = pitch
	if result.jumped:
		jumped.emit()


func _process(delta: float) -> void:
	if is_local():
		_update_camera()
		return
	var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	global_position = global_position.lerp(net_position, t)
	velocity = net_velocity
	_body.rotation.y = lerp_angle(_body.rotation.y, net_yaw, t)


## Server -> owner: force a position (respawn, teleport) and, optionally, a view yaw
## (radians). Movement is otherwise client-owned, so the server asks the owner to move.
## `new_yaw` defaults to NAN, meaning "leave the player's facing alone"; pass an actual
## value when the teleport itself implies a new facing (e.g. the elevator preserving
## relative orientation between differently-rotated cabs). Call with
## `player.server_teleport.rpc_id(player.get_multiplayer_authority(), pos)`.
@rpc("any_peer", "call_local", "reliable")
func server_teleport(to: Vector3, new_yaw: float = NAN) -> void:
	if multiplayer.get_remote_sender_id() != MultiplayerPeer.TARGET_PEER_SERVER:
		return
	if not is_local():
		return
	global_position = to
	velocity = Vector3.ZERO
	net_position = to
	if not is_nan(new_yaw):
		yaw = new_yaw
		net_yaw = new_yaw
	reset_physics_interpolation()


func horizontal_speed_units() -> float:
	return SourceMovement.horizontal_speed(velocity) / MovementConfig.UNIT_TO_METERS


func _update_camera() -> void:
	var origin := get_global_transform_interpolated().origin
	var bottom := origin.y - movement.hull_height_m() * 0.5
	_camera.global_position = Vector3(origin.x, bottom + movement.eye_height_m(), origin.z)
	_camera.global_rotation = Vector3(pitch, yaw, 0.0)


func _add_nameplate() -> void:
	if display_name.is_empty():
		return
	var label := Label3D.new()
	label.name = "Nameplate"
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0015
	label.font_size = 24
	label.outline_size = 6
	label.no_depth_test = true
	label.position.y = movement.hull_height_m() * 0.5 + 0.35
	add_child(label)


func _configure_hull() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = movement.hull_radius_m()
	shape.height = movement.hull_height_m()
	_collider.shape = shape
	# Source treats surfaces with normal.y >= 0.7 as walkable (~45.57 degrees).
	floor_max_angle = acos(0.7)
	floor_snap_length = 18.0 * MovementConfig.UNIT_TO_METERS
	floor_stop_on_slope = true
	floor_block_on_wall = false
	max_slides = 4


func _reset_input() -> void:
	_jump_queued = false
