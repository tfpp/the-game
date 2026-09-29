extends GutTest

const RUN_SCENE := preload("res://features/slum_runs/feature.tscn")
const ALLEY_SCENE := preload("res://features/slum_alley/feature.tscn")
const GARAGE_SCENE := preload("res://features/parking_garage/feature.tscn")
const HAND_SCENE := preload("res://features/holdables/hand.tscn")
const PLAYER_SCENE := preload("res://core/player/player.tscn")


class FakeHoldables:
	extends Node3D
	var drops: Array[Dictionary] = []

	func _ready() -> void:
		add_to_group(&"holdables_root")

	func spawn_thrown_item(item_id: String, from: Vector3, to: Vector3) -> void:
		drops.append({"id": item_id, "from": from, "to": to})


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
	garage.name = "parking_garage"
	features.add_child(garage)
	var arrival := alley.get_node("District/Arrival") as SlumArrivalPoint
	var container := alley.get_node("District/DumpsterNorth/Loot") as LootContainer
	container.net_searched = true
	runs.begin(1, arrival)
	assert_false(container.net_searched)
	container.net_searched = true
	runs.begin(2, garage.get_node("Garage/GarageArrival") as SlumArrivalPoint)
	assert_true(container.net_searched)
	assert_eq(runs.choose_arrival(), arrival)
	runs.finish(1)
	assert_eq(runs.choose_arrival(), arrival)
	runs.finish(2)
	runs.begin(3, arrival)
	assert_false(container.net_searched)


func test_gate_and_return_door_move_the_player_and_close_the_run() -> void:
	var features := _features()
	var runs := _run(features)
	var alley := _alley(features)
	var gate := runs.get_node("Gate") as SlumGate
	var player := _player(gate.global_position)
	var arrival := alley.get_node("District/Arrival") as SlumArrivalPoint
	gate.request_enter()
	assert_true(runs.is_active(1))
	assert_true(player.net_position.is_equal_approx(arrival.global_position))
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


func test_pawn_shop_storefront_sits_on_the_counter() -> void:
	var runs := _run(_features())
	var fence := runs.get_node("Fence") as LootFence
	assert_eq(fence.interaction_text(), "Pawn a valuable")
	var top := fence.global_position.y + fence.size.y * 0.5
	var case_node := fence.get_node("DisplayCase") as MeshInstance3D
	var case_mesh := case_node.mesh as BoxMesh
	assert_almost_eq(case_node.global_position.y - case_mesh.size.y * 0.5, top, 0.001)
	var bar := fence.get_node("BallBar") as Node3D
	for i: int in 3:
		var ball := fence.get_node("Ball%d" % i) as Node3D
		assert_lt(ball.global_position.y + LootFence.BALL_RADIUS_M, bar.global_position.y)
		assert_gt(ball.global_position.y, top + 0.25, "hangs above the display case")
	var sign := runs.get_node("FenceSign") as Label3D
	assert_gt(sign.global_position.y, bar.global_position.y)
	assert_string_contains(sign.text, "PAWN SHOP")
