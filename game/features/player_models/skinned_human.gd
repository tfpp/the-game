class_name SkinnedHuman
extends Node3D
## One imported, connected human surface. Bones deform vertices; shape keys sculpt
## the same topology for build, hairstyle and outfit. No primitive body-part nodes.

const MODEL := preload("res://assets/player_models/models/human.glb")
const SURFACE := preload("res://features/player_models/human_surface.gdshader")
const FACE := preload("res://assets/player_models/textures/face.png")
const SKIN := preload("res://assets/player_models/textures/skin.png")
const FABRIC := preload("res://assets/player_models/textures/fabric.png")
const TROUSERS := preload("res://assets/player_models/textures/trousers.png")
const HAIR := preload("res://assets/player_models/textures/hair.png")
const GEAR := preload("res://assets/player_models/textures/gear.png")
const LEATHER := preload("res://assets/player_models/textures/leather.png")
const DIGITS: Array[String] = ["Thumb", "Index", "Middle", "Ring", "Little"]
## Hand rotation for the 6-7 pose: fingers forward, palm facing the sky.
const PALM_UP := Basis(Vector3.RIGHT, PI / 2.0)
const AnimationBisect := preload("res://features/profiler/animation_bisect.gd")

var skeleton: Skeleton3D
var surface: MeshInstance3D
var material := ShaderMaterial.new()
var _bones: Dictionary = {}
var _shapes: Dictionary = {}
## The imported rig's rest transforms never change during avatar animation.
var _rests: Array[Transform3D] = []
var _rest_bases: Array[Basis] = []
var _parent_rest_inverse: Array[Basis] = []


func _ready() -> void:
	var root := MODEL.instantiate()
	add_child(root)
	_find_nodes(root)
	surface.mesh = PlayerChest.mesh_for(surface.mesh as ArrayMesh)
	material.shader = SURFACE
	for binding: Array in [
		["face_texture", FACE],
		["skin_texture", SKIN],
		["fabric_texture", FABRIC],
		["trousers_texture", TROUSERS],
		["hair_texture", HAIR],
		["gear_texture", GEAR],
		["leather_texture", LEATHER]
	]:
		material.set_shader_parameter(binding[0], binding[1])
	surface.material_override = material
	for index: int in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(index)] = index
		_rests.append(skeleton.get_bone_rest(index))
		_rest_bases.append(skeleton.get_bone_global_rest(index).basis.orthonormalized())
	for index: int in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		_parent_rest_inverse.append(
			_rest_bases[parent].inverse() if parent >= 0 else Basis.IDENTITY
		)
	for index: int in surface.mesh.get_blend_shape_count():
		_shapes[surface.mesh.get_blend_shape_name(index)] = index


func _find_nodes(node: Node) -> void:
	if node is Skeleton3D:
		skeleton = node as Skeleton3D
	if node is MeshInstance3D:
		surface = node as MeshInstance3D
	for child: Node in node.get_children():
		_find_nodes(child)


func apply_appearance(model: BlockPlayerModel) -> void:
	if surface == null:
		return
	material.set_shader_parameter("skin_tint", model.skin_color)
	material.set_shader_parameter("shirt_tint", model.shirt_color)
	material.set_shader_parameter("pants_tint", model.pants_color)
	material.set_shader_parameter("hair_tint", PlayerAppearance.HAIR_COLORS[model.hair_color_index])
	material.set_shader_parameter("eye_tint", PlayerAppearance.EYE_COLORS[model.eye_color_index])
	material.set_shader_parameter("shirt_equipped", not model.shirt_id.is_empty())
	material.set_shader_parameter("pants_equipped", not model.pants_id.is_empty())
	material.set_shader_parameter("tactical", model.outfit == "tactical")
	material.set_shader_parameter("chest_covered", model.chest == "full")
	_shape(PlayerChest.SHAPE, model.chest == "full" and model.body_type != &"penguin")
	material.set_shader_parameter("hair_enabled", model.hair_style != "bald")
	material.set_shader_parameter("hide_head", model.head_type != &"human")
	_shape("Feminine", model.body_type == &"girl")
	_shape(
		"LongHair",
		model.hair_style == "long" or (model.hair_style == "classic" and model.body_type == &"girl")
	)
	_shape("SweptHair", model.hair_style == "swept")
	_shape("CroppedHair", model.hair_style == "crop")
	_shape("Tactical", model.outfit == "tactical")


func _shape(label: String, active: bool) -> void:
	surface.set_blend_shape_value(int(_shapes[label]), 1.0 if active else 0.0)


func shape_weight(label: String) -> float:
	return surface.get_blend_shape_value(int(_shapes[label]))


func pose(model: BlockPlayerModel, left_held: bool, right_held: bool) -> void:
	material.set_shader_parameter("hide_left_arm", left_held)
	material.set_shader_parameter("hide_right_arm", right_held)
	# Leave animation calculations and shader writes active for this narrower bisect.
	if not AnimationBisect.skeleton:
		return
	_bone("Spine", model._torso.rotation)
	_bone("Head", model._head.rotation)
	_bone("UpperArmL", model._left_arm.rotation)
	_bone("UpperArmR", model._right_arm.rotation)
	_bone("ForearmL", model._left_forearm.rotation)
	_bone("ForearmR", model._right_forearm.rotation)
	_bone("ThighL", model._left_leg.rotation)
	_bone("ThighR", model._right_leg.rotation)
	_bone("CalfL", model._left_shin.rotation)
	_bone("CalfR", model._right_shin.rotation)
	for right: bool in [false, true]:
		var hand := int(_bones["HandR" if right else "HandL"])
		var forearm := int(_bones["ForearmR" if right else "ForearmL"])
		for index: int in [forearm, hand]:
			if skeleton.get_bone_pose_position(index) != _rests[index].origin:
				skeleton.set_bone_pose_position(index, _rests[index].origin)
		_set_bone_rotation(hand, _rests[hand].basis.get_rotation_quaternion())
		set_finger_curl(right, 0.12)


func _bone(label: String, rotation: Vector3) -> void:
	var index := int(_bones[label])
	var desired := Basis.from_euler(rotation)
	# Godot bone poses include the local rest rotation; identity would flip limbs
	# whose rest bones point down. Apply animation while retaining that orientation.
	_set_bone_rotation(
		index,
		(_parent_rest_inverse[index] * desired * _rest_bases[index]).get_rotation_quaternion()
	)


func _set_bone_rotation(index: int, rotation: Quaternion) -> void:
	# Rewriting an identical pose still dirties the skeleton in Godot. Read the
	# actual pose so IK/emote overlays are reset correctly on the next body pass.
	if skeleton.get_bone_pose_rotation(index) != rotation:
		skeleton.set_bone_pose_rotation(index, rotation)


## Reach an item grip by bending the existing weighted arm vertices.
func reach_grip(right: bool, world_target: Vector3, fit_item: bool = false) -> void:
	var suffix := "R" if right else "L"
	var upper := skeleton.find_bone("UpperArm" + suffix)
	var forearm := skeleton.find_bone("Forearm" + suffix)
	var wrist := skeleton.find_bone("Hand" + suffix)
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var target := skeleton.to_local(world_target)
	var upper_length := skeleton.get_bone_rest(forearm).origin.length()
	var lower_length := skeleton.get_bone_rest(wrist).origin.length()
	var offset := target - shoulder
	var direction := offset.normalized() if offset.length() > 0.001 else Vector3.DOWN
	# Existing item models have widely spaced grip markers. Translate joint poses
	# to fit those grips while preserving palm/finger size and connected vertices.
	var extension := (
		clampf(offset.length() / (upper_length + lower_length - 0.001), 1.0, 3.0)
		if fit_item
		else 1.0
	)
	skeleton.set_bone_pose_position(forearm, skeleton.get_bone_rest(forearm).origin * extension)
	skeleton.set_bone_pose_position(wrist, skeleton.get_bone_rest(wrist).origin * extension)
	upper_length *= extension
	lower_length *= extension
	var distance := clampf(offset.length(), 0.01, upper_length + lower_length - 0.001)
	var along := (
		(upper_length * upper_length - lower_length * lower_length + distance * distance)
		/ (2.0 * distance)
	)
	var bend := Vector3(0.3 if right else -0.3, -1.0, 0.3)
	bend -= direction * bend.dot(direction)
	if bend.length_squared() < 0.001:
		bend = direction.cross(Vector3.RIGHT)
	bend = bend.normalized()
	var height := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var elbow := shoulder + direction * along + bend * height
	_aim_bone(upper, elbow - shoulder)
	_aim_bone(forearm, shoulder + direction * distance - elbow)
	material.set_shader_parameter("hide_right_arm" if right else "hide_left_arm", false)
	set_finger_curl(right, 0.9)


## Every phalanx has its own weighted bone, editable independently in Blender.
func set_finger_curl(right: bool, amount: float) -> void:
	if not AnimationBisect.fingers:
		return
	for digit: String in DIGITS:
		set_digit_curl(right, digit, amount)


func set_digit_curl(right: bool, digit: String, amount: float) -> void:
	if not AnimationBisect.fingers:
		return
	if digit not in DIGITS:
		return
	var suffix := "R" if right else "L"
	var curl := clampf(amount, 0.0, 1.0)
	for segment: int in 3:
		var index := int(_bones[digit + str(segment + 1) + suffix])
		var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		var global_rest := skeleton.get_bone_global_rest(index).basis.orthonormalized()
		var axis := Vector3.RIGHT
		if digit == "Thumb":
			axis = Vector3.DOWN if right else Vector3.UP
		var local_axis := global_rest.inverse() * axis
		var angle := curl * ([0.75, 1.05, 0.85][segment] as float)
		if digit == "Thumb":
			angle *= 0.65
		_set_bone_rotation(index, rest * Quaternion(local_axis.normalized(), angle))


## Layer the gesture over locomotion or item poses. The middle finger stays straight.
func flip_off(world_wrist: Vector3, facing: Basis, weight: float) -> void:
	left_gesture(world_wrist, facing, weight, 1.0, true)


## Shared left-hand overlay; new gestures retain the right-hand item grip.
func left_gesture(
	world_wrist: Vector3, facing: Basis, weight: float, curl: float, middle_only: bool = false
) -> void:
	var blend := clampf(weight, 0.0, 1.0)
	if blend <= 0.0:
		return
	var hand := skeleton.find_bone("HandL")
	var current := skeleton.get_bone_global_pose(hand)
	var rotations: Dictionary[int, Quaternion] = {}
	for digit: String in DIGITS:
		for segment: int in 3:
			var index := int(_bones[digit + str(segment + 1) + "L"])
			rotations[index] = skeleton.get_bone_pose_rotation(index)
	reach_grip(false, skeleton.to_global(current.origin).lerp(world_wrist, blend), true)
	var rest := skeleton.get_bone_global_rest(hand).basis.orthonormalized()
	var desired := (
		skeleton.global_basis.orthonormalized().inverse() * facing * Basis(Vector3.RIGHT, PI) * rest
	)
	var orientation := current.basis.orthonormalized().slerp(desired, blend)
	var parent := (
		skeleton.get_bone_global_pose(skeleton.get_bone_parent(hand)).basis.orthonormalized()
	)
	skeleton.set_bone_pose_rotation(
		hand, (parent.inverse() * orientation).get_rotation_quaternion()
	)
	set_finger_curl(false, curl)
	if middle_only:
		set_digit_curl(false, "Middle", 0.0)
	for index: int in rotations:
		var target := skeleton.get_bone_pose_rotation(index)
		skeleton.set_bone_pose_rotation(index, rotations[index].slerp(target, blend))


## The "6-7" meme: both palms up in front of the chest, see-sawing like scales.
## `left_wrist`/`right_wrist` are world targets; `facing` is the body basis.
func six_seven(left_wrist: Vector3, right_wrist: Vector3, facing: Basis, weight: float) -> void:
	var blend := clampf(weight, 0.0, 1.0)
	if blend <= 0.0:
		return
	for right: bool in [false, true]:
		var hand := skeleton.find_bone("HandR" if right else "HandL")
		var current := skeleton.get_bone_global_pose(hand)
		var target := right_wrist if right else left_wrist
		reach_grip(right, skeleton.to_global(current.origin).lerp(target, blend), true)
		var rest := skeleton.get_bone_global_rest(hand).basis.orthonormalized()
		var desired := skeleton.global_basis.orthonormalized().inverse() * facing * PALM_UP * rest
		var orientation := current.basis.orthonormalized().slerp(desired, blend)
		var parent := (
			skeleton.get_bone_global_pose(skeleton.get_bone_parent(hand)).basis.orthonormalized()
		)
		skeleton.set_bone_pose_rotation(
			hand, (parent.inverse() * orientation).get_rotation_quaternion()
		)
		set_finger_curl(right, 0.1 * blend)


func orient_grip(right: bool, world_basis: Basis) -> void:
	var hand := skeleton.find_bone("HandR" if right else "HandL")
	var rest := skeleton.get_bone_global_rest(hand).basis.orthonormalized()
	var desired := skeleton.global_basis.orthonormalized().inverse() * world_basis * rest
	var parent := (
		skeleton.get_bone_global_pose(skeleton.get_bone_parent(hand)).basis.orthonormalized()
	)
	skeleton.set_bone_pose_rotation(hand, (parent.inverse() * desired).get_rotation_quaternion())


## First-person shoulders use the same weighted mesh with the body masked out.
func place_shoulder(right: bool, world_position: Vector3) -> void:
	var upper := skeleton.find_bone("UpperArmR" if right else "UpperArmL")
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(upper))
	skeleton.set_bone_pose_position(
		upper, parent.affine_inverse() * skeleton.to_local(world_position)
	)


func _aim_bone(index: int, direction: Vector3) -> void:
	var rest := skeleton.get_bone_global_rest(index).basis.orthonormalized()
	var desired := Basis(Quaternion(rest.y.normalized(), direction.normalized())) * rest
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	skeleton.set_bone_pose_rotation(
		index, (parent_basis.inverse() * desired).get_rotation_quaternion()
	)
