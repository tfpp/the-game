extends GutTest
## The rigged crouch and crouch-walk poses, for your own and other players' avatars.

const PLAYER := preload("res://core/player/player.tscn")
const CROUCH := preload("res://features/crouch/feature.tscn")
const MODELS := preload("res://features/player_models/feature.tscn")


func test_crouch_pose_bends_knees_and_lowers_the_rig() -> void:
	var idle := BlockPlayerMotion.crouch_pose(0.0, Vector3.ZERO, 8.0)
	assert_eq(idle["state"], &"crouch")
	assert_gt(float(idle["left_leg"]), 1.0, "thighs forward")
	assert_lt(float(idle["left_shin"]), -2.0, "knees bent back")
	assert_gt(float(idle["drop"]), 0.3)
	var walk := BlockPlayerMotion.crouch_pose(PI * 0.5, Vector3(0, 0, -2.5), 8.0)
	assert_eq(walk["state"], &"crouch_walk")
	assert_ne(walk["left_leg"], walk["right_leg"], "legs alternate while crouch walking")
	var back := BlockPlayerMotion.crouch_pose(PI * 0.5, Vector3(0, 0, 2.5), 8.0)
	assert_almost_eq(float(back["left_leg"]), float(walk["right_leg"]), 0.001, "steps reverse")


func test_avatar_follows_crouch_state_for_remote_players() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "4"
	player.set_multiplayer_authority(4)
	add_child_autofree(player)
	var crouch := CROUCH.instantiate() as Crouch
	add_child_autofree(crouch)
	var models := MODELS.instantiate() as PlayerModels
	add_child_autofree(models)
	models.set_process(false)
	models._process(0)
	var avatar := player.get_node("Body/Avatar") as BlockPlayerModel
	avatar.set_process(false)
	crouch.crouched = {4: true}
	for i: int in 30:
		avatar._process(1.0 / 60.0)
	assert_true(avatar.crouched)
	assert_eq(avatar.locomotion, &"crouch")
	assert_lt(avatar._rig.position.y, -0.3, "rig lowered")
	var bone := avatar.human.skeleton.find_bone("CalfL")
	var calf := avatar.human.skeleton.get_bone_pose_rotation(bone)
	crouch.crouched = {}
	for i: int in 30:
		avatar._process(1.0 / 60.0)
	assert_false(avatar.crouched)
	assert_gt(avatar._rig.position.y, -0.05, "stands back up")
	assert_false(
		calf.is_equal_approx(avatar.human.skeleton.get_bone_pose_rotation(bone)),
		"the skinned rig's knee bones move"
	)
	await get_tree().process_frame


func test_crouched_players_are_noticed_at_half_distance() -> void:
	assert_eq(GarageEnemyTiers.notice_radius(10.0, false), 10.0)
	assert_eq(GarageEnemyTiers.notice_radius(10.0, true), 5.0)
