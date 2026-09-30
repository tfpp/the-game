class_name MitchModel
extends PatronModel
## Mitch McConnell seated in a wheelchair, with his blond intern pushing it from
## behind (+Z; the group faces -Z). `peace` (0..1) raises his right hand in a
## peace sign. Cosmetic only: every peer builds and poses its own copy.

## Seat top height; Mitch's hip joints rest just above it.
const SEAT_Y := 0.5
const SEATED_HIP := SEAT_Y + 0.07
const WHEEL_RADIUS := 0.3
## How far behind Mitch's hips the intern walks.
const INTERN_Z := 0.85

## Set by `mitch.gd` each frame.
var peace := 0.0

var _intern: PatronModel
var _wheels: Array[Node3D] = []
var _handles: Array[Node3D] = []
var _rolled := 0.0


func build(look: int) -> void:
	super.build(look)
	var frame := _material(Color(0.25, 0.26, 0.28))
	var fabric := _material(Color(0.08, 0.08, 0.1))
	var tyre := _material(Color(0.04, 0.04, 0.04))
	var chair := _pivot("Wheelchair", self, Vector3.ZERO)
	_part("Seat", chair, Vector3(0, SEAT_Y - 0.03, 0.02), Vector3(0.46, 0.06, 0.44), fabric)
	_part("Backrest", chair, Vector3(0, 0.8, 0.22), Vector3(0.46, 0.55, 0.04), fabric)
	_part("Footrest", chair, Vector3(0, 0.08, -0.4), Vector3(0.36, 0.03, 0.18), frame)
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		_part(
			"Armrest" + tag, chair, Vector3(side * 0.25, 0.7, 0.02), Vector3(0.05, 0.04, 0.4), frame
		)
		_part(
			"Strut" + tag, chair, Vector3(side * 0.25, 0.3, -0.3), Vector3(0.03, 0.44, 0.03), frame
		)
		_handles.append(
			_part(
				"Handle" + tag,
				chair,
				Vector3(side * 0.2, 1.12, 0.3),
				Vector3(0.04, 0.04, 0.16),
				frame
			)
		)
		var wheel := _pivot("Wheel" + tag, chair, Vector3(side * 0.29, WHEEL_RADIUS, 0.08))
		var rim := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = WHEEL_RADIUS
		disc.bottom_radius = WHEEL_RADIUS
		disc.height = 0.04
		disc.radial_segments = 12
		rim.mesh = disc
		rim.material_override = tyre
		rim.rotation.z = PI / 2.0
		wheel.add_child(rim)
		_part("Spoke" + tag, wheel, Vector3.ZERO, Vector3(0.05, 0.5, 0.04), frame)
		_part(
			"Caster" + tag, chair, Vector3(side * 0.2, 0.06, -0.38), Vector3(0.03, 0.12, 0.12), tyre
		)
		_wheels.append(wheel)
	_intern = PatronModel.new()
	_intern.name = "Intern"
	_intern.position = Vector3(0, 0, INTERN_Z)
	add_child(_intern)
	_intern.build(INTERN_LOOK)


## Mitch sits still while the intern walks; the wheels roll with the distance.
## Knocked out, he slumps from the chair like any patron.
func pose(delta: float, walk: float, limp: float, flinch: float, idle: float) -> void:
	if avatar == null:
		return
	if limp > 0.5:
		super.pose(delta, 0.0, limp, flinch, idle)
	else:
		sit(delta, SEATED_HIP, idle, 0.3, -1.0)
	var raised := peace * (1.0 - limp)
	if raised > 0.0:
		var arm := avatar._right_arm
		arm.rotation = arm.rotation.lerp(Vector3(2.7, 0, 0.35), raised)
		avatar._right_forearm.rotation.x = lerpf(avatar._right_forearm.rotation.x, -0.1, raised)
		avatar.human.pose(avatar, false, false)
	if is_throwing_peace():
		for digit: String in ["Thumb", "Ring", "Little"]:
			avatar.human.set_digit_curl(true, digit, 1.0)
		for digit: String in ["Index", "Middle"]:
			avatar.human.set_digit_curl(true, digit, 0.0)
	_rolled += walk * PatronMath.WALK_SPEED * delta
	for wheel: Node3D in _wheels:
		wheel.rotation.x = -_rolled / WHEEL_RADIUS
	_intern.pose(delta, walk, limp, flinch, idle)
	if limp <= 0.0 and _intern.is_inside_tree():
		for i: int in 2:
			_intern.avatar.human.reach_grip(i == 1, _handles[i].global_position)
			_intern.avatar.human.set_finger_curl(i == 1, 0.8)


## Whether the peace-sign fingers are showing (the hand is mostly raised).
func is_throwing_peace() -> bool:
	return avatar != null and peace > 0.5
