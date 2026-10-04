extends "res://tests/features/irs_desk/filing_fixture.gd"


func test_use_opens_private_form_without_spending_and_close_restores_controls() -> void:
	_desk.use()
	assert_true(_menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing)
	assert_eq(_wallet.balances[1], 2000)
	assert_eq(_menu._tax.text, "")
	assert_eq(_menu._winnings.text, "")
	assert_false(_menu._token.is_empty())
	_menu._close()
	assert_false(_menu.is_in_group(&"modal_ui"))
	assert_true(Controls.playing)


func test_declared_winnings_do_not_credit_and_chosen_tax_debits_exact_cents_once() -> void:
	_desk.use()
	var payload := _payload(12345, 725)
	assert_eq(_entity._evaluate(1, &"file", payload), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 1275)
	assert_eq(_entity._evaluate(1, &"file", payload), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 1275)
	assert_string_contains(_menu._status.text, "$7.25")
	assert_string_contains(_menu._status.text, "go to jail")
	assert_true(_menu._submit.disabled)


func test_zero_tax_is_allowed_and_tax_is_not_calculated_from_winnings() -> void:
	_desk.use()
	assert_eq(_submit(0, 0), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 2000)
	_desk._open(_player)
	assert_eq(_submit(0, 500), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 1500, "No automatic rate or relation to declared winnings")


func test_insufficient_funds_does_not_spend_and_requires_new_filing() -> void:
	_desk.use()
	assert_eq(_submit(50000, 10000), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 2000)
	assert_string_contains(_menu._status.text, "refused")
	assert_false(_desk._filings.has(1))
	assert_true(_menu._submit.disabled)


func test_rejects_payload_forgery_wrong_peer_and_missing_use() -> void:
	assert_eq(_submit(100, 100), NetworkedEntity.Result.DENIED)
	_desk.use()
	var valid := _payload(100, 100)
	for bad: Dictionary in [
		{},
		{"token": _menu._token, "tax": -1, "winnings": 100},
		{"token": _menu._token, "tax": 10001, "winnings": 100},
		{"token": _menu._token, "tax": 1.0, "winnings": 100},
		{"token": _menu._token, "tax": 1, "winnings": -1},
		{"token": _menu._token, "tax": 1, "winnings": 100000000001},
		{"token": "forged", "tax": 1, "winnings": 100},
		{"token": _menu._token, "tax": 1, "winnings": 100, "peer": 1}
	]:
		assert_eq(_entity._evaluate(1, &"file", bad), NetworkedEntity.Result.DENIED)
	assert_eq(_entity._evaluate(77, &"file", valid), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 2000)


func test_submit_rechecks_range_and_server_authority() -> void:
	_desk.use()
	_player.net_position = Vector3(0, 1, 100)
	assert_eq(_submit(100, 100), NetworkedEntity.Result.DENIED)
	_player.net_position = _desk.global_position
	_entity.set_multiplayer_authority(77)
	assert_eq(_submit(100, 100), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 2000)


func test_text_form_parses_cents_and_controller_menu_leaves_game_paused() -> void:
	_desk.use()
	_menu._winnings.text = "15.01"
	_menu._tax.text = "2.35"
	_menu._pay()
	assert_eq(_wallet.balances[1], 1765)
	assert_false(_menu._tax.editable)
	assert_true(_menu._close_button.has_focus())
	Controls.menu_requested.emit()
	assert_false(_menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing)


func test_invalid_text_never_sends_and_range_exit_closes_modal() -> void:
	_desk.use()
	_menu._winnings.text = "10"
	_menu._tax.text = "-10"
	_menu._pay()
	assert_eq(_wallet.balances[1], 2000)
	assert_true(_menu._tax.editable)
	_player.net_position += Vector3(0, 0, 100)
	_menu._process(0.0)
	assert_false(_menu.is_in_group(&"modal_ui"))
	assert_true(Controls.playing)


func test_late_join_contract_keeps_balances_on_existing_wallet_and_forms_private() -> void:
	_desk.use()
	_submit(100, 135)
	var scene := preload("res://features/money/feature.tscn").instantiate()
	add_child_autofree(scene)
	scene.set_process(false)
	var sync := scene.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:balances")))
	var late := DESK.instantiate() as Node3D
	add_child_autofree(late)
	assert_true(late._filings.is_empty())
	assert_false(late.get_node("TaxForm")._root.visible)
	assert_true(late.get_node("NetworkedEntity").replicated_properties.is_empty())
