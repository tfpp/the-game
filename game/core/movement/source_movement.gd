class_name SourceMovement
extends RefCounted
## Pure Source-engine (CGameMovement) velocity math.
##
## Everything here is a deterministic function of its inputs, with no scene access.
## That keeps it unit-testable and safe to re-run during netcode rollback.
## Collision is handled by the caller (CharacterBody3D.move_and_slide on Jolt).
## All values are in meters (see MovementConfig *_m helpers).


## Result of one velocity step.
class StepResult:
	var velocity: Vector3
	var jumped: bool

	func _init(p_velocity: Vector3, p_jumped: bool) -> void:
		velocity = p_velocity
		jumped = p_jumped


## Build a normalized, horizontal wish direction from a yaw (radians) and a
## 2D input vector (x = strafe right, y = move back, like Input.get_vector).
static func wish_direction(yaw: float, input: Vector2) -> Vector3:
	if input.is_zero_approx():
		return Vector3.ZERO
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish := forward * -input.y + right * input.x
	return wish.normalized()


## PM_Accelerate: add speed toward wish_dir, never pushing the projected speed past wish_speed.
static func accelerate(
	velocity: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, dt: float
) -> Vector3:
	var current_speed := velocity.dot(wish_dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return velocity
	var accel_speed := minf(accel * dt * wish_speed, add_speed)
	return velocity + wish_dir * accel_speed


## PM_AirAccelerate: like accelerate, but the projected speed is capped at
## air_cap (30 u/s) while the gain rate still uses the full wish_speed.
## Strafing so wish_dir is nearly perpendicular to velocity always leaves room
## under the cap, which is why air-strafing and b-hopping gain speed.
static func air_accelerate(
	velocity: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, air_cap: float, dt: float
) -> Vector3:
	var capped := minf(wish_speed, air_cap)
	var current_speed := velocity.dot(wish_dir)
	var add_speed := capped - current_speed
	if add_speed <= 0.0:
		return velocity
	var accel_speed := minf(accel * wish_speed * dt, add_speed)
	return velocity + wish_dir * accel_speed


## PM_Friction (ground only). Operates on horizontal velocity.
static func apply_friction(
	velocity: Vector3, friction: float, stop_speed: float, dt: float
) -> Vector3:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed < 0.001:
		return Vector3(0.0, velocity.y, 0.0)
	var control := maxf(speed, stop_speed)
	var new_speed := maxf(speed - control * friction * dt, 0.0)
	horizontal *= new_speed / speed
	return Vector3(horizontal.x, velocity.y, horizontal.z)


## Whether the player counts as grounded this tick (CategorizePosition).
static func is_grounded(on_floor: bool, velocity: Vector3, cfg: MovementConfig) -> bool:
	return on_floor and velocity.y <= cfg.non_jump_velocity_m()


## One full movement tick (FullWalkMove minus collision).
##
## jump_pressed must be true only on the tick the jump key was *pressed*
## (an edge, not "held"). There is no auto-hop, so holding jump does nothing.
## Pressing on the exact tick you land skips friction for that tick; that's b-hopping.
static func step(
	velocity: Vector3,
	wish_dir: Vector3,
	on_floor: bool,
	jump_pressed: bool,
	cfg: MovementConfig,
	dt: float,
	input_strength: float = 1.0
) -> StepResult:
	var vel := velocity
	var grounded := is_grounded(on_floor, vel, cfg)
	var wish_speed := (
		cfg.max_speed_m() * clampf(input_strength, 0.0, 1.0)
		if not wish_dir.is_zero_approx()
		else 0.0
	)
	var jumped := false

	if grounded and jump_pressed:
		# CheckJumpButton runs before friction, so a perfectly timed hop skips friction.
		vel.y = cfg.jump_speed_m()
		grounded = false
		jumped = true

	if grounded:
		vel.y = 0.0
		vel = apply_friction(vel, cfg.friction, cfg.stop_speed_m(), dt)
		vel = accelerate(vel, wish_dir, wish_speed, cfg.accelerate, dt)
	else:
		vel = air_accelerate(
			vel, wish_dir, wish_speed, cfg.air_accelerate, cfg.air_wish_speed_cap_m(), dt
		)
		vel.y -= cfg.gravity_m() * dt

	return StepResult.new(vel, jumped)


static func horizontal_speed(velocity: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).length()
