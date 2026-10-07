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
	var handover := depart + MetroRules.TRAVEL * 0.5
	assert_true(hits(Vector3(0, 2.7, -70), depart + 2.8, depart + 3.0), "Departing nose")
	assert_true(hits(Vector3(0, 2.7, 70), depart + 9.7, depart + 9.9), "Arriving nose")
	# This point is between the endpoints, but outside BOTH endpoint volumes.
	assert_false(hits(Vector3(0, 2, -80), depart + 3, depart + 3.001))
	assert_false(hits(Vector3(0, 2, -80), handover - 0.001, handover))
	assert_true(hits(Vector3(0, 2, -80), depart + 3, handover))
	# The hand-over from departing to arriving train never sweeps the platform.
	assert_false(hits(Vector3(0, 2, 0), handover - 0.1, handover + 0.1))
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
		metro._check_train_impacts(MetroRules.PERIOD - 4.1, MetroRules.PERIOD - 3.9)
		assert_true(combat.is_respawning(index + 1))
		assert_false(metro.net_passengers.has(index + 1))
		assert_false(metro.transfers.pending.has(index + 1))
		assert_eq(combat.kills_for(index + 1), 0)
		assert_eq(player.net_position, metro.stations[index].global_position + Vector3(0, 2.7, 70))
	metro._check_train_impacts(MetroRules.PERIOD - 4.1, MetroRules.PERIOD - 3.9)
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


func test_reverse_track_sweeps_in_the_other_direction() -> void:
	var at := metro.stations[0].position + Vector3(16, 2.7, 70)
	var player := rider(at)
	metro._check_train_impacts(MetroRules.DEPART + 2.8, MetroRules.DEPART + 3.0)
	assert_true(combat.is_respawning(1), "Reverse departure heads toward +Z")
	assert_eq(player.net_position, at)
	var platform := rider(metro.stations[0].position + Vector3(13.5, 2.1244, 0), 2)
	metro._check_train_impacts(MetroRules.PERIOD - 0.1, MetroRules.PERIOD)
	assert_false(combat.is_respawning(platform.get_multiplayer_authority()))


func test_validated_boarder_waiting_for_readiness_is_safe_only_in_cabin() -> void:
	var player := rider(metro.stations[0].position + Vector3(0, 2.1244, 2.5))
	metro._begin_boarding_transfer()
	assert_true(metro.transfers.pending.has(1))
	metro._check_train_impacts(MetroRules.DEPART, MetroRules.DEPART + 0.1)
	assert_false(combat.is_respawning(1))
	player.net_position = metro.stations[0].position + Vector3(0, 2.7, -58)
	metro._check_train_impacts(MetroRules.DEPART, MetroRules.DEPART + 2)
	assert_true(combat.is_respawning(1))
	assert_true(metro.transfers.pending.is_empty())


func test_struck_rider_hears_the_flatline_and_bystanders_hear_it_trackside() -> void:
	var audio := GameAudio.new()
	add_child_autofree(audio)
	watch_signals(audio)
	var at := metro.stations[1].position + Vector3(0, 2.7, 70)
	rider(at)
	metro._check_train_impacts(MetroRules.PERIOD - 4.1, MetroRules.PERIOD - 3.9)
	assert_true(combat.is_respawning(1))
	assert_signal_emitted_with_parameters(
		audio, "sound_started", [&"metro_flatline", false, Vector3.ZERO]
	)
	var bystander := rider(at + Vector3(0, 0, 2), 2)
	metro._check_train_impacts(MetroRules.PERIOD - 4.1, MetroRules.PERIOD - 3.9)
	assert_true(combat.is_respawning(2))
	assert_signal_emitted_with_parameters(
		audio, "sound_started", [&"metro_flatline", true, bystander.net_position]
	)
	assert_signal_emit_count(audio, "sound_started", 2, "One cue per death, not per tick")


func test_riders_the_metro_moved_off_a_departing_train_keep_their_old_seat_safe() -> void:
	# Owners report their teleported position a round trip later; until then the
	# server still sees them in the cabin the departing train is pulling away.
	var seat := metro.stations[0].position + Vector3(0, 2.1244, 2.5)
	rider(seat, 2)
	metro.add_passenger(2, 0)
	metro._check_train_impacts(MetroRules.DEPART, MetroRules.DEPART + 0.5)
	assert_false(combat.is_respawning(2), "Transferred passenger")
	metro.remove_passenger(2)
	rider(seat + Vector3(0, 0, 1), 3)
	metro.shield_from_train(3)
	metro._check_train_impacts(MetroRules.DEPART, MetroRules.DEPART + 0.5)
	assert_false(combat.is_respawning(3), "Sent back to the platform")
	metro.net_cycle += 1
	metro._check_train_impacts(MetroRules.DEPART, MetroRules.DEPART + 0.5)
	assert_true(combat.is_respawning(3), "Shields last only for that departure")
	assert_true(combat.is_respawning(2), "Others still in the cabin are struck")


func test_shield_never_covers_the_tracks() -> void:
	var player := rider(metro.stations[0].position + Vector3(0, 0.94, -70))
	metro.add_passenger(1, 0)
	metro.shield_from_train(1)
	metro._check_train_impacts(MetroRules.DEPART + 2.8, MetroRules.DEPART + 3.0)
	assert_true(combat.is_respawning(1))
	assert_eq(player.net_position, metro.stations[0].position + Vector3(0, 0.94, -70))


func test_late_runner_returned_to_platform_is_shielded() -> void:
	rider(metro.stations[2].position + Vector3(1.6, 2.1244, 30))
	metro._clear_unboarded()
	assert_eq(metro._shielded.get(1, -1), metro.net_cycle)


func test_physics_clock_checks_arrival_before_wrapping() -> void:
	rider(metro.stations[2].position + Vector3(0, 2.7, 0))
	metro._items_departed = true
	metro.net_time = MetroRules.PERIOD - 0.01
	metro._physics_process(0.02)
	assert_true(combat.is_respawning(1))
	assert_eq(metro.net_cycle, 1)
	assert_lt(metro.net_time, 0.02)
