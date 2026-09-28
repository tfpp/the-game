extends GutTest
## Server-authoritative jump counting (features/leaderboard/leaderboard.gd) and the
## Esc-menu panel that ranks money, jumps and kills (leaderboard_panel.gd).

const LeaderboardScene := preload("res://features/leaderboard/feature.tscn")
const LeaderboardPanel := preload("res://features/leaderboard/leaderboard_panel.gd")
const PlayerScene := preload("res://core/player/player.tscn")
const MoneyScene := preload("res://features/money/feature.tscn")
const CombatScene := preload("res://features/combat/feature.tscn")

var _feature: Leaderboard
var _panel: LeaderboardPanel


func before_each() -> void:
	_feature = LeaderboardScene.instantiate() as Leaderboard
	add_child_autofree(_feature)
	_panel = _feature.get_node("Panel") as LeaderboardPanel


func after_each() -> void:
	Network.peer_accounts = {}
	Controls.pause()


func test_an_untouched_peer_has_no_jumps() -> void:
	assert_eq(_feature.jumps_for(1), 0)


func test_request_record_jump_counts_the_sender() -> void:
	_add_player(1, "Jumper")
	_feature.request_record_jump()
	assert_eq(_feature.jumps_for(1), 1)
	_feature.request_record_jump()
	assert_eq(_feature.jumps_for(1), 2)


func test_keeps_separate_jump_counts_per_peer() -> void:
	_add_player(1, "Jumper")
	_feature.request_record_jump()
	assert_eq(_feature.jumps_for(2), 0)


func test_the_local_players_jump_signal_reports_to_the_server() -> void:
	var player := PlayerScene.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	_feature._process(0.0)
	player.jumped.emit()
	assert_eq(_feature.jumps_for(1), 1)


func test_panel_registers_a_leaderboard_link_in_the_esc_menu() -> void:
	assert_true(_panel.is_in_group(&"esc_menu_links"))
	assert_eq(_panel.esc_menu_label(), "Leaderboard")


func test_opening_the_panel_pauses_and_joins_the_modal_group() -> void:
	_panel.esc_menu_open()
	assert_true(_panel.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())


func test_ranked_peer_ids_sorts_highest_value_first() -> void:
	var peer_ids: Array[int] = [1, 2, 3]
	var order := LeaderboardPanel.ranked_peer_ids(peer_ids, {1: 10, 2: 30, 3: 20})
	assert_eq(order, [2, 3, 1])


func test_ranked_peer_ids_breaks_ties_on_peer_id() -> void:
	var peer_ids: Array[int] = [3, 1, 2]
	var order := LeaderboardPanel.ranked_peer_ids(peer_ids, {1: 5, 2: 5, 3: 5})
	assert_eq(order, [1, 2, 3])


func test_player_label_falls_back_to_a_generic_name() -> void:
	assert_eq(LeaderboardPanel.player_label("Bob", 4), "Bob")
	assert_eq(LeaderboardPanel.player_label("", 4), "Player 4")


func test_value_text_formats_money_as_dollars_and_others_as_plain_counts() -> void:
	assert_eq(LeaderboardPanel.value_text(LeaderboardPanel.Tab.MONEY, 1250), "$12.50")
	assert_eq(LeaderboardPanel.value_text(LeaderboardPanel.Tab.JUMPS, 7), "7")
	assert_eq(LeaderboardPanel.value_text(LeaderboardPanel.Tab.KILLS, 0), "0")


func test_panel_ranks_connected_players_by_the_selected_tab() -> void:
	var money := MoneyScene.instantiate() as PlayerMoney
	add_child_autofree(money)
	money.set_process(false)
	var combat := CombatScene.instantiate() as Combat
	add_child_autofree(combat)

	var rich := PlayerScene.instantiate() as Player
	rich.name = "1"
	rich.display_name = "Rich"
	add_child_autofree(rich)
	rich.set_physics_process(false)

	var poor := PlayerScene.instantiate() as Player
	poor.name = "2"
	poor.set_multiplayer_authority(2)
	poor.display_name = "Poor"
	add_child_autofree(poor)
	poor.set_physics_process(false)

	money.balances = {1: 5000, 2: 100}
	_feature.jumps = {1: 2, 2: 9}
	combat.apply_damage(1, Combat.MAX_HEALTH, 2)

	_panel.esc_menu_open()
	var rows := _rows_text()
	assert_eq(rows, ["#1 Rich (you) $50.00", "#2 Poor $1.00"], "Defaults to the Money tab")

	_panel._select_tab(LeaderboardPanel.Tab.JUMPS)
	await wait_process_frames(1)
	assert_eq(_rows_text(), ["#1 Poor 9", "#2 Rich (you) 2"])

	_panel._select_tab(LeaderboardPanel.Tab.KILLS)
	await wait_process_frames(1)
	assert_eq(_rows_text(), ["#1 Poor 1", "#2 Rich (you) 0"])


func _rows_text() -> Array[String]:
	var rows: Array[String] = []
	for row: Node in _panel._rows.get_children():
		var labels: Array[String] = []
		for label: Label in row.get_children():
			labels.append(label.text)
		rows.append(" ".join(labels))
	return rows


func _add_player(peer: int, display_name: String) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.display_name = display_name
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_unknown_sender_cannot_add_jumps() -> void:
	_feature.request_record_jump()
	assert_eq(_feature.jumps_for(1), 0)


func test_offline_rows_keep_last_balance_and_cumulative_scores() -> void:
	var money := MoneyScene.instantiate() as PlayerMoney
	add_child_autofree(money)
	money.set_process(false)
	var combat := CombatScene.instantiate() as Combat
	add_child_autofree(combat)
	var player := _add_player(2, "Remember me")
	money.balances = {2: 5000}
	_feature.jumps = {2: 9}
	combat.kills = {"2": 3}
	_feature.capture_players()
	# A last update arriving after the frame snapshot is captured on disconnect.
	money.balances[2] = 1200
	_feature.jumps[2] = 10
	_feature._disconnected(2)
	player.free()
	money.balances = {}
	_feature.capture_players()
	assert_eq(_feature.entries.size(), 1)
	assert_eq(
		_feature.entries[0],
		{"name": "Remember me", "money": 1200, "jumps": 10, "kills": 3, "peer": 0}
	)
	_panel.esc_menu_open()
	assert_eq(_rows_text(), ["#1 Remember me (offline) $12.00"])
	_panel._select_tab(LeaderboardPanel.Tab.JUMPS)
	assert_eq(_rows_text(), ["#1 Remember me (offline) 10"])
	_panel._select_tab(LeaderboardPanel.Tab.KILLS)
	assert_eq(_rows_text(), ["#1 Remember me (offline) 3"])


func test_account_reconnect_and_rename_keep_one_row_without_double_counting() -> void:
	# Isolate disk writes while retaining real authenticated identity mapping.
	_feature.save_path = "user://leaderboard_reconnect_test.json"
	Network.peer_accounts = {2: {"account_id": 42, "name": "Before"}}
	var player := _add_player(2, "Untrusted name")
	_feature.jumps = {2: 5}
	_feature.capture_players()
	_feature._disconnected(2)
	player.free()
	Network.peer_accounts = {3: {"account_id": 42, "name": "After"}}
	_add_player(3, "After")
	_feature.jumps[3] = 2
	_feature.capture_players()
	_feature.capture_players()
	assert_eq(_feature.entries.size(), 1)
	assert_eq(_feature.entries[0]["name"], "After")
	assert_eq(_feature.entries[0]["jumps"], 7)
	assert_eq(_feature.entries[0]["peer"], 3)
	assert_false(_feature.entries[0].has("account_id"))
	_feature._dirty = false
	DirAccess.remove_absolute(_feature.save_path)


func test_reused_peer_does_not_inherit_previous_players_scores() -> void:
	var combat := CombatScene.instantiate() as Combat
	add_child_autofree(combat)
	var player := _add_player(2, "First")
	combat.kills = {"2": 3}
	_feature.jumps = {2: 5}
	_feature.capture_players()
	_feature._disconnected(2)
	player.free()
	_add_player(2, "Second")
	_feature.capture_players()
	assert_eq(_feature.entries.size(), 2)
	assert_eq(_feature.entries[1]["jumps"], 0)
	assert_eq(_feature.entries[1]["kills"], 0)
	combat.kills["2"] = 4
	_feature.capture_players()
	assert_eq(_feature.entries[1]["kills"], 1)


func test_disk_round_trip_and_session_reset() -> void:
	_feature.save_path = "user://leaderboard_round_trip_test.json"
	Network.peer_accounts = {2: {"account_id": 42, "name": "Saved"}}
	var player := _add_player(2, "Saved")
	_feature.jumps = {2: 12}
	_feature.capture_players()
	_feature._disconnected(2)
	player.free()
	# Simulate a fresh dedicated-server instance reading the same persistent volume.
	var restored := LeaderboardScene.instantiate() as Leaderboard
	add_child_autofree(restored)
	restored.save_path = _feature.save_path
	var previous_mode := Network.mode
	Network.mode = Network.Mode.SERVER
	restored.capture_players()
	Network.mode = previous_mode
	assert_eq(restored.entries.size(), 1)
	assert_eq(restored.entries[0]["jumps"], 12)
	assert_eq(restored.entries[0]["peer"], 0)
	restored._reset(Network.Mode.CLIENT)
	assert_eq(restored.entries.size(), 0, "No previous server history leaks into another session")
	assert_true(restored._history.is_empty())
	DirAccess.remove_absolute(_feature.save_path)


func test_history_replication_includes_late_join_snapshot() -> void:
	var sync := _feature.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:entries")))
	assert_eq(
		sync.replication_config.property_get_replication_mode(NodePath(".:entries")),
		SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	)


func test_invalid_saved_rows_are_ignored_and_guests_are_not_saved() -> void:
	_feature.save_path = "user://leaderboard_invalid_test.json"
	var file := FileAccess.open(_feature.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"1": {"name": "Bad", "money": []}, "2": false}))
	file.close()
	var previous_mode := Network.mode
	Network.mode = Network.Mode.SERVER
	_feature.capture_players()
	Network.mode = previous_mode
	assert_true(_feature.entries.is_empty())
	_add_player(1, "Guest")
	_feature.capture_players()
	_feature._save()
	var parser := JSON.new()
	parser.parse(FileAccess.get_file_as_string(_feature.save_path))
	assert_false(parser.data.has("guest:1"))
	DirAccess.remove_absolute(_feature.save_path)
