extends GutTest

const DEALER := preload("res://features/casino_patrons/card_dealer.tscn")
const SALON := preload("res://features/casino_hub/salon.tscn")
## Salon card table collision top: body centre y -1.03 + half of 0.94, above floor -1.5.
const TABLE_TOP := 0.94
const TABLE_NEAR_EDGE := 0.415


func test_hands_hover_over_the_table_in_front_of_the_dealer() -> void:
	for step: int in 40:
		var time := step * 0.137
		var left := CardDealerModel.hand_target(time, false)
		var right := CardDealerModel.hand_target(time, true)
		assert_gt(left.y, TABLE_TOP + 0.1)
		assert_gt(right.y, TABLE_TOP + 0.1)
		assert_lt(left.y, TABLE_TOP + 0.35)
		assert_gt(left.z, TABLE_NEAR_EDGE)
		assert_gt(right.z, TABLE_NEAR_EDGE)
		# Facing +Z, the dealer's left hand is on +X.
		assert_gt(left.x, 0.0)
		assert_lt(right.x, 0.0)


func test_hands_move_subtly() -> void:
	var start := CardDealerModel.hand_target(0.0, true)
	var later := CardDealerModel.hand_target(CardDealerModel.PERIOD_S * 0.25, true)
	var distance := start.distance_to(later)
	assert_gt(distance, 0.03)
	assert_lt(distance, 0.2)


func test_dealer_uses_player_rig_in_tux_and_animates_wrists() -> void:
	var npc := DEALER.instantiate() as StationaryPatron
	add_child_autofree(npc)
	var body := npc.get_node("Body") as CardDealerModel
	var model := body.model
	assert_is(model, BlockPlayerModel)
	assert_true(model.human.material.get_shader_parameter("tuxedo"))
	assert_not_null(model.human.material.get_shader_parameter("tux_texture"))
	assert_true(model.human.material.get_shader_parameter("pants_equipped"))
	assert_true(npc.is_in_group(&"killable"))
	var hitbox := npc.get_node("Hitbox") as CollisionShape3D
	assert_gt((hitbox.shape as BoxShape3D).size.y, 1.6, "hitbox covers the standing body")
	var skeleton := model.human.skeleton
	var wrist := skeleton.find_bone("HandR")
	var before := skeleton.to_global(skeleton.get_bone_global_pose(wrist).origin)
	body._process(CardDealerModel.PERIOD_S * 0.25)
	var after := skeleton.to_global(skeleton.get_bone_global_pose(wrist).origin)
	assert_gt(before.distance_to(after), 0.02)
	var local := npc.to_local(after)
	assert_gt(local.y, TABLE_TOP, "wrist stays above the felt")
	assert_gt(local.z, 0.2, "wrist reaches forward over the table")


func test_texture_respects_size_limit() -> void:
	var texture := CardDealerModel.TUX
	assert_lte(texture.get_width(), 128)
	assert_lte(texture.get_height(), 128)


func test_salon_card_dealers_use_new_model_and_staff_share_the_tux() -> void:
	var salon := SALON.instantiate()
	add_child_autofree(salon)
	for index: int in 3:
		var dealer := salon.get_node("Dealer%d" % index)
		assert_is(dealer.get_node("Body"), CardDealerModel)
	var bartender := salon.get_node("Bartender/Body") as CardDealerModel
	assert_not_null(bartender, "the bartender wears the same tux")
	assert_false(bartender.dealing, "the bartender stands at ease")
	var phases := {}
	for index: int in 3:
		phases[(salon.get_node("Dealer%d/Body" % index) as CardDealerModel).seed_phase] = true
	assert_eq(phases.size(), 3, "dealers move out of step")
