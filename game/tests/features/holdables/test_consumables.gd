extends GutTest

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _hand: Hand
var _player: Player


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hand.set_process(false)


func after_each() -> void:
	await get_tree().process_frame


func test_primary_reserves_one_item_then_consumes_without_touching_backpack() -> void:
	_hand.inventory().collect("cigarette")
	_hand.inventory().collect("beer")
	_hand.request_primary_action()
	assert_true(_hand.consumption.active())
	assert_eq(_hand.consumption.view_id(), "cigarette")
	_hand.request_primary_action()
	_hand.request_drop_item()
	_hand.inventory().request_stow(-1)
	_hand.inventory().request_equip(0)
	_hand.inventory().request_drop(-1)
	assert_eq(_hand.net_item_id, "cigarette")
	assert_eq(_hand.inventory().backpack[0], "beer")
	_hand._process(3.1)
	assert_false(_hand.consumption.active())
	assert_eq(_hand.net_item_id, "")
	assert_eq(_hand.inventory().backpack[0], "beer")
	_hand.inventory().request_equip(0)
	assert_eq(_hand.net_item_id, "beer")


func test_foreign_payload_missing_player_and_non_authority_requests_fail() -> void:
	_hand.net_item_id = "beer"
	var entity := _hand.consumption.entity
	assert_eq(entity._evaluate(2, &"consume", {}), NetworkedEntity.Result.DENIED)
	assert_eq(entity._evaluate(1, &"consume", {"item": "beer"}), NetworkedEntity.Result.DENIED)
	entity.set_multiplayer_authority(2)
	assert_eq(entity._evaluate(1, &"consume", {}), NetworkedEntity.Result.DENIED)
	entity.set_multiplayer_authority(1)
	_player.free()
	assert_eq(entity._evaluate(1, &"consume", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_hand.net_item_id, "beer")


func test_beer_uses_bar_stats_once_and_cigarettes_do_not_change_them() -> void:
	var bar := preload("res://features/bar_companion/feature.tscn").instantiate() as BarCompanion
	add_child_autofree(bar)
	bar.set_process(false)
	_hand.net_item_id = "beer"
	_hand.request_primary_action()
	_hand.request_primary_action()
	assert_eq(bar.intoxication_for(1), 1)
	_hand._process(3.1)
	_hand.net_item_id = "cigarette"
	_hand.request_primary_action()
	assert_eq(bar.intoxication_for(1), 1)
	assert_eq(bar.intoxication_for(2), 0)


func test_smoke_only_runs_while_using_and_snapshot_resumes_in_progress() -> void:
	_hand.net_item_id = "cigarette"
	_hand._process(0)
	var smoke := _hand.held_view().get_node("Smoke") as CPUParticles3D
	assert_false(smoke.emitting)
	_hand.request_primary_action()
	_hand._process(1.2)
	assert_true(smoke.emitting)
	var late := HAND.instantiate() as Hand
	late.peer_id = 1
	add_child_autofree(late)
	late.set_process(false)
	late.net_item_id = _hand.net_item_id
	late.consumption.state = _hand.consumption.state.duplicate()
	late._process(0)
	assert_almost_eq(late.global_position, _hand.global_position, Vector3.ONE * 0.001)
	assert_true((late.held_view().get_node("Smoke") as CPUParticles3D).emitting)
	var sync := late.consumption.entity.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:state")))
	late._process(2.0)
	assert_null(late.held_view())


func test_original_food_still_consumes_instantly_and_unstarted_items_can_stow() -> void:
	_hand.net_item_id = "banana"
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")
	assert_false(_hand.consumption.active())
	_hand.net_item_id = "beer"
	_hand.inventory().request_stow(-1)
	assert_eq(_hand.net_item_id, "")
	assert_eq(_hand.inventory().backpack[0], "beer")


func test_death_and_session_reset_finish_reserved_item_without_refund() -> void:
	for reset: bool in [false, true]:
		_hand.net_item_id = "cigarette"
		_hand.request_primary_action()
		if reset:
			_hand.consumption.entity.session_reset.emit(Network.Mode.OFFLINE)
		else:
			_hand.consumption._died(1, 2)
		assert_false(_hand.consumption.active())
		assert_eq(_hand.net_item_id, "")


func test_two_players_consume_independently() -> void:
	var second := PLAYER.instantiate() as Player
	second.name = "2"
	second.set_multiplayer_authority(2)
	add_child_autofree(second)
	second.set_physics_process(false)
	var other := HAND.instantiate() as Hand
	other.peer_id = 2
	add_child_autofree(other)
	other.set_process(false)
	_hand.net_item_id = "beer"
	other.net_item_id = "cigarette"
	_hand.request_primary_action()
	assert_eq(
		other.consumption.entity._evaluate(2, &"consume", {}), NetworkedEntity.Result.ACCEPTED
	)
	_hand._process(3.1)
	assert_true(other.consumption.active())
	other._process(3.1)
	assert_eq(other.net_item_id, "")


func test_rig_reaches_mouth_in_both_views_and_all_creature_bodies() -> void:
	var avatar := BlockPlayerModel.new()
	avatar.name = "Avatar"
	_player.get_node("Body").add_child(avatar)
	avatar.set_process(false)
	for body_type: String in ["default", "girl", "penguin"]:
		avatar.set_body_type(body_type)
		for head_type: String in ["human", "frog", "bird"]:
			avatar.set_head_type(head_type)
			for first_person: bool in [false, true]:
				(_player.get_node("Body") as Node3D).visible = not first_person
				for id: String in ["beer", "cigarette"]:
					_hand.net_item_id = id
					_hand.consumption.state = {"item": id, "left": 1.5}
					_hand._process(0)
					var contact := _hand.held_view().get_node("Mouth") as Marker3D
					var mouth := avatar.mouth_transform().origin
					if first_person:
						mouth = (_player.get_node("Camera") as Node3D).to_global(
							Vector3(0.025, -0.1, -0.18)
						)
					assert_almost_eq(contact.global_position, mouth, Vector3.ONE * 0.001)
					var human := (
						_hand._arms.human
						if first_person or body_type == "penguin"
						else avatar.human
					)
					var wrist := human.skeleton.find_bone("HandR")
					var actual := human.skeleton.to_global(
						human.skeleton.get_bone_global_pose(wrist).origin
					)
					assert_almost_eq(
						actual, _hand.to_global(Vector3(0.055, -0.04, 0.055)), Vector3.ONE * 0.003
					)


func test_cigarette_finger_pose_restores_the_regular_grip_when_switching_items() -> void:
	_hand.net_item_id = "cigarette"
	_hand._process(0)
	var skeleton := _hand._arms.human.skeleton
	var index := skeleton.find_bone("Index2R")
	var cigarette_pose := skeleton.get_bone_pose_rotation(index)
	_hand.net_item_id = "beer"
	_hand._process(0)
	var beer_pose := skeleton.get_bone_pose_rotation(index)
	assert_gt(cigarette_pose.angle_to(beer_pose), 0.1)
	_hand.net_item_id = "cigarette"
	_hand._process(0)
	assert_almost_eq(skeleton.get_bone_pose_rotation(index).angle_to(cigarette_pose), 0.0, 0.001)
