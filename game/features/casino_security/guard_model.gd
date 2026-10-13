class_name GuardModel
extends PatronModel
## A Golden Crown bouncer on the shared patron/player rig: a dark suit, shades,
## an earpiece, a gold badge and SECURITY across the back, bulked up by scaling
## the rig's spine, arm and thigh bones (no new meshes or textures). Faces -Z with
## its feet at the origin. Cosmetic only: every peer poses its own copy.

## Three bouncers' looks (PatronModel LOOKS shape): skin, hair and suit colours.
const GUARD_LOOKS: Array[Dictionary] = [
	{"skin": 6, "hair": "bald", "hair_color": 0, "shirt": 1, "pants": 1, "tie": -1},
	{"skin": 2, "hair": "crop", "hair_color": 0, "shirt": 1, "pants": 1, "tie": -1},
	{"skin": 4, "hair": "bald", "hair_color": 4, "shirt": 1, "pants": 1, "tie": -1},
]
## Bone scales that make the build: a broad, deep chest and thick limbs. The head
## takes back most of the spine's scale so it stays about human-sized.
const BULK := {
	"Spine": Vector3(1.24, 1.05, 1.3),
	"UpperArmL": Vector3(1.15, 1.0, 1.15),
	"UpperArmR": Vector3(1.15, 1.0, 1.15),
	"ThighL": Vector3(1.2, 1.0, 1.2),
	"ThighR": Vector3(1.2, 1.0, 1.2),
}
const GOLD := Color("d4ac4e")


func build_guard(index: int) -> void:
	dress_up(GUARD_LOOKS[posmod(index, GUARD_LOOKS.size())])
	avatar.scale = Vector3.ONE * SecurityRules.GUARD_SCALE
	var shades := _material(Color(0.03, 0.03, 0.035))
	_part(
		"Shades", head_items, Vector3(0, 0.235, FACE_Z - 0.008), Vector3(0.15, 0.035, 0.012), shades
	)
	_part("Earpiece", head_items, Vector3(0.088, 0.2, 0.0), Vector3(0.018, 0.03, 0.025), shades)
	_part(
		"Badge",
		torso_items,
		Vector3(-0.1, 0.47, CHEST_Z - 0.012),
		Vector3(0.05, 0.06, 0.008),
		_material(GOLD)
	)
	var back := Label3D.new()
	back.name = "Back"
	back.text = "SECURITY"
	back.font_size = 32
	back.pixel_size = 0.0035
	back.outline_size = 0
	back.modulate = GOLD
	back.double_sided = false
	back.position = Vector3(0, 0.4, 0.145)
	torso_items.add_child(back)
	_bulk_up()


## Scales the rig's bones; poses only rotate them, so this lasts.
func _bulk_up() -> void:
	var skeleton := avatar.human.skeleton
	if skeleton == null:
		return
	for bone: String in BULK:
		skeleton.set_bone_pose_scale(skeleton.find_bone(bone), BULK[bone])
	var spine: Vector3 = BULK["Spine"]
	var head := Vector3(1.0 / sqrt(spine.x), 1.0 / spine.y, 1.0 / sqrt(spine.z))
	skeleton.set_bone_pose_scale(skeleton.find_bone("Head"), head)


## Poses the guard. `walk` 0..1 stride; `arms` crosses them over the chest,
## `carry` holds a body on the right shoulder, `heave` throws it forward.
## Arm pivots: +x raises forward, +y turns a bent right forearm inward (left
## mirrored), +x on a forearm bends the elbow.
func pose_guard(
	delta: float, walk: float, idle: float, arms: float, carry: float, heave: float
) -> void:
	if avatar == null:
		return
	pose(delta, walk, 0.0, 0.0, idle)
	var left := avatar._left_arm
	var right := avatar._right_arm
	var left_elbow := avatar._left_forearm
	var right_elbow := avatar._right_forearm
	if arms > 0.0:
		left.rotation = left.rotation.lerp(Vector3(0.4, -0.9, 0.1), arms)
		right.rotation = right.rotation.lerp(Vector3(0.4, 0.9, -0.1), arms)
		left_elbow.rotation.x = lerpf(left_elbow.rotation.x, 1.6, arms)
		right_elbow.rotation.x = lerpf(right_elbow.rotation.x, 1.6, arms)
	if carry > 0.0:
		# Right hand clamps the passenger's legs on the shoulder; the left steadies them.
		var steady := carry * (1.0 - heave)
		right.rotation = right.rotation.lerp(Vector3(1.1, 0.25, 0.0), carry)
		right_elbow.rotation.x = lerpf(right_elbow.rotation.x, 1.3, carry)
		left.rotation = left.rotation.lerp(Vector3(0.9, -0.5, 0.0), steady)
		left_elbow.rotation.x = lerpf(left_elbow.rotation.x, 1.2, steady)
	if heave > 0.0:
		for upper: Node3D in [left, right]:
			upper.rotation = upper.rotation.lerp(Vector3(2.6, 0.0, 0.0), heave)
		for elbow: Node3D in [left_elbow, right_elbow]:
			elbow.rotation.x = lerpf(elbow.rotation.x, 0.2, heave)
		avatar._torso.rotation.x = -0.3 * heave
	avatar.human.pose(avatar, false, false)
