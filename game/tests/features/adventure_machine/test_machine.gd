extends GutTest

const FEATURE := preload("res://features/adventure_machine/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
var _machine: AdventureMachine
var _player: Player
var _device: Controls.Device


func before_each() -> void:
	_device = Controls.device
	Controls.select_device(Controls.Device.GAMEPAD)
	_machine = FEATURE.instantiate() as AdventureMachine
	add_child_autofree(_machine)
	_player = _new_player(1)
	await wait_physics_frames(4)


func after_each() -> void:
	if is_instance_valid(_machine._screen):
		_machine._screen.close(false)
	Controls.pause()
	Controls.select_device(_device)


func _new_player(peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.get_node("Sync").free()
	player.position = _machine.global_position + Vector3(0, 1, 1.6)
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func _select(id: String, peer := 1) -> NetworkedEntity.Result:
	_machine._next_action.erase(peer)
	return _machine.entity._evaluate(
		peer, &"choose", {"choice": id, "revision": _machine._stories[peer].revision}
	)


func test_use_offline_opens_real_modal_only_after_validated_request() -> void:
	assert_true(_machine.can_use(_player))
	assert_eq(_machine.entity._evaluate(99, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_machine.entity._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	assert_null(_machine._screen)
	_machine.use()
	assert_true(_machine._stories.has(1))
	assert_true(_machine._screen.is_open())
	assert_true(_machine._screen.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	_machine._screen.close()
	assert_false(_machine._screen.is_in_group(&"modal_ui"))
	assert_true(Controls.gameplay_active())


func test_touch_uses_existing_interaction_entry_point_without_a_new_binding() -> void:
	var interaction := preload("res://features/interaction/feature.tscn").instantiate()
	add_child_autofree(interaction)
	Controls.select_device(Controls.Device.TOUCH)
	Controls.start()
	assert_true(Controls.gameplay_active())
	interaction.use()
	assert_not_null(_machine._screen)
	assert_true(_machine._screen.is_open())
	assert_false(Controls.gameplay_active())


func test_schema_unknown_foreign_and_stale_choices_leave_progress_unchanged() -> void:
	assert_eq(
		_machine.entity._evaluate(1, &"choose", {"choice": "take_magnet", "revision": 0}),
		NetworkedEntity.Result.DENIED,
		"Use must initialize the story first"
	)
	_machine.use()
	for payload: Dictionary in [
		{},
		{"choice": "take_magnet"},
		{"choice": 7, "revision": 0},
		{"choice": "take_magnet", "revision": 0.0},
		{"choice": "take_magnet", "revision": "0"},
		{"choice": "take_magnet", "revision": 0, "peer": 1},
		{"choice": "unlock", "revision": 0},
		{"choice": "take_magnet", "revision": -1}
	]:
		assert_eq(_machine.entity._evaluate(1, &"choose", payload), NetworkedEntity.Result.DENIED)
	assert_eq(
		_machine.entity._evaluate(99, &"choose", {"choice": "take_magnet", "revision": 0}),
		NetworkedEntity.Result.DENIED
	)
	assert_eq(_select("take_magnet"), NetworkedEntity.Result.ACCEPTED)
	_machine._next_action.clear()
	assert_eq(
		_machine.entity._evaluate(1, &"choose", {"choice": "go_tavern", "revision": 0}),
		NetworkedEntity.Result.DENIED,
		"Duplicate/stale commands cannot advance a second time"
	)
	assert_eq(_machine._stories[1].inventory, ["magnet"])
	assert_eq(_machine._stories[1].revision, 1)


func test_front_range_aim_and_walls_are_checked_by_server() -> void:
	_player.net_yaw = PI
	assert_eq(_machine.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	_player.net_yaw = 0
	_machine.use()
	_player.net_position = _machine.global_position + Vector3(0, 1, -1.6)
	assert_eq(_select("take_magnet"), NetworkedEntity.Result.DENIED)
	_player.net_position = _machine.global_position + Vector3(0, 1, 5)
	assert_eq(_select("take_magnet"), NetworkedEntity.Result.DENIED)
	_player.net_position = _machine.global_position + Vector3(0, 1, 1.6)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, .1)
	shape.shape = box
	wall.add_child(shape)
	wall.position = _machine.global_position + Vector3(0, 1.5, .9)
	add_child_autofree(wall)
	await wait_physics_frames(4)
	assert_false(_machine.can_use(_player))
	assert_eq(_select("take_magnet"), NetworkedEntity.Result.DENIED)
	assert_eq(_machine._stories[1].revision, 0)


func test_progress_survives_close_respawn_and_replaced_player_but_not_disconnect() -> void:
	_machine.use()
	assert_eq(_select("take_magnet"), NetworkedEntity.Result.ACCEPTED)
	_machine._screen.close(false)
	_machine.use()
	assert_eq(_machine._screen._inventory.text, "Pockets: Horseshoe magnet")
	var combat := Combat.new()
	add_child_autofree(combat)
	combat.set_process(false)
	combat._respawns[1] = 10
	assert_eq(_select("go_tavern"), NetworkedEntity.Result.DENIED)
	_machine._screen._process(.25)
	assert_false(_machine._screen.is_open())
	assert_eq(_machine._stories[1].inventory, ["magnet"])
	combat._respawns.clear()
	_player.free()
	_player = _new_player(1)
	_machine.use()
	assert_eq(_machine._stories[1].inventory, ["magnet"])
	_machine._disconnect(1)
	assert_false(_machine._stories.has(1))
	_machine.use()
	assert_eq(_machine._stories[1].revision, 0)
	_machine._reset(Network.Mode.OFFLINE)
	_machine._mode_changed(Network.Mode.OFFLINE)
	assert_true(_machine._stories.is_empty())
	assert_true(_machine._next_action.is_empty())
	assert_false(_machine._screen.is_open())


func test_two_players_do_not_share_progress_or_cooldowns() -> void:
	_machine.use()
	var other := _new_player(2)
	other.position.x += 1
	other.net_position = other.position
	# No peer 2 connection in an offline fixture; initialize without sending it an RPC.
	_machine._stories[2] = _machine.Story.new()
	assert_eq(_select("take_magnet"), NetworkedEntity.Result.ACCEPTED)
	assert_true(_machine._may_choose(2, {"choice": "take_magnet", "revision": 0}))
	_machine._stories[2].choose("go_tavern")
	assert_eq(_machine._stories[1].room, "quay")
	assert_eq(_machine._stories[2].inventory.size(), 0)
	_machine._disconnect(2)
	assert_true(_machine._stories.has(1))


func test_per_player_wall_clock_throttle_and_reopen_snapshot() -> void:
	_machine.use()
	assert_eq(_select("take_magnet"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(
		_machine.entity._evaluate(1, &"choose", {"choice": "go_tavern", "revision": 1}),
		NetworkedEntity.Result.DENIED
	)
	assert_eq(_machine._stories[1].revision, 1)
	await RealTime.wait(get_tree(), .14)
	_machine.request_choice("go_tavern", 1)
	assert_eq(_machine._stories[1].room, "tavern")
	assert_eq(_machine._screen._revision, 2)
