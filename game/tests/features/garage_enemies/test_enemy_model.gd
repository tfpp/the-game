extends GutTest
## Every tier wears the player avatar rig, dressed and armed for its role.


func _model(tier: int, index: int = 0) -> GarageEnemyModel:
	var model := GarageEnemyModel.new()
	add_child_autofree(model)
	model.equip(tier, index)
	return model


func test_every_tier_uses_the_player_rig() -> void:
	for tier: int in GarageEnemyTiers.STRENGTH:
		var model := _model(tier)
		assert_true(model.avatar is BlockPlayerModel)
		assert_true(model.avatar.human.visible)


func test_brawlers_are_ragged_and_unarmed() -> void:
	var model := _model(GarageEnemyTiers.Tier.LURKER)
	assert_null(model.held)
	assert_not_null(model.torso_items.get_node_or_null("Rag0"))
	assert_not_null(model.torso_items.get_node_or_null("Patch"))


func test_knifers_hold_a_knife_and_gunmen_a_pistol() -> void:
	var knifer := _model(GarageEnemyTiers.Tier.STALKER)
	assert_eq(knifer.held.name, "Knife")
	var gunman := _model(GarageEnemyTiers.Tier.GUNMAN)
	assert_eq(gunman.held.name, "Pistol")
	assert_eq(gunman.avatar.outfit, "tactical")


func test_weapon_follows_the_hand_when_aiming() -> void:
	var gunman := _model(GarageEnemyTiers.Tier.GUNMAN)
	gunman.animate(0.016, 0.0, true)
	var hand := gunman.to_local(gunman.hand_position(true))
	assert_almost_eq(gunman.held.position.distance_to(hand), 0.0, 0.001)
	assert_lt(hand.z, -0.3, "aims forward (-Z)")
	assert_gt(hand.y, 1.1, "at shoulder height")


func test_brawler_throws_a_punch_forward() -> void:
	var brawler := _model(GarageEnemyTiers.Tier.LURKER)
	brawler.animate(0.016, 0.0, true)
	var guard := brawler.to_local(brawler.hand_position(true))
	brawler.strike()
	brawler.animate(0.016, 0.0, false)
	var jab := brawler.to_local(brawler.hand_position(true))
	assert_lt(jab.z, guard.z - 0.15, "the punch extends forward")


func test_variants_differ_within_a_tier() -> void:
	var a := GarageEnemyModel.variant(GarageEnemyTiers.Tier.LURKER, 0)
	var b := GarageEnemyModel.variant(GarageEnemyTiers.Tier.LURKER, 1)
	assert_ne(a, b)
