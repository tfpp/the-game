extends GutTest

const ChatBox := preload("res://features/chat_box/chat_box.gd")


func test_offline_session_announces_local_player_without_discord_export() -> void:
	var chat := ChatBox.new()
	add_child_autofree(chat)
	watch_signals(chat)
	Network.mode_changed.emit(Network.Mode.OFFLINE)
	assert_eq(chat._log.get_child_count(), 1)
	assert_eq(chat._log.get_child(0).text, ChatBox.format_line("", "Player 1 joined the game."))
	assert_signal_not_emitted(chat, "message_accepted")


func test_server_session_does_not_announce_a_phantom_host_player() -> void:
	var chat := ChatBox.new()
	add_child_autofree(chat)
	chat._on_mode_changed(Network.Mode.SERVER)
	chat._on_mode_changed(Network.Mode.CLIENT)
	assert_eq(chat._log.get_child_count(), 0)


func test_join_name_is_authenticated_and_bbcode_escaped() -> void:
	var chat := ChatBox.new()
	add_child_autofree(chat)
	var previous := Network.peer_accounts.duplicate(true)
	Network.peer_accounts[42] = {"name": "[color=red]Alice"}
	chat._on_peer_connected(42)
	Network.peer_accounts = previous
	assert_eq(
		chat._log.get_child(0).text, ChatBox.format_line("", "[color=red]Alice joined the game.")
	)
