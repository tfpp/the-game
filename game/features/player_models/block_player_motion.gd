class_name BlockPlayerMotion
extends RefCounted
## Cosmetic locomotion derived from existing movement state. No gameplay state or
## animation RPCs are needed; remote peers use replicated velocity and ground probes.

const RUN_FRACTION := 0.55
const IDLE_SPEED := 0.12


static func state(velocity: Vector3, grounded: bool, max_speed: float) -> StringName:
	if not grounded:
		return &"jump" if velocity.y > 0.1 else &"fall"
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < IDLE_SPEED:
		return &"idle"
	return &"run" if speed >= max_speed * RUN_FRACTION else &"walk"


static func phase_step(speed: float, max_speed: float, delta: float) -> float:
	var run := clampf(speed / maxf(max_speed, 0.1), 0.0, 1.0)
	var stride := lerpf(1.5, 3.5, run)
	return speed / stride * TAU * delta


static func pose(phase: float, velocity: Vector3, grounded: bool, max_speed: float) -> Dictionary:
	var mode := state(velocity, grounded, max_speed)
	var speed := Vector2(velocity.x, velocity.z).length()
	var amount := clampf(speed / maxf(max_speed, 0.1), 0.0, 1.0)
	var swing := sin(phase) * lerpf(0.30, 0.95, amount)
	# Reverse the stride for backwards movement, while keeping strafing animated.
	if velocity.z > 0.1:
		swing = -swing
	var result := {
		"state": mode,
		"left_leg": swing,
		"right_leg": -swing,
		"left_arm": -swing * 0.85,
		"right_arm": swing * 0.85,
		"lean": -amount * 0.12,
		"roll": clampf(-velocity.x / maxf(max_speed, 0.1), -1.0, 1.0) * 0.07,
		"bob": absf(sin(phase * 2.0)) * amount * 0.025,
	}
	if mode == &"idle":
		for key: String in ["left_leg", "right_leg", "left_arm", "right_arm", "bob"]:
			result[key] = 0.0
	elif not grounded:
		var rising := mode == &"jump"
		result["left_leg"] = 0.48 if rising else 0.15
		result["right_leg"] = -0.28 if rising else -0.12
		result["left_arm"] = -0.85 if rising else -0.30
		result["right_arm"] = -0.85 if rising else -0.30
		result["lean"] = -0.08 if rising else 0.05
		result["bob"] = 0.0
	return result
