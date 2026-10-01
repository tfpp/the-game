extends GutTest

const ChatBox := preload("res://features/chat_box/chat_box.gd")
const Relay := preload("res://features/chat_box/discord_relay.gd")
const PlayerScene := preload("res://core/player/player.tscn")

var _previous_mode: Network.Mode


class FakeRelay:
	extends Relay
	var bodies: Array[String] = []
	var statuses: Array[int] = [204]

	func _post(body: String) -> int:
		bodies.append(body)
		await get_tree().process_frame
		return statuses.pop_front()


func before_each() -> void:
	_previous_mode = Network.mode


func after_each() -> void:
	Network.mode = _previous_mode


func _relay() -> FakeRelay:
	Network.mode = Network.Mode.SERVER
	var relay := FakeRelay.new()
	relay._configured = true
	relay._url = "http://fixture.invalid/bot/game-chat"
	relay._key = "fixture-key-not-a-secret-1234567890".to_utf8_buffer()
	relay._session = "a".repeat(32)
	add_child_autofree(relay)
	return relay


func test_public_message_is_accepted_once_with_server_display_name() -> void:
	Network.mode = Network.Mode.OFFLINE
	var chat := ChatBox.new()
	add_child_autofree(chat)
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.display_name = "Alice"
	add_child_autofree(player)
	watch_signals(chat)
	chat.request_chat_message("  hello  ")
	assert_signal_emit_count(chat, "message_accepted", 1)
	assert_signal_emitted_with_parameters(chat, "message_accepted", ["Alice", "hello"])
	assert_eq(chat._log.get_child_count(), 1, "original in-game delivery remains")


func test_empty_commands_notices_and_received_messages_never_relay() -> void:
	Network.mode = Network.Mode.OFFLINE
	var chat := ChatBox.new()
	add_child_autofree(chat)
	watch_signals(chat)
	chat.request_chat_message("  ")
	chat.request_chat_message(" /suicide ")
	chat.request_chat_command("unknown")
	chat.send_notice(1, "private wallet notice")
	chat.receive_chat_message("Alice", "received from authority")
	assert_signal_not_emitted(chat, "message_accepted")
	assert_eq(chat._log.get_child_count(), 2)


func test_offline_relay_never_loads_configuration_or_posts() -> void:
	var relay := FakeRelay.new()
	add_child_autofree(relay)
	Network.mode = Network.Mode.OFFLINE
	relay.enqueue("Alice", "hello")
	assert_false(relay._configured)
	assert_true(relay.bodies.is_empty())
	assert_true(relay._pending.is_empty())


func test_queue_preserves_order_and_retries_same_event() -> void:
	var relay := _relay()
	relay.statuses = [502, 204, 204]
	relay.enqueue("Alice", "first")
	relay.enqueue("Bob", "second")
	await wait_until(func() -> bool: return not relay._sending, 5.0)
	assert_eq(relay.bodies.size(), 3)
	assert_eq(relay.bodies[0], relay.bodies[1], "retry retains ID, timestamp and content")
	var first: Dictionary = JSON.parse_string(relay.bodies[0])
	var second: Dictionary = JSON.parse_string(relay.bodies[2])
	assert_eq(first["sender"], "Alice")
	assert_eq(first["text"], "first")
	assert_eq(second["text"], "second")
	assert_ne(first["id"], second["id"])
	assert_eq(first.keys().size(), 4, "no account, peer or network identifiers")


func test_signature_matches_shared_hmac_sha256_vector() -> void:
	var signature := Relay.signature_for(
		'{"sender":"Alice","text":"hello"}', "fixture-key-not-a-secret-1234567890".to_utf8_buffer()
	)
	assert_eq(signature, "e6f01791e8ef0b7e291f760faceedd89e6464c7d61f581a7cff65c5905e3d05c")


func test_failed_delivery_exhausts_only_three_attempts() -> void:
	var relay := _relay()
	relay.statuses = [502, 502, 502]
	relay.enqueue("Alice", "hello")
	await wait_until(func() -> bool: return not relay._sending, 5.0)
	assert_eq(relay.bodies.size(), Relay.MAX_ATTEMPTS)
	assert_true(relay._pending.is_empty())


func test_leaving_server_mode_discards_pending_messages() -> void:
	var relay := _relay()
	relay.enqueue("Alice", "first")
	relay.enqueue("Bob", "queued")
	Network.mode = Network.Mode.OFFLINE
	await wait_until(func() -> bool: return not relay._sending, 2.0)
	assert_eq(relay.bodies.size(), 1)
	assert_true(relay._pending.is_empty())


func test_queue_is_bounded_including_inflight_message() -> void:
	var relay := _relay()
	relay._sending = true
	for index: int in Relay.MAX_PENDING + 10:
		relay.enqueue("Alice", str(index))
	assert_eq(relay._pending.size(), Relay.MAX_PENDING)
	assert_eq(relay._sequence, Relay.MAX_PENDING)
	assert_eq(relay._pending[0]["text"], "0")


func test_permanent_rejection_does_not_retry_or_block_next_message() -> void:
	var relay := _relay()
	relay.statuses = [401, 204]
	relay.enqueue("Alice", "rejected")
	relay.enqueue("Bob", "next")
	await wait_until(func() -> bool: return not relay._sending, 2.0)
	assert_eq(relay.bodies.size(), 2)
	assert_true(relay._pending.is_empty())
