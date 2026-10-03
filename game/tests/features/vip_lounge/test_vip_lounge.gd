extends GutTest

const CLUB := preload("res://features/vip_lounge/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var club: VipLounge
var player: Player
var money: PlayerMoney
var test_time := 200_000


class SlowWallet:
	extends PlayerMoney
	signal complete
	var calls := 0
	var ids: Array[String] = []
	var fail_once := false

	func adjust_account(
		_peer: int, _account_id: int, id: String, delta: int, _reason: String
	) -> Dictionary:
		calls += 1
		ids.append(id)
		if fail_once:
			fail_once = false
			return {"error": "Lost response"}
		await complete
		return {"balance": 200_000 + delta}


func before_each() -> void:
	test_time = 200_000
	money = PlayerMoney.new()
	add_child_autofree(money)
	money.set_process(false)
	money.balances = {1: 200_000}
	club = CLUB.instantiate() as VipLounge
	club.clock = func() -> int: return test_time
	add_child_autofree(club)
	club.set_process(false)
	player = PLAYER.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = Vector3(22, 1, -15)
	player.global_position = player.net_position


func after_each() -> void:
	club.get_node("Menu").close(false)
	Network.peer_accounts = {}
	await get_tree().process_frame


func _enter() -> void:
	var door := club.get_node("Entrance") as VipDoor
	assert_eq(door.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	player.net_position = (club.get_node("UpstairsArrival") as Marker3D).global_position
	player.global_position = player.net_position


func _service(host: String, action: String, options: Dictionary = {}) -> NetworkedEntity.Result:
	var station := club.get_node(host) as VipStation
	player.net_position = station.global_position + Vector3(0.8, 0.9, 0)
	player.global_position = player.net_position
	return station.entity._evaluate(1, &"service", {"action": action, "options": options})


func test_entry_threshold_free_admission_and_exit_with_lower_balance() -> void:
	var door := club.get_node("Entrance") as VipDoor
	money.balances = {1: 199_999}
	assert_eq(door.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_false(club.admitted(1))
	money.balances = {1: 200_000}
	_enter()
	assert_eq(money.balances[1], 200_000)
	assert_true(club.admitted(1))
	assert_true(club.get_node("Destination").available())
	money.balances = {1: 0}
	assert_true(club.admitted(1), "A guest can finish the current visit")
	var exit_door := club.get_node("Exit") as VipDoor
	player.net_position = exit_door.global_position
	assert_eq(exit_door.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_false(club.admitted(1))


func test_exact_sixfold_odds_preserve_losses_and_prize_weights() -> void:
	var ordinary := 0
	var lucky := 0
	var prizes := [0, 0, 0, 0, 0]
	for ticket: int in 125:
		ordinary += int(SlotSpinCycle.is_win(VipRules.reels(ticket, false)))
		var result := VipRules.reels(ticket, true)
		if SlotSpinCycle.is_win(result):
			lucky += 1
			prizes[result[0]] += 1
	assert_eq(ordinary, 5)
	assert_eq(lucky, ordinary * 6)
	assert_eq(prizes, [6, 6, 6, 6, 6])
	assert_false(SlotSpinCycle.is_win(VipRules.reels(124, true)))


func test_private_table_settles_wager_and_win_atomically_and_rejects_forged_stakes() -> void:
	_enter()
	var row := club.record(1)
	row["transaction"] = {
		"kind": "play",
		"id": "b".repeat(64),
		"at": test_time,
		"wager": 10_000,
		"payout": 300_000,
		"reels": [0, 0, 0],
		"collectible": ""
	}
	assert_eq(_service("PrivateTable", "play", {"wager": 10_000}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(money.balances[1], 490_000)
	assert_true(row["played"])
	assert_eq(row["xp"], 10)
	assert_true((row["transaction"] as Dictionary).is_empty())
	var other := club.get_node("PrivateTableTwo") as VipStation
	player.net_position = other.global_position + Vector3(0, 0.9, 1)
	for options: Dictionary in [
		{"wager": -100},
		{"wager": 1},
		{"wager": 10_000, "payout": 300_000},
		{"wager": "10000"},
		{"wager": 10_000.0}
	]:
		assert_eq(
			other.entity._evaluate(1, &"service", {"action": "play", "options": options}),
			NetworkedEntity.Result.DENIED
		)
	assert_eq(money.balances[1], 490_000)


func test_insufficient_private_table_balance_does_not_award_progress_or_charge() -> void:
	_enter()
	money.balances = {1: 9999}
	assert_eq(_service("PrivateTable", "play", {"wager": 10_000}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(money.balances[1], 9999)
	assert_false(club.record(1)["played"])
	assert_eq(club.record(1)["xp"], 0)
	assert_true((club.record(1)["transaction"] as Dictionary).is_empty())


func test_gift_rarity_boosts_are_independent_and_expire() -> void:
	var row := VipRules.empty_record()
	assert_almost_eq(VipRules.rare_chance(row, test_time), 0.05, 0.0001)
	row["velvet"] = test_time + 600
	assert_almost_eq(VipRules.rare_chance(row, test_time), 0.2, 0.0001)
	row["luck"] = test_time + 300
	assert_eq(VipRules.rare_chance(row, test_time), 1.0)
	assert_almost_eq(VipRules.rare_chance(row, test_time + 300), 0.2, 0.0001)
	assert_almost_eq(VipRules.rare_chance(row, test_time + 600), 0.05, 0.0001)


func test_drink_expiration_cooldown_nonstacking_and_progression() -> void:
	_enter()
	var hand := _new_hand()
	assert_eq(_service("Jade", "luck"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(hand.net_item_id, "luck_cocktail")
	assert_eq(club.profile(1)["luck"], 0, "Ordering does not activate the boost")
	hand.request_primary_action()
	assert_true(hand.consumption.active())
	assert_eq(club.profile(1)["luck"], 0, "Boost waits for the drinking animation")
	hand._process(3.1)
	assert_eq(hand.net_item_id, "")
	assert_eq(club.profile(1)["luck"], 300)
	assert_false(club.allowed(1, "luck", {}))
	assert_eq(club.record(1)["luck"], test_time + 300)
	test_time += 300
	club._publish()
	assert_eq(club.profile(1)["luck"], 0)
	assert_eq(club.profile(1)["luck_ready"], 1500)
	test_time += 1500
	assert_true(club.allowed(1, "luck", {}))
	assert_true(club.act(1, "golden", {}, (club.get_node("Jade") as VipStation).entity))
	hand.request_primary_action()
	hand._process(3.1)
	var row := club.record(1)
	VipRules.progress(row, 10, test_time)
	assert_eq(row["xp"], 20)
	assert_eq(_service("Jade", "velvet"), NetworkedEntity.Result.COOLDOWN, "Endpoint cooldown")


func _new_hand() -> Hand:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	return hand


func test_full_or_loading_inventory_does_not_spend_drink_order_cooldown() -> void:
	_enter()
	var hand := _new_hand()
	hand.net_item_id = "banana"
	hand.inventory().backpack.fill("beer")
	var endpoint := (club.get_node("Jade") as VipStation).entity
	assert_false(club.act(1, "luck", {}, endpoint))
	assert_eq(club.record(1)["luck_ready"], 0)
	assert_eq(hand.net_item_id, "banana")
	hand.inventory().backpack.fill("")
	hand.inventory().loading = true
	assert_false(club.act(1, "luck", {}, endpoint))
	assert_eq(club.record(1)["luck_ready"], 0)
	hand.inventory().loading = false
	assert_true(club.act(1, "luck", {}, endpoint))
	assert_eq(hand.inventory().backpack[0], "luck_cocktail")
	hand.inventory().request_equip(0)
	assert_eq(hand.net_item_id, "luck_cocktail")
	assert_eq(hand.inventory().backpack[0], "banana")


func test_all_drinks_use_normal_inventory_and_activate_only_for_the_consumer() -> void:
	var hand := _new_hand()
	for action: String in VipRules.DRINK_ITEMS:
		var id: String = VipRules.DRINK_ITEMS[action]
		hand.inventory().restore({"hand": id})
		assert_eq(hand.net_item_id, id, "Saved inventory recognizes the drink")
		assert_eq(hand.inventory().snapshot()["hand"], id)
		assert_eq(
			hand.consumption.entity._evaluate(2, &"consume", {}), NetworkedEntity.Result.DENIED
		)
		assert_eq(
			hand.consumption.entity._evaluate(1, &"consume", {"duration": 9000}),
			NetworkedEntity.Result.DENIED
		)
		hand.request_primary_action()
		assert_true(hand.consumption.active(), "A carried drink works outside the lounge")
		hand.request_drop_item()
		hand.inventory().request_stow(-1)
		assert_eq(hand.net_item_id, id, "Drinking locks the item against transfer")
		hand._process(3.1)
		assert_eq(hand.net_item_id, "")
		assert_eq(club.profile(1)[action], 300 if action == "luck" else 600)
		assert_eq(club.record(1)[action + "_ready"], 0, "Using a gifted item does not order it")
		hand.net_item_id = id
		hand.request_primary_action()
		assert_false(hand.consumption.active(), "Active boosts cannot be extended or stacked")
		assert_eq(hand.net_item_id, id, "Denied use keeps the item")
		hand.net_item_id = ""


func test_interrupted_drink_does_not_grant_a_boost() -> void:
	var hand := _new_hand()
	hand.net_item_id = "luck_cocktail"
	hand.request_primary_action()
	hand.consumption._died(1, 2)
	assert_eq(hand.net_item_id, "")
	assert_eq(club.record(1)["luck"], 0)
	hand.net_item_id = "golden_hour"
	hand.request_primary_action()
	hand.consumption.entity.session_reset.emit(Network.Mode.OFFLINE)
	assert_eq(hand.net_item_id, "")
	assert_eq(club.record(1)["golden"], 0)


func test_drink_views_have_grip_mouth_and_correct_floor_clearance() -> void:
	for id: String in VipRules.DRINK_ITEMS.values():
		var definition := ItemCatalog.find(id)
		assert_eq(definition.category, ItemDefinition.Category.FOOD)
		assert_eq(ItemCatalog.uses_remaining(id), 1)
		var view := ItemCatalog.create_view(id)
		add_child_autofree(view)
		assert_not_null(view.get_node_or_null("Grip"))
		assert_not_null(view.get_node_or_null("Mouth"))
		var glass := view.get_node("Glass") as MeshInstance3D
		var bottom := glass.position.y + glass.mesh.get_aabb().position.y * glass.scale.y
		assert_almost_eq(bottom + definition.ground_clearance, 0.0, 0.001)
		assert_gt((view.get_node("Mouth") as Marker3D).position.y, 0.08)


func test_gift_is_once_per_utc_day_and_does_not_reset_on_reentry() -> void:
	_enter()
	assert_eq(_service("Scarlett", "gift"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(money.balances[1], 205_000)
	assert_eq(club.record(1)["collection"].size(), 1)
	assert_false(club.allowed(1, "gift", {}))
	club.leave(1)
	player.net_position = Vector3(22, 1, -15)
	var door := club.get_node("Entrance") as VipDoor
	assert_true(club.enter(player, door.entity))
	assert_false(club.allowed(1, "gift", {}))
	test_time = VipRules.next_day(test_time)
	assert_true(club.allowed(1, "gift", {}))


func test_forged_payloads_wrong_station_unknown_peer_and_outside_room_are_denied() -> void:
	_enter()
	var jade := club.get_node("Jade") as VipStation
	player.net_position = jade.global_position + Vector3(-1, 0.9, 0)
	for payload: Dictionary in [
		{},
		{"action": "luck"},
		{"action": "luck", "options": {}, "peer": 1},
		{"action": "luck", "options": {"duration": 90000}},
		{"action": "gift", "options": {}},
		{"action": 1, "options": {}},
		{"action": "luck", "options": []}
	]:
		assert_eq(jade.entity._evaluate(1, &"service", payload), NetworkedEntity.Result.DENIED)
	assert_eq(
		jade.entity._evaluate(99, &"service", {"action": "luck", "options": {}}),
		NetworkedEntity.Result.DENIED
	)
	player.net_position.y = 1.0
	assert_eq(
		jade.entity._evaluate(1, &"service", {"action": "luck", "options": {}}),
		NetworkedEntity.Result.DENIED
	)
	assert_eq(money.balances[1], 200_000)


func test_mission_and_clothing_use_existing_wallet_and_inventory_once() -> void:
	_enter()
	assert_false(club.allowed(1, "mission", {}))
	var row := club.record(1)
	row["hosts"] = ["Scarlett", "Jade", "Valentina"]
	row["symbol"] = true
	row["played"] = true
	assert_eq(_service("Valentina", "mission"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(money.balances[1], 210_000)
	assert_true(row["mission"])
	assert_false(club.allowed(1, "mission", {}))
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	var station := club.get_node("Valentina") as VipStation
	assert_true(club.act(1, "shirt", {}, station.entity))
	assert_eq(hand.inventory().shirt, "shirt:7")
	assert_false(club.act(1, "shirt", {}, station.entity))
	assert_eq(VipRules.title_for(row), "House Favorite")


func test_ambiguous_reward_retry_keeps_same_id_and_blocks_concurrent_requests() -> void:
	_enter()
	money.remove_from_group(&"player_money")
	var slow := SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	slow.balances = {1: 200_000}
	slow.fail_once = true
	assert_eq(_service("Scarlett", "gift"), NetworkedEntity.Result.ACCEPTED)
	var tx: Dictionary = club.record(1)["transaction"]
	assert_false(tx.is_empty())
	var station := club.get_node("Scarlett") as VipStation
	assert_true(club.act(1, "gift", {}, station.entity))
	assert_false(club.act(1, "gift", {}, station.entity))
	assert_eq(slow.calls, 2)
	assert_eq(slow.ids[0], slow.ids[1])
	slow.complete.emit()
	await get_tree().process_frame
	assert_true((club.record(1)["transaction"] as Dictionary).is_empty())
	assert_false(club.allowed(1, "gift", {}))


func test_store_roundtrip_persists_absolute_deadlines_and_retry_intent() -> void:
	var store := VipStore.new()
	store.path = "user://vip-test-%d.json" % get_instance_id()
	var row := VipRules.empty_record()
	row["discovered"] = true
	row["luck"] = test_time + 300
	row["gift_ready"] = VipRules.next_day(test_time)
	row["transaction"] = {
		"kind": "gift",
		"id": "a".repeat(64),
		"at": test_time,
		"wager": 0,
		"payout": 5000,
		"reels": [],
		"collectible": "Amber coupe"
	}
	store.records = {"123": row}
	assert_true(store.save())
	var restored := VipStore.new()
	restored.path = store.path
	restored.load_records()
	assert_eq(restored.records["123"]["transaction"]["id"], "a".repeat(64))
	assert_eq(VipRules.seconds(restored.records["123"], "luck", test_time + 400), 0)
	assert_false(VipStore.valid_record({"discovered": true}))
	DirAccess.remove_absolute(store.path)


func test_saved_gridmap_layout_and_window_barrier() -> void:
	var deck := club.get_node("Interior/Deck") as GridMap
	assert_eq(deck.get_used_cells().size(), 192)
	assert_eq(deck.get_cell_item(Vector3i(20, 20, 0)), 6)
	for cell: Vector3i in deck.get_used_cells():
		assert_gte(deck.to_global(deck.map_to_local(cell)).x - 0.5, 24.0, "No overhang into casino")
	var interior := club.get_node("Interior") as Node3D
	assert_eq((interior.get_node("Ceiling") as GridMap).get_used_cells().size(), 192)
	assert_eq((interior.get_node("OuterWall") as GridMap).get_used_cells().size(), 48)
	assert_eq((interior.get_node("Roof") as StaticBody3D).global_position, Vector3(28, 8.85, 0))
	assert_true(
		VipLounge.BOUNDS.has_point((club.get_node("UpstairsArrival") as Node3D).global_position)
	)
	var casino := preload("res://features/casino_hub/casino_gridmap.tscn").instantiate() as Node3D
	add_child_autofree(casino)
	var window := casino.get_node("VipWindow") as Node3D
	assert_eq(window.global_position, Vector3(24, 6.875, 0))
	var barrier := window.get_node("WindowBarrier") as StaticBody3D
	assert_eq((barrier.get_node("Shape") as CollisionShape3D).shape.size, Vector3(0.08, 3.75, 24))
	var upper := casino.get_node("PitStructure/UpperWallsEastWest") as GridMap
	for z: int in range(-12, 12):
		assert_eq(upper.get_cell_item(Vector3i(23, 0, z)), GridMap.INVALID_CELL_ITEM)
	for z: int in [-20, -13, 12, 19]:
		assert_eq(upper.get_cell_item(Vector3i(23, 0, z)), 14, "Adjacent wall panels stay intact")
	await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(23, 6.8, 0), Vector3(25, 6.8, 0), 1)
	assert_eq(casino.get_world_3d().direct_space_state.intersect_ray(ray).get("collider"), barrier)
	for name: String in ["Scarlett", "Jade", "Valentina"]:
		assert_gte((club.get_node(name) as VipStation).age, 18)
	assert_false(club.get_node("Destination").available())


func test_modal_open_close_and_menu_stays_in_range() -> void:
	_enter()
	var station := club.get_node("Jade") as VipStation
	player.net_position = station.global_position + Vector3(-1.5, 0.9, 0)
	assert_true(club.talk(1, "Jade", station.entity))
	var menu: CanvasLayer = club.get_node("Menu")
	assert_true(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing)
	assert_eq(menu.buttons.size(), 3)
	menu.close()
	assert_true(Controls.playing)
	assert_false(menu.is_in_group(&"modal_ui"))
