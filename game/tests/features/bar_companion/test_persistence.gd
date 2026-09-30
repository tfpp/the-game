extends GutTest

const FEATURE := preload("res://features/bar_companion/feature.tscn")
const PATH := "user://test-bar-stats.json"
var _bar: BarCompanion
var _mode: Network.Mode


func before_each() -> void:
	_mode = Network.mode
	Network.mode = Network.Mode.SERVER
	Network.peer_accounts.clear()
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(PATH + ".tmp")
	_bar = FEATURE.instantiate() as BarCompanion
	_bar.store.path = PATH
	add_child_autofree(_bar)
	_bar.set_process(false)


func after_each() -> void:
	Network.mode = _mode
	Network.peer_accounts.clear()
	_bar._accounts.clear()
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(PATH + ".tmp")


func _account(peer: int, account: int, display_name := "Alice") -> void:
	Network.peer_accounts[peer] = {"account_id": account, "name": display_name}


func test_refresh_restores_fractional_stats_and_luck_for_new_peer() -> void:
	_account(2, 42)
	_bar.note_win(2)
	_bar.add_drink(2)
	_bar.grant_luck(2)
	_bar.advance(30.0)
	var before: Dictionary = _bar._state[2].duplicate()
	# Network clears identity before feature disconnect callbacks.
	Network.peer_accounts.erase(2)
	_bar.forget(2)
	assert_eq(_bar.charisma_for(2), 0)
	_account(3, 42, "Renamed")
	_bar._process(0.0)
	assert_almost_eq(float(_bar._state[3]["win"]), float(before["win"]), 0.01)
	assert_almost_eq(float(_bar._state[3]["intox"]), float(before["intox"]), 0.01)
	assert_almost_eq(float(_bar._state[3]["luck"]), float(before["luck"]), 0.01)
	assert_eq(_bar.rerolls_for(3), CharmMath.LUCK_REROLLS)
	assert_eq(_bar.price_for(3), CharmMath.price_cents(_bar.charisma_for(3)))


func test_replacement_connection_does_not_replay_old_snapshot() -> void:
	_account(2, 42)
	_bar.add_drink(2)
	_account(3, 42)
	_bar.add_drink(3)
	assert_false(_bar._state.has(2))
	assert_eq(_bar.intoxication_for(3), 2)
	_bar.forget(2)
	assert_eq(_bar.intoxication_for(3), 2, "old disconnect cannot erase new connection")


func test_reused_peer_id_and_equal_names_do_not_share_stats() -> void:
	_account(2, 42)
	_bar.add_drink(2)
	_bar.forget(2)
	_account(2, 99)
	_bar._process(0.0)
	assert_eq(_bar.intoxication_for(2), 0)
	assert_eq(_bar.charisma_for(2), 0)


func test_save_load_survives_feature_restart_and_sobers_while_away() -> void:
	var store := CharmStore.new()
	store.path = PATH
	store.remember(42, {"win": 4.5, "intox": 5.5, "luck": 600.0}, 1000.0)
	store.save()
	var loaded := CharmStore.new()
	loaded.path = PATH
	var row := loaded.restore(42, 1090.0)
	assert_eq(row, {"win": 3.0, "intox": 4.5, "luck": 510.0})
	assert_eq(CharmMath.charisma(row["win"], row["intox"]), 3)
	assert_eq(loaded.restore(42, 2000.0), CharmStore.empty_row())
	assert_eq(loaded.restore(43, 1000.0), CharmStore.empty_row())


func test_expired_connected_stats_cannot_resurrect_on_refresh() -> void:
	_account(2, 42)
	_bar.add_drink(2)
	_bar.advance(1000.0)
	_bar.forget(2)
	_account(3, 42)
	_bar._process(0.0)
	assert_eq(_bar.intoxication_for(3), 0)


func test_offline_and_dev_guests_never_write_account_files() -> void:
	_account(2, 0)
	_bar.add_drink(1)
	_bar.add_drink(2)
	_bar.forget(2)
	assert_false(FileAccess.file_exists(PATH))
	Network.mode = Network.Mode.OFFLINE
	_bar._reset(Network.Mode.OFFLINE)
	assert_eq(_bar.intoxication_for(1), 0)
	assert_true(_bar._accounts.is_empty())


func test_offline_session_does_not_restore_stale_network_identity() -> void:
	_account(1, 42)
	_bar.add_drink(1)
	Network.mode = Network.Mode.OFFLINE
	_bar._reset(Network.Mode.OFFLINE)
	_bar._process(0.0)
	assert_eq(_bar.intoxication_for(1), 0)
	assert_true(_bar._accounts.is_empty())
	_bar.add_drink(1)
	assert_eq(_bar.intoxication_for(1), 1, "offline still uses the server gameplay path")
	assert_almost_eq(
		float(_bar.store.restore(42, Time.get_unix_time_from_system())["intox"]),
		1.0,
		0.01,
		"offline changes do not overwrite account stats"
	)


func test_client_cannot_mutate_or_save_stats() -> void:
	var client := ENetMultiplayerPeer.new()
	assert_eq(client.create_client("127.0.0.1", 17999), OK)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = client
	get_tree().set_multiplayer(api, _bar.get_path())
	_bar.stats = {1: [3, 3, 30]}
	_bar.add_drink(1)
	_bar.note_win(1)
	_bar.grant_luck(1)
	_bar.advance(100.0)
	_bar.forget(1)
	assert_eq(_bar.stats, {1: [3, 3, 30]})
	assert_true(_bar._state.is_empty())
	assert_false(FileAccess.file_exists(PATH))
	get_tree().set_multiplayer(null, _bar.get_path())
	client.close()


func test_decode_rejects_bad_rows_and_caps_valid_values() -> void:
	var store := CharmStore.new()
	var data := {
		"1": {"win": 99, "intox": 99, "luck": 999, "at": 100},
		"2": {"win": "4"},
		"0": {},
		"3": {"win": -1, "intox": 1, "luck": 0, "at": 100}
	}
	store.decode(JSON.stringify(data))
	assert_eq(store.records.size(), 1)
	assert_eq(store.restore(1, 100.0), {"win": 6.0, "intox": 10.0, "luck": 600.0})
	store.decode("not json")
	assert_true(store.records.is_empty())


func test_reset_clears_replication_but_retains_authenticated_save() -> void:
	_account(2, 42)
	_bar.add_drink(2)
	_bar._reset(Network.Mode.SERVER)
	assert_true(_bar.stats.is_empty())
	assert_true(_bar._state.is_empty())
	_bar._process(0.0)
	assert_eq(_bar.intoxication_for(2), 1)
	assert_eq(
		(_bar.get_node("NetworkedEntity") as NetworkedEntity)._actions.size(),
		0,
		"stats expose no client write action"
	)
