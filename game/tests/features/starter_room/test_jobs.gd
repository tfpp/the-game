extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _feature: Node3D
var _terminal: GarageJobTerminal
var _player: Player
var _wallet: PlayerMoney


func before_each() -> void:
	_feature = FEATURE.instantiate()
	add_child_autofree(_feature)
	_terminal = _feature.get_node("Room/JobTerminal")
	_terminal.set_physics_process(false)
	_terminal.panel.set_process(false)
	_player = PLAYER.instantiate()
	_player.name = "1"
	_player.net_position = _terminal.to_global(Vector3(0, 0, .8))
	_player.position = _player.net_position
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 2000}


func after_each() -> void:
	_terminal.panel.close(false)


func _accept() -> void:
	assert_eq(_terminal.entity._evaluate(1, &"accept", {"job": 0}), NetworkedEntity.Result.ACCEPTED)


func _survey() -> void:
	_player.net_position = _terminal.van.arrival(0).global_position
	for i: int in 12:
		_terminal._physics_process(.25)
	_player.net_position = _terminal.to_global(Vector3(0, 0, .8))


func test_use_opens_real_modal_and_rejects_forged_or_distant_requests() -> void:
	assert_eq(_terminal.entity._evaluate(99, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_terminal.entity._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	_terminal.use()
	assert_true(_terminal.panel.is_open())
	assert_true(_terminal.panel.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	_terminal.panel.close()
	assert_false(_terminal.panel.is_in_group(&"modal_ui"))
	_player.net_position += Vector3(5, 0, 0)
	assert_eq(_terminal.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)


func test_accept_schema_range_life_and_one_active_job_are_server_validated() -> void:
	for payload: Dictionary in [
		{}, {"job": -1}, {"job": 99}, {"job": 0.0}, {"job": "0"}, {"job": 0, "peer": 1}
	]:
		assert_eq(_terminal.entity._evaluate(1, &"accept", payload), NetworkedEntity.Result.DENIED)
	assert_eq(_terminal.entity._evaluate(99, &"accept", {"job": 0}), NetworkedEntity.Result.DENIED)
	_player.net_position += Vector3(10, 0, 0)
	assert_eq(_terminal.entity._evaluate(1, &"accept", {"job": 0}), NetworkedEntity.Result.DENIED)
	_player.net_position = _terminal.to_global(Vector3(0, 0, .8))
	_accept()
	assert_eq(_terminal.entity._evaluate(1, &"accept", {"job": 0}), NetworkedEntity.Result.DENIED)
	assert_false(bool(_terminal.record(1)["ready"]))


func test_survey_requires_continuous_presence_and_returns_to_terminal_for_reward() -> void:
	_accept()
	_terminal._physics_process(4)
	assert_false(bool(_terminal.record(1)["ready"]))
	_player.net_position = _terminal.van.arrival(0).global_position
	_terminal._physics_process(2)
	assert_false(bool(_terminal.record(1)["ready"]))
	_player.net_position += Vector3(7, 0, 0)
	_terminal._physics_process(.25)
	_player.net_position = _terminal.van.arrival(0).global_position
	_terminal._physics_process(1)
	assert_false(bool(_terminal.record(1)["ready"]))
	_terminal._physics_process(2)
	assert_true(bool(_terminal.record(1)["ready"]))
	assert_eq(_terminal.entity._evaluate(1, &"claim", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 2000)


func test_claim_pays_existing_wallet_and_xp_exactly_once() -> void:
	_accept()
	assert_eq(_terminal.entity._evaluate(1, &"claim", {}), NetworkedEntity.Result.DENIED)
	_survey()
	assert_eq(_terminal.entity._evaluate(1, &"claim", {"xp": 999}), NetworkedEntity.Result.DENIED)
	assert_eq(_terminal.entity._evaluate(1, &"claim", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_terminal.entity._evaluate(1, &"claim", {}), NetworkedEntity.Result.DENIED)
	await wait_process_frames(2)
	assert_eq(_wallet.balances[1], 3000)
	assert_eq(_terminal.record(1)["xp"], 25)
	assert_eq(_terminal.record(1)["job"], -1)
	assert_eq(_terminal.record(1)["done"], [0])
	assert_eq(_terminal.entity._evaluate(1, &"claim", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_terminal.entity._evaluate(1, &"accept", {"job": 0}), NetworkedEntity.Result.DENIED)


func test_wallet_busy_preserves_report_and_operation_for_retry() -> void:
	_accept()
	_survey()
	_wallet._busy[1] = true
	assert_eq(_terminal.entity._evaluate(1, &"claim", {}), NetworkedEntity.Result.ACCEPTED)
	var operation := _terminal._operations[1]
	await wait_process_frames(2)
	assert_eq(_terminal.record(1)["xp"], 0)
	assert_true(bool(_terminal.record(1)["ready"]))
	assert_eq(_terminal._operations[1], operation)
	_wallet._busy.clear()
	assert_eq(_terminal.entity._evaluate(1, &"claim", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_terminal._operations[1], operation)
	await wait_process_frames(2)
	assert_eq(_wallet.balances[1], 3000)
	assert_eq(_terminal.record(1)["xp"], 25)


func test_death_disconnect_and_session_reset_do_not_complete_or_pay_jobs() -> void:
	_accept()
	var combat := Combat.new()
	add_child_autofree(combat)
	combat.apply_damage(1, Combat.MAX_HEALTH, 1)
	_player.net_position = _terminal.van.arrival(0).global_position
	_terminal._physics_process(4)
	assert_false(bool(_terminal.record(1)["ready"]))
	assert_eq(_terminal.record(1)["job"], 0, "death retains the contract")
	_player.net_position = _terminal.to_global(Vector3(0, 0, .8))
	assert_eq(_terminal.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	_terminal._disconnect(1)
	assert_true(_terminal.records.is_empty())
	_terminal._store(1, {"job": 0, "ready": true, "done": [], "xp": 0})
	_terminal._claim(1, {})
	_terminal._reset(Network.Mode.OFFLINE)
	await wait_process_frames(2)
	assert_true(_terminal.records.is_empty())
	assert_eq(_wallet.balances[1], 2000)


func test_all_routes_can_pay_once_and_accumulate_session_xp() -> void:
	preload("res://tests/features/dev_access/cheats_fixture.gd").enable(self)
	for job: int in OperationsVan.ZONE_NAMES.size():
		if _terminal.van.arrival(job) == null:
			var marker := Marker3D.new()
			marker.name = "TestArrival%s" % job
			marker.position = Vector3(100 * job, 1, 0)
			_feature.add_child(marker)
			_terminal.van.arrivals[job] = _terminal.van.get_path_to(marker)
		assert_eq(
			_terminal.entity._evaluate(1, &"accept", {"job": job}), NetworkedEntity.Result.ACCEPTED
		)
		_player.net_position = _terminal.van.arrival(job).global_position
		for tick: int in 12:
			_terminal._physics_process(.25)
		_player.net_position = _terminal.to_global(Vector3(0, 0, .8))
		assert_eq(_terminal.entity._evaluate(1, &"claim", {}), NetworkedEntity.Result.ACCEPTED)
		await wait_process_frames(2)
	assert_eq(_wallet.balances[1], 7000)
	assert_eq(_terminal.record(1)["xp"], 125)
	assert_eq(_terminal.record(1)["done"], [0, 1, 2, 3, 4])
	_terminal.panel.open(_terminal)
	assert_eq(get_viewport().gui_get_focus_owner(), _terminal.panel.desktop._launchers["Jobs"])
	_terminal._disconnect(1)
	assert_eq(_terminal.record(1)["xp"], 0)


func test_pinned_readout_uses_owner_record_and_survives_closing_application() -> void:
	_accept()
	_terminal.panel._update()
	assert_true(_terminal.panel._pin.visible)
	assert_string_contains(_terminal.panel._pin.text, "Golden Crown")
	_terminal.panel.open(_terminal)
	assert_false(_terminal.panel._pin.visible)
	_terminal.panel.close()
	_survey()
	_terminal.panel._update()
	assert_string_contains(_terminal.panel._pin.text, "claim $10 + 25 XP")
	assert_true(_terminal.panel._pin.visible)
	assert_gt(_terminal.panel._pin.position.y, 80.0)
