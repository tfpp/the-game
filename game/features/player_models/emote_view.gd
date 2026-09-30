extends Node3D
## Cosmetic overlays run after locomotion and held-item poses. All timing comes
## from PlayerModels' server-owned emote state and replicated animation clock.

var first_person := SkinnedHuman.new()

@onready var models: PlayerModels = get_parent() as PlayerModels


func _ready() -> void:
	process_priority = 25
	first_person.name = "FirstPersonEmote"
	add_child(first_person)
	first_person.material.set_shader_parameter("arms_only", true)
	first_person.hide()


func _process(_delta: float) -> void:
	first_person.hide()
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or player.is_queued_for_deletion():
			continue
		var body := player.get_node("Body") as Node3D
		var avatar := body.get_node_or_null("Avatar") as BlockPlayerModel
		if avatar == null:
			continue
		var costume := avatar.body_type == &"penguin"
		avatar.human.visible = not costume
		avatar.human.material.set_shader_parameter("arms_only", false)
		var peer := player.get_multiplayer_authority()
		var weight := models.emote_weight(peer)
		if weight <= 0.0:
			continue
		avatar.human.visible = true
		if models.emote_name(peer) == PlayerModels.SIX_SEVEN:
			_six_seven(player, body, avatar, costume, weight, models.emote_elapsed(peer))
			continue
		if costume:
			avatar._left_arm.hide()
			avatar.human.material.set_shader_parameter("arms_only", true)
			avatar.human.material.set_shader_parameter("hide_right_arm", true)
		var name := models.emote_name(peer)
		var elapsed := models.emote_elapsed(peer)
		_left_pose(avatar.human, avatar.human, name, elapsed, weight, false)
		if not player.is_local() or body.visible or Network.mode == Network.Mode.SERVER:
			continue
		var camera := player.get_node_or_null("Camera") as Camera3D
		if camera == null:
			continue
		first_person.show()
		first_person.global_transform = camera.global_transform
		first_person.pose(avatar, false, false)
		first_person.material.set_shader_parameter("hide_right_arm", true)
		first_person.material.set_shader_parameter("skin_tint", avatar.skin_color)
		first_person.material.set_shader_parameter("shirt_tint", avatar.sleeve_color())
		first_person.material.set_shader_parameter(
			"shirt_equipped", not avatar.shirt_id.is_empty() or avatar.outfit == "tactical"
		)
		first_person.place_shoulder(false, camera.to_global(Vector3(-0.28, -0.36, 0.05)))
		_left_pose(first_person, camera, name, elapsed, weight, true)


## Distinct left-hand targets, in avatar or camera space (-Z is forward).
static func gesture_target(emote: String, elapsed: float, camera: bool) -> Vector3:
	var sway := sin(elapsed * TAU * 2.0)
	match emote:
		"wave":
			return (
				Vector3(-0.23 + sway * 0.08, 0.04, -0.45)
				if camera
				else Vector3(-0.4 + sway * 0.08, 0.65, -0.25)
			)
		"salute":
			return Vector3(-0.15, 0.08, -0.36) if camera else Vector3(-0.15, 0.74, -0.22)
		"cheer":
			return (
				Vector3(-0.23, 0.08 + sway * 0.06, -0.4)
				if camera
				else Vector3(-0.3, 0.9 + sway * 0.08, -0.16)
			)
	return Vector3(-0.16, -0.09, -0.42) if camera else Vector3(-0.26, 0.43, -0.38)


func _left_pose(
	human: SkinnedHuman, space: Node3D, emote: String, elapsed: float, weight: float, camera: bool
) -> void:
	var wrist := gesture_target(emote, elapsed, camera)
	if camera:
		wrist = Vector3(-0.22, -0.42, -0.18).lerp(wrist, weight)
		human.reach_grip(false, space.to_global(wrist), true)
	var facing := space.global_basis.orthonormalized()
	if emote == "flip_off":
		human.flip_off(space.to_global(wrist), facing, weight)
		return
	if emote == "wave":
		facing *= Basis(Vector3.FORWARD, sin(elapsed * TAU * 2.0) * 0.35)
	elif emote == "salute":
		facing *= Basis(Vector3.FORWARD, -PI / 2.0)
	human.left_gesture(space.to_global(wrist), facing, weight, 1.0 if emote == "cheer" else 0.0)


## Wrist height offset for the see-saw: left rises while right falls, twice a second.
static func six_seven_bob(elapsed: float) -> float:
	return 0.09 * sin(maxf(elapsed, 0.0) * TAU * 2.0)


func _six_seven(
	player: Player,
	body: Node3D,
	avatar: BlockPlayerModel,
	costume: bool,
	weight: float,
	elapsed: float
) -> void:
	var bob := six_seven_bob(elapsed)
	if costume:
		avatar._left_arm.hide()
		avatar._right_arm.hide()
		avatar.human.material.set_shader_parameter("arms_only", true)
	avatar.human.material.set_shader_parameter("hide_left_arm", false)
	avatar.human.material.set_shader_parameter("hide_right_arm", false)
	avatar.human.six_seven(
		avatar.human.to_global(Vector3(-0.22, 0.3 + bob, -0.34)),
		avatar.human.to_global(Vector3(0.22, 0.3 - bob, -0.34)),
		avatar.human.global_basis.orthonormalized(),
		weight
	)
	if not player.is_local() or body.visible or Network.mode == Network.Mode.SERVER:
		return
	var camera := player.get_node_or_null("Camera") as Camera3D
	if camera == null:
		return
	first_person.show()
	first_person.global_transform = camera.global_transform
	first_person.pose(avatar, false, false)
	first_person.material.set_shader_parameter("skin_tint", avatar.skin_color)
	first_person.material.set_shader_parameter("shirt_tint", avatar.sleeve_color())
	first_person.material.set_shader_parameter(
		"shirt_equipped", not avatar.shirt_id.is_empty() or avatar.outfit == "tactical"
	)
	first_person.place_shoulder(false, camera.to_global(Vector3(-0.28, -0.36, 0.05)))
	first_person.place_shoulder(true, camera.to_global(Vector3(0.28, -0.36, 0.05)))
	first_person.six_seven(
		camera.to_global(Vector3(-0.2, -0.24 + bob * weight, -0.42)),
		camera.to_global(Vector3(0.2, -0.24 - bob * weight, -0.42)),
		camera.global_basis.orthonormalized(),
		weight
	)
