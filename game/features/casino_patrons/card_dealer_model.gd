class_name CardDealerModel
extends Node3D
## Salon card dealer on the shared player avatar rig, wearing a black vest, white
## shirt and red bow tie. Hands drift over the felt in a slow dealing motion.
## Purely cosmetic: every peer animates its own copy from local time.

const TUX := preload("res://assets/casino_patrons/textures/dealer_tux.png")
## Player/Body sits at the capsule centre; the capsule is 1.8288 m tall.
const FEET_TO_BODY := 0.9144
## Hands hover about 20 cm over the 0.94 m salon card table, in front of the dealer.
const HAND_HEIGHT := 1.14
const HAND_REACH := 0.48
const HAND_SPREAD := 0.2
## Hand motion stays small: a few centimetres, with a slow ~2 s cycle.
const SWAY := Vector3(0.07, 0.05, 0.06)
const PERIOD_S := 2.2

@export var seed_phase := 0.0
@export var skin_index := 3
@export var hair_style := "crop"

var model := BlockPlayerModel.new()
var _time := 0.0


func _ready() -> void:
	model.name = "Avatar"
	# The avatar rig faces -Z; dealers stand on the -Z side of their tables facing +Z.
	model.rotation.y = PI
	model.position.y = FEET_TO_BODY
	add_child(model)
	model.set_appearance(
		{"skin": skin_index, "hair": hair_style, "hair_color": 0, "eyes": 0, "outfit": "casual"}
	)
	var material := model.human.material
	material.set_shader_parameter("tux_texture", TUX)
	material.set_shader_parameter("tuxedo", true)
	material.set_shader_parameter("pants_equipped", true)
	material.set_shader_parameter("pants_tint", Color("1d1d22"))
	_time = seed_phase
	_pose(0.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_pose(delta)


func _pose(delta: float) -> void:
	model.animate(delta, Vector3.ZERO, true, 1.0)
	for right: bool in [false, true]:
		model.human.reach_grip(right, to_global(hand_target(_time, right)))
		model.human.set_finger_curl(right, 0.35)


## Local hand position (dealer faces +Z). Hands move out of phase, like cards passing.
static func hand_target(time: float, right: bool) -> Vector3:
	var angle := TAU * time / PERIOD_S + (PI if right else 0.0)
	var side := -1.0 if right else 1.0
	return Vector3(
		side * HAND_SPREAD + SWAY.x * sin(angle),
		HAND_HEIGHT + SWAY.y * absf(sin(angle * 0.5 + 0.7)),
		HAND_REACH + SWAY.z * cos(angle)
	)
