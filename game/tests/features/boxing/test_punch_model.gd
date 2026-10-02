extends GutTest

const PLAYER := preload("res://core/player/player.tscn")
const MODELS := preload("res://features/player_models/feature.tscn")
const BOXING := preload("res://features/boxing/feature.tscn")

var player: Player
var avatar: BlockPlayerModel
var boxing: Boxing


func before_each() -> void:
	player = PLAYER.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	player.set_process(false)
	var models := MODELS.instantiate() as PlayerModels
	add_child_autofree(models)
	models._process(0.0)
	avatar = player.get_node("Body/Avatar") as BlockPlayerModel
	avatar.set_process(false)
	boxing = BOXING.instantiate() as Boxing
	add_child_autofree(boxing)
	boxing.set_process(false)
	boxing._fists.set_process(false)
	boxing._kicks.set_process(false)


func test_accepted_jab_moves_connected_arm_and_closes_fingers() -> void:
	avatar.animate(1.0, Vector3.ZERO, true, 8.0)
	var bone := avatar.human.skeleton.find_bone("Index1L")
	var relaxed := avatar.human.skeleton.get_bone_pose_rotation(bone)
	boxing.punch(1, 0.0)
	boxing._fists._process(BoxingFists.SWING_S * 0.35)
	avatar.animate(0.01, Vector3.ZERO, true, 8.0)
	assert_almost_eq(avatar._left_arm.rotation.x, PI * 0.5, 0.001)
	assert_gt(avatar._right_forearm.rotation.x, 1.0)
	assert_ne(avatar.human.skeleton.get_bone_pose_rotation(bone), relaxed)
	assert_true(boxing.arm_pose(7).is_empty(), "No cross-player pose")
	boxing._fists._process(1.0)
	avatar.animate(1.0, Vector3.ZERO, true, 8.0)
	assert_true(boxing.arm_pose(1).is_empty())
	assert_almost_eq(avatar._left_arm.rotation.x, 0.0, 0.001)
	assert_eq(avatar.human.skeleton.get_bone_pose_rotation(bone), relaxed)


func test_power_punch_moves_right_arm_for_every_body() -> void:
	for body: String in ["default", "girl", "penguin"]:
		avatar.set_body_type(body)
		boxing._ready_at_ms.clear()
		boxing.punch(1, BoxingMath.FULL_CHARGE_S)
		boxing._fists._process(BoxingFists.POWER_SWING_S * 0.35)
		avatar.animate(0.01, Vector3(0, 0, -4), true, 8.0)
		assert_almost_eq(avatar._right_arm.rotation.x, PI * 0.5, 0.001, body)
		assert_gt(avatar._left_forearm.rotation.x, 1.0, body)


func test_cooldown_does_not_restart_swing_and_world_has_no_extra_fists() -> void:
	boxing.punch(1, 0.0)
	boxing._fists._process(0.05)
	var pose := boxing.arm_pose(1)
	boxing.punch(1, 0.0)
	assert_eq(boxing.arm_pose(1), pose)
	var body := player.get_node("Body") as Node3D
	body.show()
	boxing._fists._process(0.0)
	assert_false(boxing._fists._views[1].visible)
	body.hide()
	boxing._fists._process(0.0)
	assert_true(boxing._fists._views[1].visible)


func test_first_person_uses_matching_rig_and_camera_space_wrists() -> void:
	(player.get_node("Body") as Node3D).hide()
	avatar.set_body_type("girl")
	avatar.set_skin_index(3)
	avatar.set_clothing("", "")
	player.get_node("Camera").rotation = Vector3(0.3, 0.7, 0.0)
	boxing._fists.swing(1, false)
	boxing._fists._process(BoxingFists.SWING_S * 0.35)
	var view := boxing._fists._views[1]
	var hands := view.get_node("Hands") as SkinnedHuman
	assert_true(bool(hands.material.get_shader_parameter("arms_only")))
	assert_eq(hands.material.get_shader_parameter("skin_tint"), avatar.skin_color)
	assert_eq(hands.shape_weight("Feminine"), 1.0)
	for right: bool in [false, true]:
		var bone := hands.skeleton.find_bone("HandR" if right else "HandL")
		var wrist := view.to_local(
			hands.skeleton.to_global(hands.skeleton.get_bone_global_pose(bone).origin)
		)
		assert_almost_eq(wrist.x, 0.2 if right else -0.2, 0.01)
		assert_almost_eq(wrist.y, -0.2, 0.01)
		assert_almost_eq(wrist.z, -0.4 if right else -0.85, 0.01)
	boxing._fists._process(1.0)
	assert_false(view.visible)


func test_disconnect_and_session_change_clear_cosmetics() -> void:
	boxing.punch(1, 0.0)
	boxing._forget_peer(1)
	assert_true(boxing.arm_pose(1).is_empty())
	boxing._fists.swing(1, true)
	boxing._on_mode_changed(Network.Mode.OFFLINE)
	assert_true(boxing.arm_pose(1).is_empty())


func test_kick_moves_leg_for_human_girl_and_penguin_without_moving_item_arms() -> void:
	for body: String in ["default", "girl", "penguin"]:
		avatar.set_body_type(body)
		boxing._ready_at_ms.clear()
		boxing.punch(1, 1.0, true)
		boxing._kicks._process(BoxingKicks.POWER_S * 0.35)
		avatar.animate(0.01, Vector3.ZERO, true, 8.0, 0.0, true)
		assert_almost_eq(avatar._right_leg.rotation.x, PI * 0.5, 0.001, body)
		assert_almost_eq(avatar._right_shin.rotation.x, -0.08, 0.001, body)
		assert_almost_eq(avatar._right_arm.rotation.x, 0.0, 0.001, body)
		assert_true(boxing.leg_pose(7).is_empty())
	boxing._kicks._process(1.0)
	avatar.animate(1.0, Vector3.ZERO, true, 8.0)
	assert_true(boxing.leg_pose(1).is_empty())
	assert_almost_eq(avatar._right_leg.rotation.x, 0.0, 0.001)


func test_first_person_kick_uses_appearance_and_hides_when_third_person() -> void:
	var body := player.get_node("Body") as Node3D
	body.hide()
	avatar.set_body_type("girl")
	avatar.set_skin_index(3)
	boxing._kicks.swing(1, true)
	boxing._kicks._process(BoxingKicks.POWER_S * 0.35)
	var view := boxing._kicks._views[1]
	var leg := view.get_node("Leg") as SkinnedHuman
	assert_true(view.visible)
	assert_true(bool(leg.material.get_shader_parameter("right_leg_only")))
	assert_eq(leg.shape_weight("Feminine"), 1.0)
	assert_eq(leg.material.get_shader_parameter("skin_tint"), avatar.skin_color)
	body.show()
	boxing._kicks._process(0.0)
	assert_false(view.visible)
	body.hide()
	avatar.set_body_type("penguin")
	boxing._kicks._process(0.0)
	assert_false(leg.visible)
	assert_true((view.get_node("Penguin") as Node3D).visible)
	boxing._forget_peer(1)
	assert_true(boxing.leg_pose(1).is_empty())
	assert_false(boxing._kicks._views.has(1))


func test_held_item_pose_keeps_priority() -> void:
	boxing.punch(1, 0.0)
	avatar.animate(1.0, Vector3.ZERO, true, 8.0, 0.0, true)
	assert_almost_eq(avatar._left_arm.rotation.x, 0.0, 0.001)
	assert_true(bool(avatar.human.material.get_shader_parameter("hide_right_arm")))
