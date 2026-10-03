class_name SalonGuestModel
extends PatronModel
## A stationary salon guest on the patron avatar rig: standing about, or seated at a
## card table with both hands resting on the felt. Faces -Z; the stationary scenes
## turn it to face +Z like the imported poses it replaced. The look comes from
## `look`, or from the guest's position when it is -1, so the salon's many guests
## differ without per-instance settings. Cosmetic only; posed ~10 times a second
## while visible (smokers use 30 Hz within 18 m of a camera).

## Salon chairs (the card table model) have 0.48 m seat tops.
const CHAIR_HIP := 0.55
## Felt top (0.93 m) and how far in front of the chair the hands rest.
const HAND_HEIGHT := 0.96
const HAND_REACH := 0.5
const HAND_SPREAD := 0.17
const UPDATE_S := 0.1
const POSE_PHASES := 7
const AnimationBisect := preload("res://features/profiler/animation_bisect.gd")
static var _next_pose_phase := 0

@export var look := -1
@export var seated := false
## Pick an evening dress (girl body) rather than a dinner suit.
@export var lady := false
## Ambient smoking is opt-in; dealers, vendors and other guests stay unchanged.
@export var smoking := false

var _smoking: PatronSmoking

var _time := 0.0
var _since := 0.0
var _until_update := UPDATE_S


func _ready() -> void:
	var chosen := look if look >= 0 else guest_look(global_position, lady)
	build(chosen)
	_time = chosen * 1.7
	if smoking:
		_smoking = PatronSmoking.new()
		_smoking.name = "Smoking"
		add_child(_smoking)
	_update(UPDATE_S)
	# Scheduling phase is independent of the visual idle phase and clothing look.
	var interval := 1.0 / 30.0 if smoking else UPDATE_S
	_until_update = float(_next_pose_phase + 1) * interval / POSE_PHASES
	_next_pose_phase = (_next_pose_phase + 1) % POSE_PHASES


func _process(delta: float) -> void:
	if not AnimationBisect.guests:
		return
	_time += delta
	_since += delta
	_until_update -= delta
	var interval := 1.0 / 30.0 if smoking else UPDATE_S
	var nearby := is_visible_in_tree()
	var camera := get_viewport().get_camera_3d()
	if _smoking != null:
		nearby = nearby and camera != null
		if nearby:
			nearby = (
				global_position.distance_squared_to(camera.global_position)
				< PatronSmoking.VIEW_DISTANCE * PatronSmoking.VIEW_DISTANCE
			)
		if not nearby:
			_smoking.set_active(false)
			_since = minf(_since, UPDATE_S)
	if not nearby or _until_update > 0.0:
		return
	_update(_since)
	_since = 0.0
	# Keep the stagger when frames cross a deadline; resume hidden guests once.
	_until_update = fposmod(_until_update, interval)
	if is_zero_approx(_until_update):
		_until_update = interval


func _update(delta: float) -> void:
	if not seated:
		pose(delta, 0.0, 0.0, 0.0, _time)
	else:
		sit(delta, CHAIR_HIP, _time, 0.7, -0.5)
		for right: bool in [false, true]:
			var side := 1.0 if right else -1.0
			var target := Vector3(side * HAND_SPREAD, HAND_HEIGHT, -HAND_REACH)
			avatar.human.reach_grip(right, to_global(target))
			avatar.human.set_finger_curl(right, 0.2)
	if _smoking != null:
		_smoking.present(self, _time)


## A guest look (after the named patrons) picked from a position hash: the
## dresses alternate with the suits in `LOOKS`.
static func guest_look(at: Vector3, dress: bool) -> int:
	var cell := Vector3i((at * 2.0).round())
	var mixed := absi(cell.x * 73856093 ^ cell.y * 19349663 ^ cell.z * 83492791)
	return INTERN_LOOK + 1 + (mixed % (GUEST_LOOKS / 2)) * 2 + (0 if dress else 1)


## Hitbox in this node's space: a seated body reaches forward to the knees.
func hitbox_bounds() -> AABB:
	if seated:
		return AABB(Vector3(-0.3, 0.0, -0.6), Vector3(0.6, CHAIR_HIP + 0.95, 0.85))
	return AABB(Vector3(-0.3, 0.0, -0.2), Vector3(0.6, 1.83, 0.4))
