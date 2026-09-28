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
	Controls.pause()


func test_an_untouched_peer_has_no_jumps() -> void:
	assert_eq(_feature.jumps_for(1), 0)


func test_request_record_jump_counts_the_sender() -> void:
	_feature.request_record_jump()
	assert_eq(_feature.jumps_for(1), 1)
	_feature.request_record_jump()
	assert_eq(_feature.jumps_for(1), 2)


func test_keeps_separate_jump_counts_per_peer() -> void:
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
	# Rows are rebuilt with queue_free(), so a frame must pass before the old ones
	# are actually gone (see controls_page.gd's rebind list for the same pattern).
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
