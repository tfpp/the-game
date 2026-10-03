extends GutTest


class DelayedWallet:
	extends PlayerMoney
	signal release
	var calls := 0

	func credit_reward(_peer: int, _id: String, _amount: int, _reason: String) -> Dictionary:
		calls += 1
		await release
		return {"balance": 30000}


const BAR := preload("res://features/bar_companion/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _bar: BarCompanion
var _case: VivienneCase
var _npc: Vivienne
var _player: Player
var _wallet: PlayerMoney
var _playing: bool
var _device: Controls.Device


func before_each() -> void:
	_playing = Controls.playing
	_device = Controls.device
	Controls.device = Controls.Device.TOUCH
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 20000}
	_bar = BAR.instantiate()
	add_child_autofree(_bar)
	_bar.set_process(false)
	_case = _bar.get_node("VivienneCase")
	_npc = _bar.get_node("Vivienne")
	_npc.set_physics_process(false)
	_player = PLAYER.instantiate()
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)


func after_each() -> void:
	for menu: Node in get_tree().get_nodes_in_group(&"modal_ui"):
		if menu.has_method("_close"):
			menu.call("_close", false)
	Controls.device = _device
	Controls.playing = _playing
	Network.peer_accounts.clear()


func _move(node: Node3D) -> void:
	_player.net_position = node.global_position + Vector3(0, 0, 0.8)
	_player.global_position = _player.net_position


func _talk() -> NetworkedInteraction:
	return _npc.get_node("NetworkedEntity")


func _topic(step: int) -> NetworkedEntity.Result:
	_move(_npc)
	_talk()._actions[&"case"].next_msec = 0
	return _talk()._evaluate(1, &"case", {"step": step})


func _evidence(index: int) -> NetworkedEntity.Result:
	var point := _case.get_node("Evidence%d" % index) as Node3D
	_move(point)
	var talk := point.get_node("NetworkedEntity") as NetworkedInteraction
	talk._actions[&"use"].next_msec = 0
	return talk._evaluate(1, &"use", {})


func test_ten_step_case_actually_gathers_evidence_and_pays_once() -> void:
	assert_eq(_case.stage(1), 0)
	assert_eq(_topic(0), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 1)
	assert_eq(_evidence(0), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 2)
	assert_eq(_evidence(1), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 3)
	assert_eq(_topic(3), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 4)
	assert_eq(_evidence(2), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 5)
	assert_eq(_evidence(3), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 6)
	assert_eq(_evidence(4), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 7)
	assert_eq(_evidence(3), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 8)
	assert_eq(_evidence(0), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 9)
	assert_eq(int(_wallet.balances[1]), 20000, "no payout before verdict")
	assert_eq(_topic(9), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 10)
	assert_eq(int(_wallet.balances[1]), 30000, "$100, not the fictional billion")
	assert_eq(_topic(9), NetworkedEntity.Result.DENIED, "stale reward request")
	assert_eq(_topic(10), NetworkedEntity.Result.ACCEPTED, "read-only progress")
	assert_eq(int(_wallet.balances[1]), 30000)
	assert_eq(_npc.net_escort, 0, "story never hires her or grants luck")
	assert_eq(_bar.rerolls_for(1), 0)


func test_free_topics_menu_and_journal_pause_and_resume() -> void:
	_move(_npc)
	_npc.use()
	var menu := _npc.get_node("CaseMenu") as CanvasLayer
	assert_true(menu._root.visible)
	assert_true(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_eq(menu._choices.get_child_count(), 2)
	assert_string_contains((menu._choices.get_child(0) as Button).text, "Get to know")
	assert_eq(int(_wallet.balances[1]), 20000)
	menu._choose("0")
	assert_eq(_case.stage(1), 1)
	assert_string_contains(menu._text.text, "fictional")
	assert_string_contains(menu._text.text, "north card table")
	menu._close()
	assert_true(Controls.gameplay_active())
	_case.esc_menu_open()
	assert_true(_case._journal.is_in_group(&"modal_ui"))
	assert_string_contains(_case._journal._text.text, "north card table")
	_case._journal._close()
	assert_true(Controls.gameplay_active())


func test_server_rejects_skip_forged_stale_far_unknown_and_non_authority() -> void:
	_move(_npc)
	assert_eq(_talk()._evaluate(7, &"case", {"step": 0}), NetworkedEntity.Result.DENIED)
	assert_eq(_talk()._evaluate(1, &"case", {"step": 9}), NetworkedEntity.Result.DENIED)
	assert_eq(_talk()._evaluate(1, &"case", {"step": "0"}), NetworkedEntity.Result.DENIED)
	assert_eq(_talk()._evaluate(1, &"case", {"step": 0, "peer": 2}), NetworkedEntity.Result.DENIED)
	_player.net_position += Vector3(0, 0, 10)
	assert_eq(_talk()._evaluate(1, &"case", {"step": 0}), NetworkedEntity.Result.DENIED)
	assert_eq(_evidence(4), NetworkedEntity.Result.DENIED, "out-of-order evidence")
	_talk().set_multiplayer_authority(2)
	assert_eq(_topic(0), NetworkedEntity.Result.DENIED)
	_talk().set_multiplayer_authority(1)
	assert_eq(_topic(0), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_topic(0), NetworkedEntity.Result.DENIED, "stale topic")
	assert_eq(_case.stage(1), 1)
	assert_eq(_case.stage(2), 0)
	assert_eq(int(_wallet.balances[1]), 20000)


func test_busy_wallet_retry_retains_operation_id_and_never_duplicates() -> void:
	_case.progress = {1: 9}
	_wallet._busy[1] = true
	assert_eq(_topic(9), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 9)
	var id := str(_case._claims[1]["id"])
	assert_eq(int(_wallet.balances[1]), 20000)
	_wallet._busy.erase(1)
	assert_eq(_topic(9), NetworkedEntity.Result.ACCEPTED)
	assert_eq(str(_case._claims[1]["id"]), id)
	assert_eq(_case.stage(1), 10)
	assert_eq(int(_wallet.balances[1]), 30000)
	assert_eq(_topic(9), NetworkedEntity.Result.DENIED)


func test_progress_survives_replaced_player_but_clears_on_disconnect_and_reset() -> void:
	_topic(0)
	_player.free()
	_player = PLAYER.instantiate()
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	assert_eq(_evidence(0), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_case.stage(1), 2)
	_case.progress[2] = 4
	_case._forget(1)
	assert_eq(_case.stage(1), 0)
	assert_eq(_case.stage(2), 4)
	_case._reset(Network.Mode.OFFLINE)
	assert_true(_case.progress.is_empty())
	assert_true(_case._claims.is_empty())


func test_pending_claim_blocks_competition_and_stale_disconnect_reply() -> void:
	_wallet.free()
	var delayed := DelayedWallet.new()
	_wallet = delayed
	add_child_autofree(delayed)
	delayed.set_process(false)
	_case.progress = {1: 9}
	assert_eq(_topic(9), NetworkedEntity.Result.ACCEPTED)
	assert_eq(delayed.calls, 1)
	assert_true(_case._claims[1]["pending"])
	assert_eq(_topic(9), NetworkedEntity.Result.ACCEPTED)
	assert_eq(delayed.calls, 1, "one pending settlement")
	_case._forget(1)
	_case.progress = {1: 8}
	delayed.release.emit()
	assert_eq(_case.stage(1), 8, "old response cannot complete a replacement case")
	assert_true(_case._claims.is_empty())


func test_snapshot_and_static_endpoints_support_late_join_presentation() -> void:
	assert_has(_case.entity.replicated_properties, NodePath(".:progress"))
	_case.progress = {1: 7, 2: 4}
	assert_true(_case.allowed(1, 3))
	assert_false(_case.allowed(1, 2))
	assert_true(_case.allowed(2, 2))
	assert_false(_case.allowed(2, 3))
	assert_string_contains(_case.objective(1), "Confront Donald Gilt")
	for index: int in 5:
		var point := _case.get_node("Evidence%d" % index) as Node3D
		assert_not_null(point.get_node("NetworkedEntity"))
		assert_true(point.is_in_group(&"interactables"))
	assert_eq(VivienneCase.OBJECTIVES.size(), 11)
	assert_eq(VivienneCase.LINES.size(), 10)
