class_name HeldArms
extends Node3D
## First-person hands use the same skinned human mesh and finger bones. Creature
## costumes also use this rig for their item grips, with non-arm surfaces masked.

var human := SkinnedHuman.new()
var _right := Node3D.new()
var _left := Node3D.new()
var _glove := StandardMaterial3D.new()
var _sleeve := StandardMaterial3D.new()


func _ready() -> void:
	_right.name = "RightGlove"
	_left.name = "LeftGlove"
	add_child(_right)
	add_child(_left)
	add_child(human)
	human.material.set_shader_parameter("arms_only", true)
	human.material.set_shader_parameter("shirt_equipped", true)
	set_skin_color(PlayerSkin.TONES[0])
	set_sleeve_color(Color(0.17, 0.32, 0.40))


func set_sleeve_color(color: Color) -> void:
	_sleeve.albedo_color = color
	human.material.set_shader_parameter("shirt_tint", color)


func set_skin_color(color: Color) -> void:
	_glove.albedo_color = color
	human.material.set_shader_parameter("skin_tint", color)


func pose(right_shoulder: Vector3, left_shoulder: Vector3, support: Node3D) -> void:
	_right.transform = Transform3D.IDENTITY
	_left.visible = support != null
	if support != null:
		_left.global_transform = support.global_transform
	human.place_shoulder(true, to_global(right_shoulder))
	human.reach_grip(true, _right.to_global(Vector3(0.055, -0.04, 0.055)), true)
	human.orient_grip(true, _right.global_basis.orthonormalized())
	human.material.set_shader_parameter("hide_left_arm", support == null)
	if support != null:
		human.place_shoulder(false, to_global(left_shoulder))
		human.reach_grip(false, _left.to_global(Vector3(-0.055, -0.04, 0.055)), true)
		human.orient_grip(false, _left.global_basis.orthonormalized())
