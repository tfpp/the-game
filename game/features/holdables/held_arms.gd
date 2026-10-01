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


## Shared by catalog items and generated weapons with authored grip markers.
func pose_for_player(player: Player, support: Node3D, skin: Color) -> void:
	set_skin_color(skin)
	var body := player.get_node("Body") as Node3D
	var avatar := body.get_node_or_null("Avatar")
	if avatar != null and avatar.has_method("sleeve_color"):
		set_sleeve_color(avatar.call("sleeve_color"))
	else:
		set_sleeve_color(skin)
	var first_person := player.is_local() and not body.visible
	visible = true
	if not first_person and avatar is BlockPlayerModel and avatar.human.visible:
		visible = false
		avatar.human.reach_grip(true, to_global(Vector3(0.055, -0.04, 0.055)), true)
		avatar.human.orient_grip(true, global_basis.orthonormalized())
		if support != null:
			avatar.human.reach_grip(false, support.to_global(Vector3(-0.055, -0.04, 0.055)), true)
			avatar.human.orient_grip(false, support.global_basis.orthonormalized())
		return
	if not first_person and avatar != null and avatar.has_method("shoulder_position"):
		pose(
			to_local(avatar.call("shoulder_position", true)),
			to_local(avatar.call("shoulder_position", false)),
			support
		)
		return
	var shoulders: Transform3D
	if first_person:
		shoulders = (player.get_node("Camera") as Node3D).global_transform
		var factor := HeldItemPose.avatar_height_scale(body)
		shoulders.basis = shoulders.basis.scaled(Vector3.ONE * factor)
		shoulders.origin += shoulders.basis * Vector3(0, -0.36, 0.10)
	else:
		var yaw := player.yaw if player.is_local() else body.global_rotation.y
		shoulders = Transform3D(Basis(Vector3.UP, yaw), body.global_position)
		shoulders.origin.y += 0.30
	pose(
		to_local(shoulders * Vector3(0.32, 0, 0)),
		to_local(shoulders * Vector3(-0.32, 0, 0)),
		support
	)
