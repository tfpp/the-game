extends GutTest

const MachineScene := preload("res://features/slot_machine/machine.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const Interaction := preload("res://features/interaction/interaction.gd")
const Touch := preload("res://features/touch_controls/touch_controls.gd")

var _machine: SlotMachine


func before_each() -> void:
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	_machine = MachineScene.instantiate() as SlotMachine
	add_child_autofree(_machine)
	_machine.set_process(false)


func test_independent_reels_and_exact_return() -> void:
	var cycle := SlotSpinCycle.new()
	for spin: int in 100:
		var result := cycle.next_result()
		assert_eq(result.size(), 3)
		for symbol: int in result:
			assert_between(symbol, 0, SlotSpinCycle.SYMBOL_COUNT - 1)
	var total := 0
	var wins := 0
	for a: int in 5:
		for b: int in 5:
			for c: int in 5:
				var reels: Array[int] = [a, b, c]
				total += SlotSpinCycle.payout(reels)
				wins += int(SlotSpinCycle.is_win(reels))
	assert_eq(total, 10000, "125 $1 spins pay $100: 80% return")
	assert_eq(wins, 5)


func test_reels_stop_left_to_right_and_finish_once() -> void:
	_machine._begin_spin(1, "Alice")
	assert_true(_machine.state["spinning"])
	assert_eq(_machine.state["stopped"], 0)
	_machine._advance(1.21)
	assert_eq(_machine.state["stopped"], 1)
	var first := int(_machine.state["reels"][0])
	_machine._advance(0.9)
	assert_eq(_machine.state["stopped"], 2)
	assert_eq(int(_machine.state["reels"][0]), first)
	var second := int(_machine.state["reels"][1])
	_machine._advance(0.9)
	assert_false(_machine.state["spinning"])
	assert_eq(_machine.state["stopped"], 3)
	assert_eq(int(_machine.state["reels"][0]), first)
	assert_eq(int(_machine.state["reels"][1]), second)
	var reels: Array[int] = []
	reels.assign(_machine.state["reels"])
	assert_eq(bool(_machine.state["won"]), SlotSpinCycle.is_win(reels))
	assert_eq(_machine._last_sound_spin, 1)
	_machine.play_result(1, true)
	assert_eq(_machine._last_sound_spin, 1)


func test_unknown_player_cannot_start_a_spin() -> void:
	_machine.request_spin()
	assert_eq(_machine.state["spin"], 0)


func test_busy_machine_rejects_requests_without_consuming_another_spin() -> void:
	_machine._begin_spin(1, "Alice")
	_machine.request_spin()
	assert_eq(_machine.state["spin"], 1)
	assert_eq(_machine.state["operator"], "Alice")


func test_server_checks_range_facing_and_obstructions() -> void:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(2)
	player.position = Vector3(0, 0.9144, 2.5)
	player.net_position = player.position
	add_child_autofree(player)
	await get_tree().physics_frame
	assert_true(_machine.can_use(player))
	player.net_position.z = 10
	assert_false(_machine.can_use(player))
	player.net_position.z = 2.5
	player.net_yaw = PI
	assert_false(_machine.can_use(player))
	player.net_yaw = 0
	player.net_position.z = -2
	assert_false(_machine.can_use(player))
	player.net_position.z = 2.5
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.2)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(0, 1.5, 1.7)
	add_child_autofree(wall)
	await get_tree().physics_frame
	assert_false(_machine.can_use(player), "Cannot use through a wall")


func test_use_bindings_and_touch_target() -> void:
	var interaction := Interaction.new()
	add_child_autofree(interaction)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	assert_true(key.is_action_pressed(&"use"))
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_B
	button.pressed = true
	assert_true(button.is_action_pressed(&"use"))
	button.button_index = JOY_BUTTON_A
	assert_false(button.is_action_pressed(&"use"))
	var overlay := Touch.new()
	overlay.size = Vector2(1280, 720)
	add_child_autofree(overlay)
	assert_gt(overlay.use_center().distance_to(overlay.jump_center()), 116.0)
	assert_true(overlay.safe_bounds.has_point(overlay.use_center()))
	assert_true(overlay.safe_bounds.has_point(overlay.jump_center()))


func test_switching_sessions_clears_old_results() -> void:
	_machine._begin_spin(1, "Alice")
	_machine._advance(4.0)
	_machine._on_mode_changed(Network.Mode.OFFLINE)
	assert_eq(_machine.state, SlotMachine.initial_state())
	assert_eq(_machine._last_sound_spin, 0)


func test_result_audio_selects_win_or_loss_and_ignores_duplicates() -> void:
	var win := AudioStreamGenerator.new()
	var loss := AudioStreamGenerator.new()
	_machine._win_sound = win
	_machine._lose_sound = loss
	_machine.play_result(1, true)
	assert_same((_machine.get_node("Audio") as AudioStreamPlayer3D).stream, win)
	_machine.play_result(1, false)
	assert_same((_machine.get_node("Audio") as AudioStreamPlayer3D).stream, win)
	_machine.play_result(2, false)
	assert_same((_machine.get_node("Audio") as AudioStreamPlayer3D).stream, loss)


func test_mobile_use_starts_spin_without_moving_looking_or_jumping() -> void:
	var saved_device := Controls.device
	var saved_touch := Controls.touch_available
	var saved_joypad := Controls.joypad
	Controls.device = Controls.Device.TOUCH
	Controls.touch_available = true
	Controls.joypad = -1
	Controls.start()
	var player := PlayerScene.instantiate() as Player
	player.position = Vector3(0, 0.9144, 2.5)
	add_child_autofree(player)
	player.set_physics_process(false)
	var interaction := Interaction.new()
	add_child_autofree(interaction)
	var overlay := Touch.new()
	overlay.size = Vector2(1280, 720)
	add_child_autofree(overlay)
	await get_tree().physics_frame
	var press := InputEventScreenTouch.new()
	press.index = 7
	press.position = overlay.use_center() * overlay.ui_scale
	press.pressed = true
	overlay._input(press)
	assert_eq(_machine.state["spin"], 1)
	assert_eq(overlay.use_finger, 7)
	assert_eq(overlay.look_finger, -1)
	assert_eq(Controls.movement(), Vector2.ZERO)
	assert_false(Controls.consume_jump())
	press.pressed = false
	overlay._input(press)
	assert_eq(overlay.use_finger, -1)
	_machine._advance(4.0)
	# The same route is disabled while a menu/chat modal owns input.
	var modal := Node.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	press.pressed = true
	overlay._input(press)
	interaction.use()
	assert_eq(_machine.state["spin"], 1)
	Controls.pause()
	Controls.device = saved_device
	Controls.touch_available = saved_touch
	Controls.joypad = saved_joypad


func test_wallet_charges_and_rejects_empty_balance() -> void:
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	wallet.balances[1] = 100
	var result: Dictionary = await wallet.spin(1, "test")
	assert_eq(int(wallet.balances[1]), int(result["payout"]))
	wallet.balances[1] = 99
	result = await wallet.spin(1, "test2")
	assert_true(result.has("error"))
	assert_eq(int(wallet.balances[1]), 99)


func test_temporary_income_and_remote_nameplate() -> void:
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(2)
	player.display_name = "Alice"
	add_child_autofree(player)
	Network.peer_accounts[2] = {"account_id": 0, "name": "Alice"}
	wallet._process(59.0)
	assert_eq(float(wallet._temporary_seconds[2]), 59.0)
	wallet._process(1.0)
	assert_eq(int(wallet.balances[2]), 2500)
	var label := player.get_node("MoneyLabel") as Label3D
	assert_eq(label.text, "$25.00")
	Network.peer_accounts.erase(2)
	wallet._reset(Network.Mode.OFFLINE)
	assert_true(wallet.balances.is_empty())
	assert_true(wallet._temporary_seconds.is_empty())
