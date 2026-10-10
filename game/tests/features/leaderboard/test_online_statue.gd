extends GutTest

const BOARD := preload("res://features/leaderboard/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const MODELS := preload("res://features/player_models/feature.tscn")
var _board: Leaderboard
var _statue: OnlineStatue
var _money: PlayerMoney


func before_each() -> void:
	_board = BOARD.instantiate() as Leaderboard
	add_child_autofree(_board)
	_board.save_path = "user://statue_test.json"
	_board.set_process(false)
	_statue = _board.get_node("OnlineStatue") as OnlineStatue
	_statue.set_process(false)
	_money = PlayerMoney.new()
	add_child_autofree(_money)
	_money.set_process(false)


func after_each() -> void:
	_board._dirty = false
	Network.peer_accounts = {}
	DirAccess.remove_absolute(_board.save_path)


func _player(peer: int, title: String) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.display_name = title
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_offline_portrait_appears_immediately_then_changes_only_every_minute() -> void:
	_player(1, "First")
	_statue._process(0.0)
	assert_eq(_statue.champion["name"], "First")
	assert_not_null(_statue.get_node_or_null("Portrait"))
	_board._process(61.0)
	_statue._process(59.0)
	assert_eq(_statue.champion["seconds"], 0)
	_statue._process(1.0)
	assert_eq(_statue.champion["seconds"], 61)
	assert_string_contains((_statue.get_node("Plaque") as Label3D).text, "0h 01m")
	assert_false((_statue.get_node("Portrait") as BlockPlayerModel).is_processing())


func test_accounts_use_api_total_not_a_second_clock_and_ties_are_stable() -> void:
	Network.peer_accounts = {
		2: {"account_id": 42, "name": "First"}, 3: {"account_id": 43, "name": "Second"}
	}
	_player(2, "Not trusted")
	_player(3, "Second")
	_money.accept_playtime(2, {"playtime_seconds": 3600})
	_money.accept_playtime(3, {"playtime_seconds": 3600})
	_board._process(120.0)
	assert_eq(_board.longest_online()["seconds"], 3600)
	assert_eq(_board.longest_online()["name"], "First")
	_money.accept_playtime(3, {"playtime_seconds": 3601})
	assert_eq(_board.longest_online()["name"], "Second")
	assert_false(_board.longest_online().has("account_id"))
	assert_false(_board.entries[0].has("portrait"), "Existing panel snapshots stay small")


func test_disconnect_reconnect_rename_and_peer_reuse_preserve_the_account_honor() -> void:
	Network.peer_accounts = {2: {"account_id": 42, "name": "Before"}}
	var player := _player(2, "Before")
	_money.accept_playtime(2, {"playtime_seconds": 900})
	assert_eq(_board.longest_online()["seconds"], 900)
	_board._disconnected(2)
	player.free()
	Network.peer_accounts = {}
	_player(2, "Guest")
	_board._process(100.0)
	assert_eq(_board.longest_online()["name"], "Before", "Offline champions stay eligible")
	Network.peer_accounts[3] = {"account_id": 42, "name": "After"}
	_player(3, "Untrusted")
	_money.accept_playtime(3, {"playtime_seconds": 905})
	assert_eq(_board.longest_online()["name"], "After")
	assert_eq(_board.longest_online()["seconds"], 905, "Absolute totals are not added twice")
	assert_eq(_board.entries.size(), 2)


func test_saved_time_and_portrait_survive_restart_and_old_rows_are_accepted() -> void:
	Network.peer_accounts = {2: {"account_id": 42, "name": "Saved"}}
	var player := _player(2, "Saved")
	_money.accept_playtime(2, {"playtime_seconds": 1234})
	var expected := _board.longest_online()
	_board._disconnected(2)
	player.free()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_board.save_path))
	data["43"] = {"name": "Legacy", "money": 20, "jumps": 1, "kills": 0}
	var file := FileAccess.open(_board.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var restored := BOARD.instantiate() as Leaderboard
	add_child_autofree(restored)
	restored.set_process(false)
	restored.save_path = _board.save_path
	var mode := Network.mode
	Network.mode = Network.Mode.SERVER
	var loaded := restored.longest_online()
	assert_eq(loaded["name"], expected["name"])
	assert_eq(loaded["seconds"], expected["seconds"])
	assert_eq(loaded["portrait"]["body"], expected["portrait"]["body"])
	assert_true(OnlineStatue.valid_portrait(loaded["portrait"]))
	assert_eq(restored.entries.size(), 2)
	Network.mode = mode
	_statue.champion = expected
	_statue._reset(Network.Mode.CLIENT)
	assert_true(_statue.champion.is_empty())
	assert_null(_statue.get_node_or_null("Portrait"))


func test_avatar_choices_and_feet_are_preserved_on_the_pedestal() -> void:
	var models := MODELS.instantiate() as PlayerModels
	add_child_autofree(models)
	models.set_process(false)
	_player(1, "Sculpture")
	models.head_types = {1: "frog"}
	models.tail_types = {1: "fin"}
	for body: String in ["default", "girl", "penguin"]:
		models.body_types = {1: body}
		var snapshot := _board.longest_online()
		assert_true(OnlineStatue.valid_portrait(snapshot["portrait"]))
		_statue.champion = snapshot
		var model := _statue.get_node("Portrait") as BlockPlayerModel
		assert_eq(str(model.body_type), body)
		assert_eq(model.head_type, &"frog")
		assert_eq(model.tail_type, &"fin")
		var surface := model.human.surface
		var bounds := surface.get_aabb()
		var bottom := bounds.position.y * model.scale.y
		if body == "penguin":
			bottom = -0.52 * model.scale.y * BlockPlayerModel.PENGUIN_HEIGHT_SCALE
		assert_almost_eq(model.position.y + bottom, 0.9, 0.001, "Feet touch the cap")
		var material := surface.material_override as ShaderMaterial
		assert_true(material.get_shader_parameter("hide_head"))
		assert_false(model.is_processing())
		assert_null(model.player, "Portrait is never a player or damage target")
	await wait_process_frames(1)


func test_missing_and_invalid_heartbeat_fields_do_not_replace_known_time() -> void:
	_money.accept_playtime(1, {"playtime_seconds": 60})
	for result: Dictionary in [{}, {"playtime_seconds": -1}, {"playtime_seconds": "99"}]:
		_money.accept_playtime(1, result)
	assert_eq(_money.playtime_for(1), 60)
	Network.peer_accounts[1] = {"account_id": 99, "name": "Replacement"}
	assert_eq(_money.playtime_for(1), -1, "A reused peer never inherits account time")
	_money._reset(Network.Mode.OFFLINE)
	assert_eq(_money.playtime_for(1), -1)
