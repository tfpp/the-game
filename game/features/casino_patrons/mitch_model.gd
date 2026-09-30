class_name MitchModel
extends PatronModel
## Mitch McConnell seated in a wheelchair, with his blond intern pushing it from
## behind (+Z; the group faces -Z). `peace` (0..1) raises his right hand in a
## peace sign. Cosmetic only: every peer builds and poses its own copy.

## Seat top height; Mitch's hips rest just above it.
const SEAT_Y := 0.5
const WHEEL_RADIUS := 0.3
## How far behind Mitch's hips the intern walks.
const INTERN_Z := 0.85

## Set by `mitch.gd` each frame.
var peace := 0.0

var _intern: PatronModel
var _wheels: Array[Node3D] = []
var _fingers: Node3D


func build(look: int) -> void:
	super.build(look)
	var frame := _material(Color(0.25, 0.26, 0.28))
	var fabric := _material(Color(0.08, 0.08, 0.1))
	var tyre := _material(Color(0.04, 0.04, 0.04))
	var chair := _pivot("Wheelchair", self, Vector3.ZERO)
	_part("Seat", chair, Vector3(0, SEAT_Y - 0.03, 0), Vector3(0.46, 0.06, 0.44), fabric)
	_part("Backrest", chair, Vector3(0, 0.8, 0.22), Vector3(0.46, 0.55, 0.04), fabric)
	_part("Footrest", chair, Vector3(0, 0.08, -0.45), Vector3(0.36, 0.03, 0.14), frame)
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		_part(
			"Armrest" + tag, chair, Vector3(side * 0.25, 0.7, 0.02), Vector3(0.05, 0.04, 0.4), frame
		)
		_part(
			"Strut" + tag, chair, Vector3(side * 0.25, 0.3, -0.3), Vector3(0.03, 0.44, 0.03), frame
		)
		_part(
			"Handle" + tag, chair, Vector3(side * 0.2, 1.12, 0.3), Vector3(0.04, 0.04, 0.16), frame
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
	_fingers = _pivot("PeaceSign", _elbows[1], Vector3(0, -0.38, 0))
	var skin := (_elbows[1].get_node("HandR") as MeshInstance3D).material_override
	for side: float in [-1.0, 1.0]:
		var finger := _pivot("Finger%d" % int(side), _fingers, Vector3.ZERO)
		finger.rotation.z = side * 0.3
		_part("Digit", finger, Vector3(0, -0.06, 0), Vector3(0.025, 0.12, 0.025), skin)
	_fingers.visible = false
	_intern = PatronModel.new()
	_intern.name = "Intern"
	_intern.position = Vector3(0, 0, INTERN_Z)
	add_child(_intern)
	_intern.build(INTERN_LOOK)


## Mitch sits still while the intern walks; the wheels roll with `phase`.
func pose(phase: float, walk: float, limp: float, flinch: float, idle: float) -> void:
	if _hips == null:
		return
	super.pose(phase, 0.0, limp, flinch, idle)
	var alive := 1.0 - limp
	_hips.position.y = lerpf(HIP_HEIGHT, SEAT_Y + 0.08, alive)
	_torso.rotation.x += 0.12 * alive
	for i: int in 2:
		_legs[i].rotation.x = PI / 2.0 * alive
		_knees[i].rotation.x = -PI / 2.0 * alive
		_shoulders[i].rotation.x = 0.35 * alive
		_elbows[i].rotation.x = 1.0 * alive
	_shoulders[1].rotation = _shoulders[1].rotation.lerp(Vector3(2.7, 0, 0.35), peace * alive)
	_elbows[1].rotation.x = lerpf(_elbows[1].rotation.x, 0.1, peace * alive)
	_fingers.visible = peace * alive > 0.5
	for wheel: Node3D in _wheels:
		wheel.rotation.x = -phase / TAU * 4.0
	_intern.pose(phase, walk, limp, flinch, idle)
	for i: int in 2:
		_intern._shoulders[i].rotation = Vector3(0.75 * alive, 0, 0)
		_intern._elbows[i].rotation.x = 0.5 * alive
