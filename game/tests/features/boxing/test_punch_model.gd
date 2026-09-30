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


func test_disconnect_and_session_change_clear_cosmetics() -> void:
	boxing.punch(1, 0.0)
	boxing._forget_peer(1)
	assert_true(boxing.arm_pose(1).is_empty())
	boxing._fists.swing(1, true)
	boxing._on_mode_changed(Network.Mode.OFFLINE)
	assert_true(boxing.arm_pose(1).is_empty())


func test_held_item_pose_keeps_priority() -> void:
	boxing.punch(1, 0.0)
	avatar.animate(1.0, Vector3.ZERO, true, 8.0, 0.0, true)
	assert_almost_eq(avatar._left_arm.rotation.x, 0.0, 0.001)
	assert_true(bool(avatar.human.material.get_shader_parameter("hide_right_arm")))
