class_name PatronSmoking
extends Node3D
## Local ambient presentation, not an inventory item or gameplay action.
## Call after the guest's base pose so the same avatar IK owns the right arm.

const CIGARETTE := preload("res://features/holdables/items/cigarette_view.tscn")
const SMOKE := preload("res://features/casino_patrons/smoke.tscn")
const CYCLE_S := 10.0
const VIEW_DISTANCE := 18.0

var cigarette: Node3D
var exhale: CPUParticles3D
var tip_smoke: CPUParticles3D
var _active := false


func _ready() -> void:
	cigarette = CIGARETTE.instantiate() as Node3D
	add_child(cigarette)
	# Keep the existing painted cigarette but replace its solid sphere smoke
	# on this instance only; player-held cigarettes remain unchanged.
	var old := cigarette.get_node("Smoke")
	cigarette.remove_child(old)
	old.free()
	tip_smoke = SMOKE.instantiate() as CPUParticles3D
	tip_smoke.name = "TipSmoke"
	tip_smoke.amount = 8
	tip_smoke.lifetime = 2.0
	tip_smoke.direction = Vector3.UP
	tip_smoke.initial_velocity_min = 0.04
	tip_smoke.initial_velocity_max = 0.08
	tip_smoke.scale_amount_min = 0.3
	tip_smoke.scale_amount_max = 0.5
	tip_smoke.position = Vector3(0, 0, -0.025)
	cigarette.add_child(tip_smoke)
	exhale = SMOKE.instantiate() as CPUParticles3D
	exhale.name = "Exhale"
	add_child(exhale)
	set_active(false)


## A smooth reach, held draw, lower and pause; guests are phase-offset.
static func draw_weight(time: float) -> float:
	var phase := fposmod(time, CYCLE_S)
	return smoothstep(0.5, 1.5, phase) * (1.0 - smoothstep(2.6, 3.5, phase))


static func is_exhaling(time: float) -> bool:
	var phase := fposmod(time, CYCLE_S)
	return phase >= 3.1 and phase < 4.6


func set_active(active: bool) -> void:
	visible = active
	tip_smoke.emitting = active
	if not active:
		exhale.emitting = false
		if _active:
			# Clear world-space particles on death/cull, so respawns don't
			# bring back an old cloud or leave one suspended over a dead NPC.
			exhale.restart()
			tip_smoke.restart()
			exhale.emitting = false
			tip_smoke.emitting = false
	_active = active


func present(model: SalonGuestModel, time: float) -> void:
	set_active(true)
	var mouth := model.avatar.mouth_transform()
	var basis := mouth.basis.orthonormalized()
	var contact := (cigarette.get_node("Mouth") as Marker3D).position
	var drawn := Transform3D(basis, mouth.origin - basis * contact)
	var resting := Transform3D(
		model.global_basis.orthonormalized() * Basis(Vector3.RIGHT, -0.25),
		model.to_global(Vector3(0.24, 1.05 if not model.seated else 0.99, -0.4))
	)
	cigarette.global_transform = resting.interpolate_with(drawn, draw_weight(time))
	var grip := cigarette.get_node("Grip") as Marker3D
	model.avatar.human.reach_grip(true, grip.global_position)
	model.avatar.human.orient_grip(true, grip.global_basis)
	model.avatar.human.set_finger_curl(true, 0.65)
	model.avatar.human.set_digit_curl(true, "Index", 0.35)
	model.avatar.human.set_digit_curl(true, "Middle", 0.45)
	exhale.global_transform = mouth
	exhale.emitting = is_exhaling(time)
