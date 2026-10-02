extends GutTest

const SHIFT := preload("res://features/bar_companion/busboy_shift.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const PATRON := preload("res://features/casino_patrons/stationary_seated.tscn")
var _shift: BusboyShift
var _player: Player
var _wallet: PlayerMoney


class SlowWallet:
	extends PlayerMoney
	signal complete
	var calls := 0
	var ids: Array[String] = []

	func credit_coin(_peer: int, id: String, _reason: String) -> Dictionary:
		calls += 1
		ids.append(id)
		await complete
		return {"balance": 3000}


func before_each() -> void:
	_shift = SHIFT.instantiate() as BusboyShift
	add_child_autofree(_shift)
	_shift.set_process(false)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 2000}
	for point: Node3D in _shift._points:
		var talk := point.get_node("NetworkedEntity") as NetworkedInteraction
		talk._actions[&"use"].cooldown_msec = 0


func test_start_requires_authentic_peer_empty_payload_range_and_authority() -> void:
	var talk := _talk("Bar")
	_player.net_position = Vector3(0, 1, 8)
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	_player.net_position = _shift.get_node("Bar").global_position
	assert_eq(talk._evaluate(77, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(talk._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	talk.set_multiplayer_authority(77)
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	talk.set_multiplayer_authority(1)
	assert_eq(_use("Bar"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_shift.worker, 1)
	assert_eq(_shift.phase, "active")
	assert_eq(_wallet.balances[1], 2000, "Starting never charges")


func test_one_at_a_time_pickup_and_drop_do_not_touch_inventory_or_pay_early() -> void:
	_use("Bar")
	_shift.dirty = [0, 1]
	_shift._publish()
	assert_eq(_use("Glass0"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_shift.cargo, -2)
	assert_eq(_shift.dirty, [1])
	assert_eq(_use("Glass1"), NetworkedEntity.Result.DENIED)
	assert_eq(_use("Bar"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_shift.cargo, -1)
	assert_eq(_shift.cleared, 1)
	assert_eq(_use("Glass0"), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 2000)


func test_competing_worker_cannot_start_take_glass_deliver_or_claim() -> void:
	_use("Bar")
	var second := PLAYER.instantiate() as Player
	second.name = "2"
	second.set_multiplayer_authority(2)
	add_child_autofree(second)
	second.set_physics_process(false)
	_shift.dirty = [0]
	_shift._publish()
	for point_name: String in ["Bar", "Glass0", "Order0"]:
		second.net_position = _shift.get_node(point_name).global_position
		assert_eq(_talk(point_name)._evaluate(2, &"use", {}), NetworkedEntity.Result.DENIED)
	_shift._finish("prize")
	assert_eq(_talk("Bar")._evaluate(2, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_shift.worker, 1)


func test_order_drink_must_come_from_bar_and_go_to_correct_patron() -> void:
	_use("Bar")
	_shift.orders = {1: BusboyShift.ORDER_DEADLINE}
	_shift._publish()
	assert_eq(_use("Order1"), NetworkedEntity.Result.DENIED)
	assert_eq(_use("Bar"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_shift.cargo, 1)
	assert_eq(_use("Order0"), NetworkedEntity.Result.DENIED)
	_shift.dirty = [2]
	_shift._publish()
	assert_eq(_use("Glass2"), NetworkedEntity.Result.DENIED)
	assert_eq(_use("Order1"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_shift.served, 1)
	assert_eq(_shift.cargo, -1)
	assert_true(_shift.orders.is_empty())
	assert_eq(_use("Order1"), NetworkedEntity.Result.DENIED)


func test_ninth_dirty_glass_fails_without_prize_and_clears_cargo() -> void:
	_use("Bar")
	for count: int in 8:
		_shift.spawn_empty()
		assert_eq(_shift.dirty.size(), count + 1)
		assert_eq(_shift.phase, "active")
	assert_eq(_shift.dirty.size(), 8)
	_shift.spawn_empty()
	assert_eq(_shift.phase, "failed")
	assert_true(_shift.dirty.is_empty())
	assert_eq(_shift.cargo, -1)
	assert_eq(_wallet.balances[1], 2000)
	assert_eq(_use("Bar"), NetworkedEntity.Result.ACCEPTED, "retry, not a payout")
	assert_eq(_shift.phase, "active")


func test_overdue_order_fails_even_when_drink_is_in_transit() -> void:
	_use("Bar")
	_shift.orders = {0: 0.5, 1: 10.0, 2: 0.5}
	_shift.cargo = 0
	_shift.advance(0.6)
	assert_eq(_shift.phase, "failed")
	assert_eq(_wallet.balances[1], 2000)


func test_timer_success_pays_once_at_bar_and_no_work_cannot_win() -> void:
	_use("Bar")
	_shift.elapsed = 119.0
	_shift.advance(1.0)
	assert_eq(_shift.phase, "failed")
	_use("Bar")
	_shift.cleared = 1
	_shift.elapsed = 119.0
	_shift.advance(1.0)
	assert_eq(_shift.phase, "prize")
	assert_eq(_wallet.balances[1], 2000, "prize is claimed, not paid remotely")
	assert_eq(_use("Bar"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 3000)
	assert_eq(_shift.phase, "paid")
	_use("Bar")
	assert_eq(_shift.phase, "active")
	assert_eq(_wallet.balances[1], 3000, "second Use starts a new shift, not another prize")


func test_time_limit_with_unserved_orders_loses() -> void:
	_use("Bar")
	_shift.cleared = 5
	_shift.orders = {0: 20.0}
	_shift.elapsed = 119.0
	_shift.advance(1.0)
	assert_eq(_shift.phase, "failed")
	assert_eq(_wallet.balances[1], 2000)


func test_timers_start_slow_ramp_and_large_steps_cannot_skip_failure() -> void:
	assert_eq(BusboyShift.glass_interval(0), 12.0)
	assert_eq(BusboyShift.glass_interval(120), 4.0)
	assert_lt(BusboyShift.order_interval(90), BusboyShift.order_interval(30))
	_use("Bar")
	_shift.advance(11.0)
	assert_true(_shift.dirty.is_empty())
	_shift.advance(1.0)
	assert_eq(_shift.dirty.size(), 1)
	assert_true(_shift.orders.is_empty())
	_shift.advance(120.0)
	assert_eq(_shift.phase, "failed", "cannot skip backlog failure with a long frame")
	assert_lt(_shift.elapsed, 120.0)


func test_orders_use_existing_live_patrons_after_thirty_seconds() -> void:
	var patron := PATRON.instantiate() as StationaryPatron
	patron.name = "Patron0_0"
	add_child_autofree(patron)
	_use("Bar")
	_shift.advance(29)
	assert_true(_shift.orders.is_empty())
	_shift.advance(1)
	assert_true(_shift.orders.has(0))
	_shift.orders.clear()
	patron.net_alive = false
	_shift._spawn_order()
	assert_true(_shift.orders.is_empty(), "dead guests do not place orders")


func test_disconnect_death_replacement_and_session_cleanup() -> void:
	_use("Bar")
	_shift.dirty = [0]
	_shift._death(1, 1)
	assert_eq(_shift.phase, "failed")
	_use("Bar")
	_shift._disconnect(2)
	assert_eq(_shift.phase, "active")
	_shift._disconnect(1)
	assert_eq(_shift.phase, "idle")
	assert_eq(_shift.worker, 0)
	_use("Bar")
	_player.free()
	_shift.advance(1)
	assert_eq(_shift.phase, "failed", "replacing the player's node cancels the shift")
	_shift.entity.session_reset.emit(Network.Mode.OFFLINE)
	assert_eq(_shift.snapshot["phase"], "idle")
	assert_true(_shift.orders.is_empty())


func test_actual_combat_death_and_respawn_guard_fail_the_shift() -> void:
	var combat := Combat.new()
	add_child_autofree(combat)
	combat.set_process(false)
	_shift._connect_combat()
	_use("Bar")
	combat.apply_damage(1, 100, 1)
	assert_eq(_shift.phase, "failed", "the shared combat signal cancels immediately")
	assert_eq(_use("Bar"), NetworkedEntity.Result.DENIED, "cannot start while dead")
	combat._respawns.clear()
	_use("Bar")
	combat._respawns[1] = 1.0
	_shift.advance(0.01)
	assert_eq(_shift.phase, "failed", "respawn guard also catches missing death signals")
	assert_eq(_wallet.balances[1], 2000)


func test_claim_retries_busy_wallet_and_blocks_pending_duplicates() -> void:
	_use("Bar")
	_shift._finish("prize")
	_wallet._busy[1] = true
	_use("Bar")
	assert_eq(_shift.phase, "prize")
	_wallet._busy.clear()
	_wallet.remove_from_group(&"player_money")
	var slow := SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	_use("Bar")
	assert_eq(slow.calls, 1)
	assert_eq(_use("Bar"), NetworkedEntity.Result.DENIED)
	slow.complete.emit()
	assert_eq(_shift.phase, "paid")
	assert_eq(slow.ids[0], _shift._prize_id)


func test_stale_reward_callback_cannot_change_new_session() -> void:
	_wallet.remove_from_group(&"player_money")
	var slow := SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	_use("Bar")
	_shift._finish("prize")
	_use("Bar")
	_shift._reset(Network.Mode.OFFLINE)
	slow.complete.emit()
	assert_eq(_shift.phase, "idle")
	assert_false(_shift._pending)


func test_late_snapshot_presents_glasses_orders_cargo_and_server_owned_spawn_fields() -> void:
	_use("Bar")
	_shift.dirty = [0, 1, 5]
	_shift.orders = {1: 12.0}
	_shift.cargo = -2
	_shift._publish()
	var late := SHIFT.instantiate() as BusboyShift
	add_child_autofree(late)
	late.set_process(false)
	late.snapshot = _shift.snapshot.duplicate(true)
	late._present()
	assert_true(late.get_node("Glass0").visible)
	assert_true(late.get_node("Glass1").visible)
	assert_true(late.get_node("Glass0/Label").visible)
	assert_false(late.get_node("Glass1/Label").visible, "one clear EMPTY marker per table")
	assert_true(late.get_node("Order1").visible)
	assert_true(late._carry.visible)
	assert_true(late._carry.get_node("Empty").visible)
	assert_false(late._carry.get_node("Drink").visible)
	assert_string_contains(late.get_node("Order1/Label").text, "12s left")
	var sync := late.entity.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:snapshot")))
	late.snapshot["cargo"] = 1
	late._present()
	assert_true(late._carry.get_node("Drink").visible)
	assert_false(late._carry.get_node("Empty").visible)


func test_cargo_mounts_in_both_views_and_hud_reads_task_without_capturing_input() -> void:
	_use("Bar")
	_shift.cargo = -2
	_shift._publish()
	var body := _player.get_node("Body") as Node3D
	body.visible = false
	_shift._present()
	var expected := HeldItemPose.player_mount(_player, Vector3(-0.10, -0.23, -0.5))
	assert_almost_eq(_shift._carry.global_position, expected.origin, Vector3.ONE * 0.001)
	body.visible = true
	_shift._present()
	expected = HeldItemPose.player_mount(_player)
	assert_almost_eq(
		_shift._carry.global_position,
		expected.origin + expected.basis * Vector3(-0.44, 0, 0),
		Vector3.ONE * 0.001
	)
	var hud := _shift.get_node("HUD") as CanvasLayer
	hud._process(0)
	assert_true(hud.visible)
	assert_string_contains(hud._label.text, "Return glass to bar")
	assert_eq(hud._label.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(hud.is_in_group(&"modal_ui"))


func _talk(node_name: String) -> NetworkedInteraction:
	return _shift.get_node(node_name + "/NetworkedEntity") as NetworkedInteraction


func _use(node_name: String) -> NetworkedEntity.Result:
	_player.net_position = (_shift.get_node(node_name) as Node3D).global_position
	return _talk(node_name)._evaluate(1, &"use", {})
