class_name Frog
extends CharacterBody3D
## The server chooses safe hops and reacts to players. Clients only render synced
## state; appearance and individual movement traits arrive through spawn data.

const REMOTE_SMOOTHING := 18.0
const ALERT_RADIUS := 5.0
const CALM_RADIUS := 7.0
const RESPAWN_DELAY_S := 4.0
## Caps how many times one hop can rebound off surfaces in a row, so a frog wedged
## between two walls can't bounce forever.
const MAX_BOUNCES := 2

@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0
@export var net_phase := -1.0
## Keep alive and position in the same continuous snapshot: an on-change alive
## event can otherwise arrive before the position update during respawn.
@export var net_alive := true

var body_color := Color(0.3, 0.8, 0.35)
var body_size := 1.0
var jump_distance := 1.5
var jump_height := 0.5
var jump_duration := 0.45
var rest_time := 1.0
## Set by features/game_config/game_config.gd: scales how often this frog hops
## (server-only, since hopping is only simulated on the server).
var hop_rate_scale := 1.0
## Set by features/game_config/game_config.gd: scales how high this frog hops
## (server-only, for the same reason as hop_rate_scale).
var jump_height_scale := 1.0

var _home := Vector3.ZERO
var _respawn_timer := 0.0
var _was_alive := true
var _remote_initialized := false
var _hopping := false
var _settling := true
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_elapsed := 0.0
var _hop_duration := 0.45
var _hop_height := 0.5
var _rest_timer := 0.0
var _sense_timer := 0.0
var _threat := Vector3.INF
var _fleeing := false
var _heading := Vector3.FORWARD
var _navigation := FrogNavigation.new()
var _bounce_count := 0

@onready var _body: FrogModel = $Body
@onready var _collider: CollisionShape3D = $Collider
@onready var _ribbit: AudioStreamPlayer3D = $Ribbit


func _ready() -> void:
	_home = position
	add_to_group(&"killable")
	add_to_group(&"frogs")
	_navigation.configure(body_size, get_rid())
	_collider.shape = _navigation.body_shape
	_collider.position.y = _navigation.radius + 0.04
	_body.build(body_color, body_size)
	_ribbit.stream = FrogRibbit.stream()
	if multiplayer.is_server():
		net_position = position
		_rest_timer = randf_range(0.3, _resting_time())
		_heading = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	else:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not net_alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = 0.12
		_sense_players()
	if _settling:
		velocity.y -= 18.0 * delta
		move_and_slide()
		if is_on_floor():
			# The collision sphere rests slightly below the visual foot origin.
			# Restore probe clearance before planning the next arc.
			global_position.y += 0.04
			_settling = false
			velocity = Vector3.ZERO
	elif _hopping:
		_hop_elapsed += delta
		net_phase = minf(_hop_elapsed / _hop_duration, 1.0)
		var next := FrogHop.arc_position(_hop_from, _hop_to, net_phase, _hop_height)
		var collision := move_and_collide(next - global_position)
		if collision != null:
			# A player/prop may move into a hop after it was planned, or the frog
			# simply hopped into a wall. Rebound off it, trampoline-style, unless
			# this hop has already bounced its limit or there's nowhere safe to
			# land — then fall onto the floor instead of passing through it.
			if _bounce_count >= MAX_BOUNCES or not _bounce_off(collision):
				_finish_hop()
				_settling = true
		elif net_phase >= 1.0:
			_finish_hop()
	else:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			_start_hop()
	net_position = position


func _process(delta: float) -> void:
	if net_alive != _was_alive:
		_remote_initialized = false
		_was_alive = net_alive
	_body.visible = net_alive
	_collider.disabled = not net_alive
	var smoothing := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	if not multiplayer.is_server():
		_render_remote(smoothing)
	if not net_alive:
		return
	_body.rotation.y = lerp_angle(_body.rotation.y, net_yaw, smoothing)
	_body.animate(net_phase, delta)


func _sense_players() -> void:
	var nearest := CALM_RADIUS if _fleeing else ALERT_RADIUS
	_threat = Vector3.INF
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player == null or absf(player.global_position.y - global_position.y) > 2.5:
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance < nearest:
			nearest = distance
			_threat = player.global_position
	var was_fleeing := _fleeing
	_fleeing = _threat.is_finite()
	if _fleeing and not was_fleeing:
		_rest_timer = minf(_rest_timer, 0.08)


func _start_hop() -> void:
	var direction := _heading.rotated(Vector3.UP, randf_range(-0.65, 0.65))
	if _fleeing:
		direction = FrogHop.escape_direction(global_position, _threat, _heading)
	var distance := jump_distance * randf_range(0.75, 1.15) * (1.5 if _fleeing else 1.0)
	_hop_height = jump_height * jump_height_scale * (1.2 if _fleeing else 1.0)
	var hop := _navigation.find_hop(
		get_world_3d().direct_space_state,
		global_position,
		direction,
		distance,
		_hop_height,
		_threat
	)
	if hop.is_empty():
		_rest_timer = 0.25
		_heading = _heading.rotated(Vector3.UP, PI * 0.5)
		return
	_hop_from = global_position
	_hop_to = hop["target"]
	_heading = (_hop_to - _hop_from) * Vector3(1, 0, 1)
	_heading = _heading.normalized()
	net_yaw = FrogHop.facing_yaw(_hop_from, _hop_to)
	_hop_duration = jump_duration * (0.85 if _fleeing else 1.0)
	_hop_elapsed = 0.0
	net_phase = 0.0
	_bounce_count = 0
	_hopping = true


## Trampoline-style rebound off whatever the in-flight hop just struck: reflect the
## hop's horizontal direction off the contact normal (FrogHop.bounce_direction) and
## ask navigation for a safe landing along it, same as a fresh hop. Returns false
## when no safe landing exists, so the caller falls back to stopping and settling.
func _bounce_off(collision: KinematicCollision3D) -> bool:
	var incoming := (_hop_to - _hop_from) * Vector3(1, 0, 1)
	var normal := collision.get_normal()
	var direction := FrogHop.bounce_direction(incoming, normal)
	var height := _hop_height * FrogHop.BOUNCE_HEIGHT_GAIN
	# Still touching the surface right after contact; nudge off it first, the same
	# clearance fix _physics_process applies after landing, since a hop probed from
	# a position still touching the wall always fails FrogNavigation.arc_is_clear's
	# very first check.
	global_position += normal * 0.04
	var hop := _navigation.find_hop(
		get_world_3d().direct_space_state,
		global_position,
		direction,
		jump_distance * FrogHop.BOUNCE_DISTANCE_SCALE,
		height,
		_threat
	)
	if hop.is_empty():
		return false
	_bounce_count += 1
	_hop_from = global_position
	_hop_to = hop["target"]
	_heading = (_hop_to - _hop_from) * Vector3(1, 0, 1)
	_heading = _heading.normalized()
	net_yaw = FrogHop.facing_yaw(_hop_from, _hop_to)
	_hop_height = height
	_hop_duration = jump_duration * (0.85 if _fleeing else 1.0)
	_hop_elapsed = 0.0
	net_phase = 0.0
	_hopping = true
	return true


func _finish_hop() -> void:
	_hopping = false
	net_phase = -1.0
	_rest_timer = (randf_range(0.08, 0.18) if _fleeing else _resting_time() * randf_range(0.7, 1.3))


func _render_remote(smoothing: float) -> void:
	if not _remote_initialized:
		# Spawn data remembers the original pond position. The synchronizer applies
		# the current snapshot after _ready, before the first process frame.
		position = net_position
		_body.rotation.y = net_yaw
		_remote_initialized = true
		reset_physics_interpolation()
	else:
		position = position.lerp(net_position, smoothing)


## Called by the server's weapon hitscan. Repeated shotgun pellets cannot restart
## the timer or duplicate the effect, and clients cannot choose an animal's state.
func take_hit(_attacker_peer: int) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	net_alive = false
	_hopping = false
	net_phase = -1.0
	velocity = Vector3.ZERO
	_respawn_timer = RESPAWN_DELAY_S
	_explode.rpc()


func _respawn() -> void:
	position = _home
	net_position = position
	net_yaw = 0.0
	net_phase = -1.0
	_hopping = false
	_settling = true
	velocity = Vector3.ZERO
	_fleeing = false
	_threat = Vector3.INF
	_sense_timer = 0.0
	_bounce_count = 0
	_rest_timer = _resting_time()
	net_alive = true
	reset_physics_interpolation()


@rpc("authority", "call_local", "reliable")
func _explode() -> void:
	MeshExplosion.spawn(self, _body)
	_play_ribbit()


## Cosmetic only; the dedicated server has no audio output.
func _play_ribbit() -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	_ribbit.pitch_scale = randf_range(0.92, 1.12)
	_ribbit.play()


## Time to rest between hops, `rest_time` scaled down as `hop_rate_scale` rises.
func _resting_time() -> float:
	return rest_time / maxf(hop_rate_scale, 0.01)
