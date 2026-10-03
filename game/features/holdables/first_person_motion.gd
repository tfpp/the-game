class_name FirstPersonMotion
extends RefCounted
## Look lag and bob layered over whole-viewmodel momentum, including jump/landing.

const RESPONSE := 6.0
const MAX_LOOK_SPEED := 5.0
const METERS_PER_CYCLE := 5.0
const FULL_BOB_SPEED := 8.0
const MOMENTUM_STIFFNESS := 65.0
const MOMENTUM_DAMPING := 11.0
const MOMENTUM_TRAVEL := Vector3(0.075, 0.065, 0.055)
const MOMENTUM_LIMIT := Vector3(0.11, 0.13, 0.09)
const VELOCITY_IMPULSE := Vector3(0.025, 0.045, 0.025)

var _ready := false
var _angles := Vector2.ZERO
var _lag := Vector2.ZERO
var _bob := Vector3.ZERO
var _movement := Vector3.ZERO
var _momentum := Vector3.ZERO
var _momentum_velocity := Vector3.ZERO
var _previous_velocity := Vector3.ZERO
var _phase := 0.0
var camera_motion := Transform3D.IDENTITY


func reset() -> void:
	_ready = false
	_lag = Vector2.ZERO
	_bob = Vector3.ZERO
	_movement = Vector3.ZERO
	_momentum = Vector3.ZERO
	_momentum_velocity = Vector3.ZERO
	_previous_velocity = Vector3.ZERO
	_phase = 0.0
	camera_motion = Transform3D.IDENTITY


func advance(angles: Vector2, velocity: Vector3, delta: float) -> Transform3D:
	if not _ready:
		_angles = angles
		_previous_velocity = velocity
		_ready = true
	if delta <= 0.0:
		return Transform3D.IDENTITY
	var look := Vector2(
		angle_difference(_angles.x, angles.x), angle_difference(_angles.y, angles.y)
	) / delta
	_angles = angles
	look = look.limit_length(MAX_LOOK_SPEED)
	var weight := 1.0 - exp(-RESPONSE * delta)
	_lag = _lag.lerp(look, weight)
	var speed := Vector2(velocity.x, velocity.z).length()
	_phase = fmod(_phase + speed * delta * TAU / METERS_PER_CYCLE, TAU)
	var strength := clampf(speed / FULL_BOB_SPEED, 0.0, 1.0)
	var bob := Vector3(sin(_phase) * 0.025, -absf(cos(_phase)) * 0.018, 0.0) * strength
	_bob = _bob.lerp(bob, weight)
	var facing := Basis(Vector3.UP, angles.x).inverse()
	var local_velocity := facing * Vector3(velocity.x, 0, velocity.z)
	var movement := (local_velocity / FULL_BOB_SPEED).limit_length(1.0)
	_movement = _movement.lerp(movement, weight)
	var target := -movement * MOMENTUM_TRAVEL
	target.y = -clampf(velocity.y / 6.0, -1.0, 1.0) * MOMENTUM_TRAVEL.y
	# A change in real world velocity kicks the spring. Jumping and landing
	# therefore move the entire rig, even without any horizontal movement.
	_momentum_velocity -= facing * (velocity - _previous_velocity) * VELOCITY_IMPULSE
	_previous_velocity = velocity
	_advance_momentum(target, delta)
	var lean := Vector3(
		_movement.z * 0.025 + _momentum.y * 0.4,
		-_movement.x * 0.012,
		_movement.x * 0.035
	)
	return Transform3D(
		Basis.from_euler(Vector3(-_lag.y, -_lag.x, -_lag.x * 0.4) * 0.012 + lean),
		Vector3(_lag.x, -_lag.y, 0.0) * 0.008 + _bob + _momentum
	)


func _advance_momentum(target: Vector3, delta: float) -> void:
	# Small integration steps keep the spring stable during long rendering frames.
	var remaining := minf(delta, 0.1)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		var acceleration := (
			(target - _momentum) * MOMENTUM_STIFFNESS - _momentum_velocity * MOMENTUM_DAMPING
		)
		_momentum_velocity += acceleration * step
		_momentum += _momentum_velocity * step
		remaining -= step
	_momentum = _momentum.clamp(-MOMENTUM_LIMIT, MOMENTUM_LIMIT)


func apply(player: Player, resting: Transform3D, delta: float, active: bool) -> Transform3D:
	if not active or not FirstPersonView.is_first_person(player):
		reset()
		return resting
	camera_motion = advance(Vector2(player.yaw, player.pitch), player.velocity, delta)
	camera_motion = FirstPersonView.swap_pose(player) * camera_motion
	var camera := player.get_node("Camera") as Camera3D
	var frame := camera.global_transform
	return frame * camera_motion * frame.affine_inverse() * resting
