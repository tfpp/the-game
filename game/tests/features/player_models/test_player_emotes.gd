extends GutTest

const PLAYER := preload("res://core/player/player.tscn")
const FEATURE := preload("res://features/player_models/feature.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var _player: Player
var _models: PlayerModels
var _avatar: BlockPlayerModel
var _view: Node3D


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_models = FEATURE.instantiate() as PlayerModels
	add_child_autofree(_models)
	_models.set_process(false)
	_models._process(0)
	_avatar = _player.get_node("Body/Avatar") as BlockPlayerModel
	_avatar.set_process(false)
	_view = _models.get_node("EmoteView") as Node3D
	_view.set_process(false)


func after_each() -> void:
	await get_tree().process_frame


func _start() -> void:
	assert_eq(
		_models.entity._evaluate(1, &"emote", {"name": "flip_off"}), NetworkedEntity.Result.ACCEPTED
	)
	_models.emote_clock = 1.0


func test_server_rejects_unknown_emotes_forged_identity_and_missing_players() -> void:
	for payload: Dictionary in [
		{},
		{"name": "dance"},
		{"name": 42},
		{"name": "flip_off", "peer_id": 2},
		{"name": "flip_off", "started": 999}
	]:
		assert_eq(_models.entity._evaluate(1, &"emote", payload), NetworkedEntity.Result.DENIED)
	assert_eq(
		_models.entity._evaluate(77, &"emote", {"name": "flip_off"}), NetworkedEntity.Result.DENIED
	)
	assert_true(_models.emotes.is_empty())
	_models.entity.set_multiplayer_authority(2)
	assert_eq(
		_models.entity._evaluate(1, &"emote", {"name": "flip_off"}), NetworkedEntity.Result.DENIED
	)


func test_emote_cooldown_is_per_peer_and_starts_only_on_the_server() -> void:
	var other := Node.new()
	other.set_multiplayer_authority(2)
	add_child_autofree(other)
	other.add_to_group(&"players")
	_start()
	var original: Dictionary = _models.emotes[1].duplicate()
	assert_eq(
		_models.entity._evaluate(1, &"emote", {"name": "flip_off"}), NetworkedEntity.Result.DENIED
	)
	assert_eq(_models.emotes[1], original)
	assert_eq(
		_models.entity._evaluate(2, &"emote", {"name": "flip_off"}), NetworkedEntity.Result.ACCEPTED
	)
	assert_eq(_models.emotes[2]["started"], _models.emote_clock)
	_models.emote_clock = PlayerModels.EMOTE_COOLDOWN
	assert_eq(
		_models.entity._evaluate(1, &"emote", {"name": "flip_off"}), NetworkedEntity.Result.ACCEPTED
	)


func test_replicated_timeline_resumes_current_phase_and_expires() -> void:
	_models.emote_clock = 20.0
	assert_true(_models._apply_emote(1, {"name": "flip_off"}))
	_models.emote_clock = 21.25
	assert_almost_eq(_models.emote_elapsed(1), 1.25, 0.001)
	assert_eq(_models.emote_weight(1), 1.0)
	assert_eq(PlayerModels.emote_envelope(0.0), 0.0)
	assert_gt(PlayerModels.emote_envelope(0.15), 0.0)
	assert_lt(PlayerModels.emote_envelope(2.8), 1.0)
	_models.emote_clock = 23.0
	_models._process(0)
	assert_false(_models.emotes.has(1))
	assert_eq(_models.emote_elapsed(1), -1.0)


func test_disconnect_despawn_and_session_reset_clear_emotes() -> void:
	_start()
	_models._remove_peer(1)
	assert_true(_models.emotes.is_empty())
	assert_true(_models._emote_ready.is_empty())
	_start()
	_models._reset_session(Network.Mode.OFFLINE)
	assert_true(_models.emotes.is_empty())
	assert_eq(_models.emote_clock, 0.0)
	assert_true(_models._emote_ready.is_empty())
	_start()
	_player.queue_free()
	_models._expire_emotes()
	assert_true(_models.emotes.is_empty())


func test_late_join_waits_for_the_clock_snapshot_before_presenting_the_emote() -> void:
	_models.emotes = {1: {"name": "flip_off", "started": 10.0}}
	_models._clock_received = false
	assert_eq(_models.emote_elapsed(1), -1.0)
	_models.emote_clock = 11.4
	assert_almost_eq(_models.emote_elapsed(1), 1.4, 0.001)
	assert_eq(_models.emote_weight(1), 1.0)


func test_third_person_gesture_raises_the_hand_and_only_extends_the_middle_finger() -> void:
	_start()
	(_player.get_node("Body") as Node3D).show()
	_avatar.animate(0.1, Vector3(0, 0, -4), true, 8)
	var skeleton := _avatar.human.skeleton
	var thigh := skeleton.get_bone_pose_rotation(skeleton.find_bone("ThighL"))
	_view._process(0)
	assert_false(_view.first_person.visible)
	assert_eq(skeleton.get_bone_pose_rotation(skeleton.find_bone("ThighL")), thigh)
	assert_gt(skeleton.get_bone_global_pose(skeleton.find_bone("HandL")).origin.y, 0.3)
	for segment: int in 3:
		var middle := skeleton.find_bone("Middle" + str(segment + 1) + "L")
		var rest := skeleton.get_bone_rest(middle).basis.get_rotation_quaternion()
		assert_almost_eq(absf(skeleton.get_bone_pose_rotation(middle).dot(rest)), 1.0, 0.001)
	var index := skeleton.find_bone("Index1L")
	assert_lt(
		absf(
			skeleton.get_bone_pose_rotation(index).dot(
				skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
			)
		),
		0.95
	)


func test_first_person_unarmed_gesture_and_camera_switch_share_network_state() -> void:
	_start()
	_avatar.animate(0.1, Vector3.ZERO, true, 8)
	_view._process(0)
	assert_true(_view.first_person.visible)
	assert_true(bool(_view.first_person.material.get_shader_parameter("hide_right_arm")))
	var human: SkinnedHuman = _view.first_person
	var wrist := human.skeleton.find_bone("HandL")
	var position := (_player.get_node("Camera") as Node3D).to_local(
		human.skeleton.to_global(human.skeleton.get_bone_global_pose(wrist).origin)
	)
	assert_lt(position.z, -0.3)
	assert_gt(position.y, -0.2)
	(_player.get_node("Body") as Node3D).show()
	_view._process(0)
	assert_false(human.visible)
	assert_eq(_models.emote_elapsed(1), 1.0)


func test_emoting_with_a_weapon_keeps_it_equipped_and_restores_support_hand() -> void:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	hand.net_item_id = "shotgun"
	hand._process(0)
	_start()
	_avatar.animate(0.1, Vector3.ZERO, true, 8, 0, true, true)
	hand._process(0)
	_view._process(0)
	assert_eq(hand.net_item_id, "shotgun")
	assert_true(hand.visible)
	assert_true(bool(hand._arms.human.material.get_shader_parameter("hide_left_arm")))
	assert_true(_view.first_person.visible)
	_models.emote_clock = PlayerModels.EMOTE_SECONDS
	_models._process(0)
	_avatar.animate(0.1, Vector3.ZERO, true, 8, 0, true, true)
	hand._process(0)
	_view._process(0)
	assert_false(_view.first_person.visible)
	assert_false(bool(hand._arms.human.material.get_shader_parameter("hide_left_arm")))


func test_penguin_gesture_restores_the_costume_afterwards() -> void:
	_start()
	_avatar.set_body_type("penguin")
	_avatar.animate(0.1, Vector3.ZERO, true, 8)
	_view._process(0)
	assert_true(_avatar.human.visible)
	assert_true(bool(_avatar.human.material.get_shader_parameter("arms_only")))
	assert_false(_avatar._left_arm.visible)
	_models.emote_clock = PlayerModels.EMOTE_SECONDS
	_models._process(0)
	_avatar.animate(0.1, Vector3.ZERO, true, 8)
	_view._process(0)
	assert_false(_avatar.human.visible)
	assert_true(_avatar._left_arm.visible)


func test_new_names_use_existing_authority_cooldown_and_timeline() -> void:
	for emote: String in ["wave", "salute", "cheer"]:
		_models._reset_session(Network.Mode.OFFLINE)
		assert_eq(
			_models.entity._evaluate(1, &"emote", {"name": emote}), NetworkedEntity.Result.ACCEPTED
		)
		assert_eq(_models.emote_name(1), emote)
		assert_eq(
			_models.entity._evaluate(1, &"emote", {"name": "flip_off"}),
			NetworkedEntity.Result.DENIED
		)
		_models._clock_received = false
		assert_eq(_models.emote_elapsed(1), -1.0)
		_models.emote_clock = 1.25
		assert_almost_eq(_models.emote_elapsed(1), 1.25, 0.001)
		_models._remove_peer(1)
		assert_true(_models.emotes.is_empty())


func test_new_gestures_show_in_both_views_and_restore_penguin() -> void:
	for emote: String in ["wave", "salute", "cheer"]:
		_models._reset_session(Network.Mode.OFFLINE)
		assert_true(_models._apply_emote(1, {"name": emote}))
		_models.emote_clock = 1.0
		_avatar.set_body_type("penguin")
		_avatar.animate(0.1, Vector3.ZERO, true, 8)
		_view._process(0)
		assert_true(_view.first_person.visible)
		assert_true(_avatar.human.visible)
		assert_false(_avatar._left_arm.visible)
		var skeleton: Skeleton3D = _view.first_person.skeleton
		var wrist := skeleton.find_bone("HandL")
		var at := (_player.get_node("Camera") as Node3D).to_local(
			skeleton.to_global(skeleton.get_bone_global_pose(wrist).origin)
		)
		assert_lt(at.z, -0.3)
		var digit := skeleton.find_bone("Index1L")
		var rest := skeleton.get_bone_rest(digit).basis.get_rotation_quaternion()
		var alignment := absf(skeleton.get_bone_pose_rotation(digit).dot(rest))
		if emote == "cheer":
			assert_lt(alignment, 0.95, "Cheer closes a fist")
		else:
			assert_almost_eq(alignment, 1.0, 0.001, "Wave/salute extend fingers")
		(_player.get_node("Body") as Node3D).show()
		_view._process(0)
		assert_false(_view.first_person.visible)
		_models.emote_clock = PlayerModels.EMOTE_SECONDS
		_models._process(0)
		_avatar.animate(0.1, Vector3.ZERO, true, 8)
		_view._process(0)
		assert_false(_avatar.human.visible)
		assert_true(_avatar._left_arm.visible)
		(_player.get_node("Body") as Node3D).hide()


func test_new_gestures_keep_weapon_and_restore_support_hand() -> void:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	hand.net_item_id = "shotgun"
	for emote: String in ["wave", "salute", "cheer"]:
		_models._reset_session(Network.Mode.OFFLINE)
		assert_true(_models._apply_emote(1, {"name": emote}))
		_models.emote_clock = 1.0
		_avatar.animate(0.1, Vector3.ZERO, true, 8, 0, true, true)
		hand._process(0)
		_view._process(0)
		assert_eq(hand.net_item_id, "shotgun")
		assert_true(hand.visible)
		assert_true(bool(hand._arms.human.material.get_shader_parameter("hide_left_arm")))
		_models.emote_clock = PlayerModels.EMOTE_SECONDS
		_models._process(0)
		_avatar.animate(0.1, Vector3.ZERO, true, 8, 0, true, true)
		hand._process(0)
		_view._process(0)
		assert_false(_view.first_person.visible)
		assert_false(bool(hand._arms.human.material.get_shader_parameter("hide_left_arm")))
