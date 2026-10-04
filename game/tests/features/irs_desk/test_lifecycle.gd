extends "res://tests/features/irs_desk/filing_fixture.gd"


class SlowWallet:
	extends PlayerMoney
	signal complete
	var calls: Array[Array] = []
	var response := {"error": "Timeout"}

	func adjust_account(
		peer: int, account: int, id: String, delta: int, _reason: String
	) -> Dictionary:
		calls.append([peer, account, id, delta])
		await complete
		return response


func test_pending_filing_blocks_replay_but_allows_a_different_player() -> void:
	var slow := _slow_wallet()
	_desk.use()
	var payload := _payload(10000, 400)
	assert_eq(_submit(10000, 400), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_entity._evaluate(1, &"file", payload), NetworkedEntity.Result.DENIED)
	var second := PLAYER.instantiate() as Player
	second.name = "2"
	second.set_multiplayer_authority(2)
	add_child_autofree(second)
	second.set_physics_process(false)
	second.net_position = _player.net_position
	# Offline has no transport peer 2; seed its server-issued form directly.
	_desk._filings[2] = {"token": _desk._new_id(), "player": weakref(second), "busy": false}
	var other := {"token": _desk._filings[2]["token"], "winnings": 100, "tax": 100}
	assert_eq(_entity._evaluate(2, &"file", other), NetworkedEntity.Result.ACCEPTED)
	assert_eq(slow.calls.size(), 2)
	_desk._forget(2)
	slow.complete.emit()


func test_transient_error_and_reopening_retain_immutable_id_and_amounts() -> void:
	var slow := _slow_wallet()
	_desk.use()
	_submit(10000, 400)
	var original := slow.calls[0].duplicate()
	slow.complete.emit()
	assert_false(_menu._submit.disabled)
	assert_false(_menu._tax.editable)
	_desk._open(_player)
	assert_eq(_menu._tax.text, "4.00")
	assert_eq(_menu._winnings.text, "100.00")
	assert_eq(_submit(10000, 401), NetworkedEntity.Result.DENIED)
	assert_eq(_submit(9999, 400), NetworkedEntity.Result.DENIED)
	assert_eq(_submit(10000, 400), NetworkedEntity.Result.ACCEPTED)
	assert_eq(slow.calls[1], original)
	slow.response = {"balance": 1600}
	slow.complete.emit()
	assert_false(_desk._filings.has(1))
	assert_true(_menu._submit.disabled)


func test_real_wallet_busy_retry_uses_same_id_and_additive_receipt() -> void:
	_desk.use()
	_wallet._busy[1] = true
	var payload := _payload(10000, 400)
	_submit(10000, 400)
	assert_eq(_wallet.balances[1], 2000)
	assert_false(_menu._submit.disabled)
	_wallet._busy.clear()
	assert_eq(_entity._evaluate(1, &"file", payload), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 1600)
	_wallet.balances[1] += 123
	var replay := await _wallet.adjust_account(1, 0, payload["token"], -400, "Tax")
	assert_eq(replay["balance"], 1723, "Existing wallet receipt never subtracts twice")


func test_disconnect_and_replacement_receive_no_old_receipt() -> void:
	var slow := _slow_wallet()
	_desk.use()
	_submit(100, 100)
	_player.free()
	_desk._forget(1)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = _desk.global_position
	_desk._open(_player)
	var replacement_token: String = _menu._token
	slow.response = {"balance": 1900}
	slow.complete.emit()
	assert_eq(_menu._token, replacement_token)
	assert_eq(_menu._status.text, "")
	assert_true(_desk._filings.has(1))


func test_session_reset_ignores_old_payment_and_respawn_closes_form() -> void:
	var slow := _slow_wallet()
	_desk.use()
	_submit(100, 100)
	_entity.session_reset.emit(Network.Mode.OFFLINE)
	slow.response = {"balance": 1900}
	slow.complete.emit()
	assert_true(_desk._filings.is_empty())
	assert_false(_menu._status.text.contains("received"))
	_player.net_position = Vector3(0, 1, -16)
	_menu._process(0.0)
	assert_false(_menu.is_in_group(&"modal_ui"))


func _slow_wallet() -> SlowWallet:
	_wallet.remove_from_group(&"player_money")
	var slow := SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	return slow
