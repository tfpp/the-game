extends GutTest

const METRO := preload("res://features/metro/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var metro: MetroService
var combat: Combat


func before_each() -> void:
	combat = Combat.new()
	add_child_autofree(combat)
	combat.set_process(false)
	metro = METRO.instantiate() as MetroService
	add_child_autofree(metro)
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	await wait_physics_frames(3)


func rider(at: Vector3, peer: int = 1) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.position = at
	player.net_position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func hits(point: Vector3, start: float, end: float) -> bool:
	return MetroRules.train_hits(point, 0.4064, 1.8288, start, end)


func test_visible_arrival_and_departure_sweep_not_hidden_reset() -> void:
	var depart := MetroRules.DEPART
	assert_true(hits(Vector3(0, 2.7, -70), depart + 0.9, depart + 1.1))
	assert_true(hits(Vector3(0, 2.7, 70), depart + 8.9, depart + 9.1))
	# This point is between the endpoints, but outside BOTH endpoint volumes.
	assert_true(hits(Vector3(0, 2, -70), depart, depart + 3))
	assert_false(hits(Vector3(0, 2, 0), depart + 3, depart + 7))
	assert_false(hits(Vector3(0, 2, 0), 1, depart))
	assert_false(hits(Vector3(0, 2, 0), 5, 5))
	assert_false(hits(Vector3(0, 2, 0), MetroRules.PERIOD, 0))


func test_real_train_bounds_leave_platform_and_roof_clear() -> void:
	var start := MetroRules.PERIOD - 0.1
	var end := MetroRules.PERIOD
	assert_true(hits(Vector3(0, 2.7, 0), start, end), "Jumping in front is lethal")
	assert_true(hits(Vector3(1.8, 2.7, 0), start, end), "Capsule grazes side")
	assert_false(hits(Vector3(2.1, 2.1244, 0), start, end), "Platform is clear")
	assert_false(hits(Vector3(0, 4.7, 0), start, end), "Above roof is clear")
	assert_false(hits(Vector3(0, -1, 0), start, end), "Below rail bed is clear")
	assert_false(hits(Vector3(0, 2, -60), start, end), "Behind consist is clear")
	assert_almost_eq(MetroRules.TRAIN_HALF_LENGTH * 2, MetroRules.PITCH * 5, 0.001)


func test_all_stations_kill_once_without_kill_credit_and_clear_travel() -> void:
	watch_signals(combat)
	for index: int in 4:
		var player := rider(metro.stations[index].global_position + Vector3(0, 2.7, 70), index + 1)
		metro.add_passenger(index + 1, index)
		# Unrelated pending travel must not grant track immunity.
		metro.transfers.pending[index + 1] = {"kind": "lift", "source": null, "cab": null}
		metro._check_train_impacts(MetroRules.PERIOD - 1.1, MetroRules.PERIOD - 0.9)
		assert_true(combat.is_respawning(index + 1))
		assert_false(metro.net_passengers.has(index + 1))
		assert_false(metro.transfers.pending.has(index + 1))
		assert_eq(combat.kills_for(index + 1), 0)
		assert_eq(player.net_position, metro.stations[index].global_position + Vector3(0, 2.7, 70))
	metro._check_train_impacts(MetroRules.PERIOD - 1.1, MetroRules.PERIOD - 0.9)
	assert_signal_emit_count(combat, "player_died", 4)


func test_parked_train_ride_compartment_and_crown_are_unaffected() -> void:
	var player := rider(metro.stations[0].position + Vector3(0, 2.1244, 0))
	metro._check_train_impacts(2, 3)
	assert_false(combat.is_respawning(1))
	player.net_position = metro.rides[0].position + Vector3(0, 2.1244, 0)
	metro._check_train_impacts(MetroRules.PERIOD - 0.1, MetroRules.PERIOD)
	assert_false(combat.is_respawning(1))
	player.net_position = Vector3(0, 2, 0)
	metro._check_train_impacts(MetroRules.PERIOD - 0.1, MetroRules.PERIOD)
	assert_false(combat.is_respawning(1))


func test_validated_boarder_waiting_for_readiness_is_safe_only_in_cabin() -> void:
	var player := rider(metro.stations[0].position + Vector3(0, 2.1244, 2.5))
	metro._begin_boarding_transfer()
	assert_true(metro.transfers.pending.has(1))
	metro._check_train_impacts(MetroRules.DEPART, MetroRules.DEPART + 0.1)
	assert_false(combat.is_respawning(1))
	player.net_position = metro.stations[0].position + Vector3(0, 2.7, -58)
	metro._check_train_impacts(MetroRules.DEPART, MetroRules.DEPART + 0.5)
	assert_true(combat.is_respawning(1))
	assert_true(metro.transfers.pending.is_empty())


func test_physics_clock_checks_arrival_before_wrapping() -> void:
	rider(metro.stations[2].position + Vector3(0, 2.7, 0))
	metro._items_departed = true
	metro.net_time = MetroRules.PERIOD - 0.01
	metro._physics_process(0.02)
	assert_true(combat.is_respawning(1))
	assert_eq(metro.net_cycle, 1)
	assert_lt(metro.net_time, 0.02)
