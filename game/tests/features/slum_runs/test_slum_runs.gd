extends GutTest

const RUN_SCENE := preload("res://features/slum_runs/feature.tscn")
const ALLEY_SCENE := preload("res://features/slum_alley/alley.tscn")
const GARAGE_SCENE := preload("res://features/procedural_rooms/prototype.tscn")
const HAND_SCENE := preload("res://features/holdables/hand.tscn")
const PLAYER_SCENE := preload("res://core/player/player.tscn")


class FakeHoldables:
	extends Node3D
	var drops: Array[Dictionary] = []

	func _ready() -> void:
		add_to_group(&"holdables_root")

	func spawn_thrown_item(item_id: String, from: Vector3, to: Vector3) -> void:
		drops.append({"id": item_id, "from": from, "to": to})


func after_each() -> void:
	for toast: Node in get_tree().get_nodes_in_group(LootToast.GROUP):
		toast.free()


func _features() -> Node3D:
	var features := Node3D.new()
	add_child_autofree(features)
	return features


func _run(features: Node3D) -> SlumRuns:
	var run := RUN_SCENE.instantiate() as SlumRuns
	run.name = "slum_runs"
	features.add_child(run)
	return run


func _alley(features: Node3D) -> Node3D:
	var alley := ALLEY_SCENE.instantiate() as Node3D
	alley.name = "slum_alley"
	features.add_child(alley)
	return alley


func _player(at: Vector3) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "1"
	player.position = at
	player.net_position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func _hand() -> Hand:
	var hand := HAND_SCENE.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	return hand


func test_alley_has_a_return_route_searchable_dumpsters_and_failed_lights() -> void:
	var features := _features()
	_run(features)
	var alley := _alley(features)
	var arrival := alley.get_node("District/Arrival") as SlumArrivalPoint
	var door := alley.get_node("District/ReturnDoor") as GarageDoor
	assert_true(arrival.is_in_group(&"slum_arrival_points"))
	assert_not_null(door.get_node_or_null(door.destination))
	var loot_count := 0
	for node: Node in get_tree().get_nodes_in_group(LootContainer.GROUP):
		if alley.is_ancestor_of(node):
			loot_count += 1
	assert_eq(loot_count, 4)
	var street_mesh := (alley.get_node("District/StreetDetails") as MeshInstance3D).mesh
	var dumpster_mesh := (alley.get_node("District/DumpsterNorth/Model") as MeshInstance3D).mesh
	assert_not_null(street_mesh)
	assert_not_null(dumpster_mesh)
	assert_true(street_mesh.get_surface_count() <= 9)
	assert_true(dumpster_mesh.get_surface_count() <= 9)
	assert_not_null(alley.get_node_or_null("District/Rain"))
	for lamp_name: String in ["StreetLampNorth", "StreetLampCenter", "StreetLampSouth"]:
		assert_eq(
			(alley.get_node("District/" + lamp_name) as FluorescentLight).mode,
			FluorescentLight.Mode.STEADY
		)
	assert_eq(
		(alley.get_node("District/StreetLampEast") as FluorescentLight).mode,
		FluorescentLight.Mode.DEAD
	)


func test_a_shared_run_resets_loot_once_and_keeps_late_arrivals_together() -> void:
	var features := _features()
	var runs := _run(features)
	var alley := _alley(features)
	var garage := GARAGE_SCENE.instantiate() as Node3D
	garage.name = "procedural_rooms"
	features.add_child(garage)
	var arrival := alley.get_node("District/Arrival") as SlumArrivalPoint
	var container := alley.get_node("District/DumpsterNorth/Loot") as LootContainer
	container.net_searched = true
	runs.begin(1, arrival)
	assert_false(container.net_searched)
	container.net_searched = true
	runs.begin(2, garage.get_node("Garage/Arrival") as SlumArrivalPoint)
	assert_true(container.net_searched)
	assert_eq(runs.choose_arrival(), arrival)
	runs.finish(1)
	assert_eq(runs.choose_arrival(), arrival)
	runs.finish(2)
	runs.begin(3, arrival)
	assert_false(container.net_searched)


func test_retired_gate_is_scenery_and_legacy_return_door_still_closes_a_run() -> void:
	var features := _features()
	var runs := _run(features)
	var alley := _alley(features)
	var gate := runs.get_node("Gate") as CSGBox3D
	assert_null(gate.get_script())
	assert_false(gate.is_in_group(&"interactables"), "Public excursions use the Crown elevator")
	var player := _player(gate.global_position)
	var arrival := alley.get_node("District/Arrival") as SlumArrivalPoint
	runs.begin(1, arrival)
	assert_true(runs.is_active(1))
	var return_door := alley.get_node("District/ReturnDoor") as GarageDoor
	player.net_position = return_door.global_position
	return_door.request_enter()
	assert_false(runs.is_active(1))
	assert_true(
		player.net_position.is_equal_approx(
			(runs.get_node("CasinoArrival") as Marker3D).global_position
		)
	)


func test_slum_death_drops_only_valuables_for_other_players() -> void:
	var features := _features()
	var runs := _run(features)
	var alley := _alley(features)
	var arrival := alley.get_node("District/Arrival") as SlumArrivalPoint
	var player := _player(arrival.global_position)
	var hand := _hand()
	var holdables := FakeHoldables.new()
	add_child_autofree(holdables)
	assert_true(hand.inventory().collect("watch"))
	assert_true(hand.inventory().collect("scrap"))
	runs.begin(1, arrival)
	runs._on_player_died(1, 2)
	assert_false(runs.is_active(1))
	assert_eq(holdables.drops.size(), 2)
	assert_eq(hand.inventory().take_first_valuable(), "")
	assert_true(holdables.drops[0]["from"].distance_to(player.net_position) < 1.0)


func test_combat_death_scatter_happens_at_the_slum_position() -> void:
	var combat := Combat.new()
	add_child_autofree(combat)
	var features := _features()
	var runs := _run(features)
	var alley := _alley(features)
	var arrival := alley.get_node("District/Arrival") as SlumArrivalPoint
	_player(arrival.global_position)
	var hand := _hand()
	var holdables := FakeHoldables.new()
	add_child_autofree(holdables)
	assert_true(hand.inventory().collect("watch"))
	runs.begin(1, arrival)
	combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	assert_eq(holdables.drops.size(), 1)
	assert_true((holdables.drops[0]["from"] as Vector3).distance_to(arrival.global_position) < 1.0)


func test_fence_pays_once_for_a_reserved_valuable() -> void:
	var features := _features()
	var runs := _run(features)
	var fence := runs.get_node("Fence") as LootFence
	_player(fence.global_position)
	var hand := _hand()
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	assert_true(hand.inventory().collect("watch"))
	await fence.request_sell()
	assert_eq(int(wallet.balances.get(1, 0)), 3000)
	assert_eq(hand.inventory().take_first_valuable(), "")
	await fence.request_sell()
	assert_eq(int(wallet.balances.get(1, 0)), 3000)


func test_all_tiers_and_saved_cash_sell_once_at_the_catalog_price() -> void:
	var features := _features()
	var fence := _run(features).get_node("Fence") as LootFence
	var player := _player(fence.global_position)
	var hand := _hand()
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {1: 2000}
	var total := 2000
	for id: String in ["scrap", "stolen_wallet", "electronics", "watch", "jewelry", "cash_bundle"]:
		assert_true(hand.inventory().collect(id))
		player.net_position = fence.global_position + Vector3.RIGHT * 10
		await fence.request_sell()
		assert_eq(int(wallet.balances[1]), total, "Out-of-range sale is rejected")
		assert_eq(hand.net_item_id, id)
		player.net_position = fence.global_position
		await fence.request_sell()
		total += ItemCatalog.find(id).sale_value_cents
		assert_eq(int(wallet.balances[1]), total)
		assert_eq(hand.net_item_id, "")
		await fence.request_sell()
		assert_eq(int(wallet.balances[1]), total, "Repeated Use cannot duplicate a sale")


func test_pawn_shop_display_case_matches_counter_and_offers_trading() -> void:
	var runs := _run(_features())
	var fence := runs.get_node("Fence") as LootFence
	assert_eq(fence.interaction_text(), "Trade · Buy guns and ammo / sell valuables")
	var case_node := fence.get_node("DisplayCase") as Node3D
	var frame := case_node.get_node("Frame") as MeshInstance3D
	var bounds := frame.mesh.get_aabb()
	assert_almost_eq(case_node.global_position.y + bounds.position.y, 0.0, .001)
	assert_almost_eq(bounds.size, fence.size, Vector3.ONE * .001)
	var phone := case_node.get_node("Phone") as Node3D
	assert_almost_eq(phone.global_position.y, fence.global_position.y + fence.size.y * .5, .001)
	var sign := case_node.get_node("CashSign") as SignBoard
	assert_string_contains(sign.text, "BUY - SELL - TRADE")


func test_death_message_lists_dropped_valuables_and_kept_weapons() -> void:
	var watch := ItemCatalog.find("watch").display_name
	var scrap := ItemCatalog.find("scrap").display_name
	assert_eq(
		SlumRuns.death_penalty_message(PackedStringArray(["watch"])),
		"You dropped %s. Your weapons were kept." % watch
	)
	assert_eq(
		SlumRuns.death_penalty_message(PackedStringArray(["watch", "scrap", "watch"])),
		"You dropped %s, %s and %s. Your weapons were kept." % [watch, scrap, watch]
	)
	assert_eq(
		SlumRuns.death_penalty_message(PackedStringArray()),
		"You had no valuables to drop. Your weapons were kept."
	)


func test_slum_death_message_waits_for_the_respawn() -> void:
	var combat := Combat.new()
	add_child_autofree(combat)
	var features := _features()
	var runs := _run(features)
	var alley := _alley(features)
	var arrival := alley.get_node("District/Arrival") as SlumArrivalPoint
	_player(arrival.global_position)
	var hand := _hand()
	var holdables := FakeHoldables.new()
	add_child_autofree(holdables)
	assert_true(hand.inventory().collect("watch"))
	runs.begin(1, arrival)
	combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	var toast := get_tree().get_first_node_in_group(LootToast.GROUP) as LootToast
	assert_true(toast == null or not toast.shown_text().begins_with("You dropped"))
	combat._announce_respawn(1)
	toast = get_tree().get_first_node_in_group(LootToast.GROUP) as LootToast
	assert_not_null(toast)
	assert_eq(toast.shown_text(), SlumRuns.death_penalty_message(PackedStringArray(["watch"])))


func test_crown_death_sends_no_slum_message() -> void:
	var features := _features()
	var runs := _run(features)
	_player(Vector3.ZERO)
	_hand()
	runs._on_player_died(1, 2)
	var toast := get_tree().get_first_node_in_group(LootToast.GROUP) as LootToast
	assert_true(toast == null or toast.shown_text().is_empty())
