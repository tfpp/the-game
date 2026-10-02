extends GutTest

const BOMB := preload("res://features/timed_bomb/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const Puzzle := preload("res://features/timed_bomb/local_puzzle.gd")
var _bomb: Node3D
var _player: Player
var _path := "user://test_bomb_337.json"


func before_each() -> void:
	DirAccess.remove_absolute(_path)
	_bomb = BOMB.instantiate()
	_bomb.practice_path = _path
	add_child_autofree(_bomb)
	_bomb.set_process(false)
	_bomb._fetch()
	# Use a synthetic code only in this isolated practice fixture.
	_bomb._local.data["code"] = "0042"
	_bomb._local.save()
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = _bomb.global_position + Vector3(0, 1, 1)


func after_each() -> void:
	_bomb.get_node("KeypadUI")._close(false)
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func test_valid_request_defuses_and_survives_reload_and_session_reset() -> void:
	assert_eq(_request({"code": "0042"}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_bomb.net_state, "defused")
	_bomb._reset(Network.Mode.OFFLINE)
	_bomb._fetch()
	assert_eq(_bomb.net_state, "defused")
	assert_eq(_request({"code": "0042"}), NetworkedEntity.Result.COOLDOWN)
	assert_false(_bomb.can_use(_player))


func test_wrong_code_cooldown_is_shared_and_cannot_be_reset_by_reconnect() -> void:
	_request({"code": "0000"})
	assert_eq(_bomb.net_state, "armed")
	var puzzle := Puzzle.new()
	puzzle.path = _path
	assert_true(puzzle.load_or_create(int(Time.get_unix_time_from_system())))
	assert_eq(puzzle.snapshot(int(Time.get_unix_time_from_system()), "0042")["state"], "armed")
	assert_eq(
		puzzle.snapshot(int(Time.get_unix_time_from_system()) + 5, "0042")["state"], "defused"
	)


func test_bad_schema_unknown_peer_range_and_authority_never_defuse() -> void:
	for payload: Dictionary in [
		{},
		{"code": 42},
		{"code": "042"},
		{"code": "00420"},
		{"code": "abcd"},
		{"code": "００４２"},
		{"code": "0042", "peer": 1}
	]:
		assert_eq(_request(payload), NetworkedEntity.Result.DENIED)
	assert_eq(
		_bomb.entity._evaluate(88, &"defuse", {"code": "0042"}), NetworkedEntity.Result.DENIED
	)
	_player.net_position += Vector3(10, 0, 0)
	assert_eq(_request({"code": "0042"}), NetworkedEntity.Result.DENIED)
	_player.net_position = _bomb.global_position + Vector3.UP
	_bomb.entity.set_multiplayer_authority(88)
	assert_eq(_request({"code": "0042"}), NetworkedEntity.Result.DENIED)
	assert_eq(_bomb.net_state, "armed")


func test_busy_and_unavailable_keypad_cannot_submit() -> void:
	_bomb._busy = true
	assert_eq(_request({"code": "0042"}), NetworkedEntity.Result.DENIED)
	_bomb._busy = false
	_bomb.net_available = false
	assert_eq(_request({"code": "0042"}), NetworkedEntity.Result.DENIED)
	assert_eq(_bomb.net_state, "armed")


func test_realtime_expiry_wins_and_only_emits_one_transient_blast() -> void:
	watch_signals(_bomb.entity)
	_bomb._local.data["deadline"] = int(Time.get_unix_time_from_system())
	_bomb._fetch("0042")
	assert_eq(_bomb.net_state, "exploded")
	assert_signal_emit_count(_bomb.entity, "event_received", 1)
	_bomb._fetch()
	assert_signal_emit_count(_bomb.entity, "event_received", 1)
	assert_false(_bomb.can_use(_player))
	_bomb._process(0)
	assert_true(_bomb.get_node("Wreck").visible)
	assert_false(_bomb.get_node("Body").visible)


func test_keypad_use_modal_digits_submission_close_and_range_cleanup() -> void:
	_bomb.use()
	var menu: CanvasLayer = _bomb.get_node("KeypadUI")
	assert_true(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing)
	for digit: String in ["0", "0", "4", "2", "9"]:
		menu._digit(digit)
	assert_eq(menu._code, "0042")
	menu._submit()
	assert_eq(_bomb.net_state, "defused")
	menu._process(0)
	assert_true(menu.is_in_group(&"modal_ui"), "Keep Close available for browser pointer lock")
	assert_string_contains(menu._status.text, "defused")
	menu._close()
	assert_false(menu.is_in_group(&"modal_ui"))
	assert_true(Controls.playing)


func test_keypad_close_and_menu_request_do_not_leave_modal_open() -> void:
	_bomb.use()
	var menu: CanvasLayer = _bomb.get_node("KeypadUI")
	menu._close()
	assert_true(Controls.playing)
	_bomb.use()
	Controls.menu_requested.emit()
	assert_false(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.playing)


func test_countdown_format_and_only_public_state_is_in_spawn_replication() -> void:
	_bomb.net_remaining = 86400
	assert_string_contains(_bomb.status_text(), "24:00:00")
	_bomb.net_remaining = 3661
	assert_string_contains(_bomb.status_text(), "01:01:01")
	var sync := _bomb.entity.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	var fields := sync.replication_config.get_properties()
	assert_eq(fields.size(), 3)
	for field: NodePath in [
		NodePath(".:net_state"), NodePath(".:net_remaining"), NodePath(".:net_available")
	]:
		assert_true(sync.replication_config.property_get_spawn(field))
	assert_false(NodePath(".:code") in fields)


func test_practice_file_corruption_fails_closed_and_is_not_rearmed() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	var puzzle := Puzzle.new()
	puzzle.path = _path
	assert_false(puzzle.load_or_create(123))
	assert_eq(FileAccess.get_file_as_string(_path), "{}")


func _request(payload: Dictionary) -> NetworkedEntity.Result:
	return _bomb.entity._evaluate(1, &"defuse", payload)
