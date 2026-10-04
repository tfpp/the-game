extends GutTest

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const FENCE := preload("res://features/slum_runs/loot_fence.gd")


func test_selected_sale_rejects_stale_slots_and_nonvaluables() -> void:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	hand.inventory().backpack = PackedStringArray(
		["scrap", "pistol", "ammo:pistol:20", "", "", "", "", ""]
	)
	assert_eq(hand.inventory().take_valuable_at(0, "watch"), "")
	assert_eq(hand.inventory().item_at(0), "scrap")
	assert_eq(hand.inventory().take_valuable_at(1, "pistol"), "")
	assert_eq(hand.inventory().take_valuable_at(2, "ammo:pistol:20"), "")
	assert_eq(hand.inventory().take_valuable_at(-2, "scrap"), "")
	hand.inventory().loading = true
	assert_eq(hand.inventory().take_valuable_at(0, "scrap"), "")
	hand.inventory().loading = false
	assert_eq(hand.inventory().take_valuable_at(0, "scrap"), "scrap")
	assert_eq(hand.inventory().take_valuable_at(0, "scrap"), "")


func test_trade_requests_validate_sender_range_and_stock() -> void:
	var fence := CSGBox3D.new()
	fence.set_script(FENCE)
	add_child_autofree(fence)
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	var menu := fence.get_node("TradeMenu")
	assert_true(menu.call("_may_buy", 1, {"id": "m4a4"}))
	assert_true(menu.call("_may_buy", 1, {"id": "ammo:ak47:60"}))
	assert_false(menu.call("_may_buy", 2, {"id": "pistol"}))
	assert_false(menu.call("_may_buy", 1, {"id": "hat:1"}))
	assert_false(menu.call("_may_buy", 1, {"id": "pistol", "price": 1}))
	assert_false(menu.call("_may_sell", 1, {"slot": 0, "id": "scrap", "peer": 2}))
	player.net_position = Vector3(20, 0, 0)
	assert_false(menu.call("_may_buy", 1, {"id": "pistol"}))


func test_rifle_magazines_are_independent_and_reload_to_thirty() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	hand.inventory().backpack = PackedStringArray(
		["ammo:smg:40", "ammo:m4a4:60", "ammo:ak47:60", "ammo:smg:40", "", "", "", ""]
	)
	for id: String in ["smg", "m4a4", "ak47"]:
		hand.net_item_id = id
		var magazine := hand.magazine_for(id)
		magazine.advance(0)
		assert_eq(magazine.loaded(), 30)
		for shot: int in 30:
			assert_true(magazine.can_fire())
			hand.inventory().spend_ammo(id)
			magazine.record_shot()
		assert_false(magazine.can_fire())
		assert_eq(hand.inventory().ammo_for(id), 50 if id == "smg" else 30)
		assert_eq(magazine.entity._evaluate(2, &"reload", {}), NetworkedEntity.Result.DENIED)
		assert_eq(magazine.entity._evaluate(1, &"reload", {}), NetworkedEntity.Result.ACCEPTED)
		assert_false(magazine.can_fire())
		magazine.advance(2.3)
		assert_eq(magazine.loaded(), 30)
	assert_eq(hand.magazine_for("smg").loaded(), 30)
