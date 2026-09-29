class_name PatronModel
extends Node3D
## A jointed casino patron built from one shared unit cube per part, like
## features/shooting_gallery/humanoid_target_model.gd, but with hip, knee,
## shoulder, elbow and neck pivots so it can walk and go limp. Faces -Z.
## Cosmetic only: every peer builds and poses its own copy.

const SKIN_TONES: Array[Color] = [
	Color(0.93, 0.76, 0.62),
	Color(0.78, 0.58, 0.42),
	Color(0.55, 0.38, 0.26),
	Color(0.36, 0.24, 0.17),
]
const JACKETS: Array[Color] = [
	Color(0.12, 0.13, 0.2),
	Color(0.45, 0.1, 0.12),
	Color(0.2, 0.3, 0.22),
	Color(0.62, 0.58, 0.5),
	Color(0.3, 0.18, 0.35),
]
const TROUSERS: Array[Color] = [
	Color(0.1, 0.1, 0.12), Color(0.25, 0.22, 0.2), Color(0.18, 0.2, 0.28)
]
const HAIR: Array[Color] = [
	Color(0.08, 0.06, 0.05), Color(0.35, 0.2, 0.1), Color(0.75, 0.6, 0.35), Color(0.6, 0.6, 0.6)
]
const TIES: Array[Color] = [Color(0.7, 0.1, 0.1), Color(0.8, 0.65, 0.15), Color(0.1, 0.3, 0.6)]

## The patron index that dresses up as Zohran Mamdani, New York City's mayor:
## dark suit, white shirt, blue tie, short black hair and a trimmed beard, with a
## name tag floating overhead.
const MAMDANI_LOOK := 4
const MAMDANI_NAME := "Zohran Mamdani"
const TRUMP_LOOK := 5
const TRUMP_NAME := "Donald Trump"
## Mitch McConnell rides a wheelchair pushed by his intern (`mitch.gd`); the intern
## is a second body built with INTERN_LOOK inside his model.
const MITCH_LOOK := 6
const MITCH_NAME := "Mitch McConnell"
const INTERN_LOOK := 7

## Hip height when standing; the pose lifts and lowers `Hips` around it.
const HIP_HEIGHT := 0.95

var _cube := BoxMesh.new()
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []


## Builds the body with a look picked from `look` (the patron's index).
func build(look: int) -> void:
	var skin := _material(SKIN_TONES[look % SKIN_TONES.size()])
	var jacket := _material(JACKETS[look % JACKETS.size()])
	var trousers := _material(TROUSERS[(look + 1) % TROUSERS.size()])
	var hair := _material(HAIR[(look * 3 + 1) % HAIR.size()])
	var shirt := _material(Color(0.92, 0.9, 0.86))
	var tie := _material(TIES[look % TIES.size()])
	var shoe := _material(Color(0.06, 0.05, 0.05))
	var dark := _material(Color(0.05, 0.05, 0.06))
	var is_mamdani := look == MAMDANI_LOOK
	if is_mamdani:
		skin = _material(Color(0.66, 0.47, 0.34))
		jacket = _material(Color(0.1, 0.11, 0.16))
		trousers = jacket
		hair = _material(Color(0.05, 0.04, 0.04))
		tie = _material(Color(0.12, 0.3, 0.62))
	if look == TRUMP_LOOK:
		skin = _material(Color(0.92, 0.64, 0.43))
		jacket = _material(Color(0.08, 0.12, 0.23))
		trousers = jacket
		hair = _material(Color(0.88, 0.73, 0.36))
		tie = _material(Color(0.8, 0.04, 0.06))
	if look == MITCH_LOOK:
		skin = _material(Color(0.93, 0.8, 0.72))
		jacket = _material(Color(0.1, 0.1, 0.13))
		trousers = jacket
		hair = _material(Color(0.9, 0.9, 0.88))
		tie = _material(Color(0.2, 0.25, 0.55))
	if look == INTERN_LOOK:
		skin = _material(Color(0.96, 0.82, 0.72))
		jacket = _material(Color(0.95, 0.93, 0.9))
		trousers = _material(Color(0.12, 0.14, 0.24))
		hair = _material(Color(0.98, 0.84, 0.45))
		tie = _material(Color(0.85, 0.35, 0.5))
	_hips = _pivot("Hips", self, Vector3(0, HIP_HEIGHT, 0))
	_part("Pelvis", _hips, Vector3(0, 0.02, 0), Vector3(0.34, 0.18, 0.22), trousers)
	_torso = _pivot("Torso", _hips, Vector3(0, 0.1, 0))
	_part("Chest", _torso, Vector3(0, 0.27, 0), Vector3(0.42, 0.5, 0.24), jacket)
	_part("Shirt", _torso, Vector3(0, 0.4, -0.115), Vector3(0.14, 0.26, 0.02), shirt)
	_part("Tie", _torso, Vector3(0, 0.36, -0.13), Vector3(0.05, 0.26, 0.02), tie)
	_part("Neck", _torso, Vector3(0, 0.56, 0), Vector3(0.1, 0.08, 0.1), skin)
	_head = _pivot("Head", _torso, Vector3(0, 0.6, 0))
	_part("Face", _head, Vector3(0, 0.13, 0), Vector3(0.24, 0.27, 0.25), skin)
	_part("Hair", _head, Vector3(0, 0.28, 0.02), Vector3(0.26, 0.06, 0.27), hair)
	_part("HairBack", _head, Vector3(0, 0.18, 0.12), Vector3(0.26, 0.2, 0.04), hair)
	_part("Nose", _head, Vector3(0, 0.12, -0.13), Vector3(0.04, 0.06, 0.03), skin)
	if is_mamdani:
		_part("Beard", _head, Vector3(0, 0.04, -0.01), Vector3(0.25, 0.1, 0.25), hair)
		_part("Moustache", _head, Vector3(0, 0.085, -0.13), Vector3(0.1, 0.02, 0.02), hair)
		_name_tag(MAMDANI_NAME)
	if look == TRUMP_LOOK:
		_part("SweptFringe", _head, Vector3(-0.035, 0.25, -0.12), Vector3(0.28, 0.09, 0.1), hair)
		_name_tag(TRUMP_NAME)
	if look == MITCH_LOOK:
		for side: float in [-1.0, 1.0]:
			_part(
				"Lens%d" % int(side),
				_head,
				Vector3(side * 0.06, 0.17, -0.13),
				Vector3(0.07, 0.05, 0.01),
				dark
			)
		_part("Jowls", _head, Vector3(0, 0.02, -0.03), Vector3(0.22, 0.08, 0.2), skin)
		_name_tag(MITCH_NAME)
	if look == INTERN_LOOK:
		_part("LongHair", _head, Vector3(0, 0.05, 0.1), Vector3(0.3, 0.36, 0.1), hair)
		_part("Bangs", _head, Vector3(0, 0.25, -0.11), Vector3(0.26, 0.06, 0.06), hair)
		for side: float in [-1.0, 1.0]:
			_part(
				"Cheek%d" % int(side),
				_head,
				Vector3(side * 0.08, 0.1, -0.126),
				Vector3(0.04, 0.025, 0.01),
				_material(Color(0.95, 0.55, 0.6))
			)
		_part(
			"Lanyard",
			_torso,
			Vector3(0, 0.2, -0.135),
			Vector3(0.08, 0.1, 0.01),
			_material(Color(0.2, 0.4, 0.8))
		)
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		_part(
			"Eye" + tag, _head, Vector3(side * 0.06, 0.17, -0.126), Vector3(0.04, 0.03, 0.01), dark
		)
		var shoulder := _pivot("Shoulder" + tag, _torso, Vector3(side * 0.27, 0.47, 0))
		_part("UpperArm" + tag, shoulder, Vector3(0, -0.15, 0), Vector3(0.13, 0.32, 0.14), jacket)
		var elbow := _pivot("Elbow" + tag, shoulder, Vector3(0, -0.3, 0))
		_part("Forearm" + tag, elbow, Vector3(0, -0.13, 0), Vector3(0.11, 0.28, 0.12), jacket)
		_part("Hand" + tag, elbow, Vector3(0, -0.32, 0), Vector3(0.09, 0.12, 0.1), skin)
		var leg := _pivot("Leg" + tag, _hips, Vector3(side * 0.1, 0, 0))
		_part("Thigh" + tag, leg, Vector3(0, -0.22, 0), Vector3(0.15, 0.44, 0.16), trousers)
		var knee := _pivot("Knee" + tag, leg, Vector3(0, -0.45, 0))
		_part("Shin" + tag, knee, Vector3(0, -0.22, 0), Vector3(0.13, 0.44, 0.14), trousers)
		_part("Shoe" + tag, knee, Vector3(0, -0.46, -0.05), Vector3(0.13, 0.08, 0.26), shoe)
		_shoulders.append(shoulder)
		_elbows.append(elbow)
		_legs.append(leg)
		_knees.append(knee)


## Poses the joints. `phase` is the walk cycle in radians and `walk` how much
## of a stride to take (0 standing, 1 walking). `limp` (0..1) blends into a
## sprawled, knocked-out pose; `flinch` (0..1) snaps the head back after a punch.
## `idle` slowly turns the head while standing about.
func pose(phase: float, walk: float, limp: float, flinch: float, idle: float) -> void:
	if _hips == null:
		return
	var stride := sin(phase) * 0.5 * walk
	var alive := 1.0 - limp
	_hips.position.y = HIP_HEIGHT + absf(cos(phase)) * 0.03 * walk * alive
	_torso.rotation = Vector3(flinch * 0.25, sin(phase) * 0.06 * walk * alive, 0)
	_head.rotation = Vector3(
		flinch * 0.5 - limp * 0.3, sin(idle * 0.7) * 0.5 * (1.0 - walk) * alive, limp * 0.6
	)
	for i: int in 2:
		var side := -1.0 if i == 0 else 1.0
		var swing := stride if i == 0 else -stride
		_legs[i].rotation = Vector3(swing * alive, 0, side * 0.22 * limp)
		_knees[i].rotation.x = (-maxf(-swing, 0.0) * 1.1 * alive - limp * (0.9 if i == 0 else 0.15))
		_shoulders[i].rotation = Vector3(
			-swing * 0.8 * alive - limp * 0.5, 0, side * (0.08 * alive + 1.35 * limp)
		)
		_elbows[i].rotation.x = 0.2 * alive + absf(swing) * 0.4 * alive + 0.7 * limp


func _name_tag(text: String) -> void:
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 10
	tag.pixel_size = 0.004
	tag.position = Vector3(0, 2.1, 0)
	add_child(tag)


func _pivot(label: String, parent: Node3D, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label
	pivot.position = at
	parent.add_child(pivot)
	return pivot


func _part(
	label: String, parent: Node3D, at: Vector3, dimensions: Vector3, material: Material
) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = _cube
	part.material_override = material
	part.position = at
	part.scale = dimensions
	parent.add_child(part)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material


## Raises the right arm forward and up by `amount` (0..1), e.g. to pat a head.
## Call after `pose()`.
func reach(amount: float) -> void:
	if _hips == null or amount <= 0.0:
		return
	_shoulders[1].rotation = _shoulders[1].rotation.lerp(Vector3(1.3, 0, 0.1), amount)
	_elbows[1].rotation.x = lerpf(_elbows[1].rotation.x, 0.2, amount)
