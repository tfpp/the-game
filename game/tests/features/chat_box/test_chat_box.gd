extends GutTest
## Pure text handling for the chat box (features/chat_box/chat_box.gd): sanitizing and
## formatting messages, kept free of scene access so they're unit-testable.

const ChatBox := preload("res://features/chat_box/chat_box.gd")


func test_sanitize_trims_surrounding_whitespace() -> void:
	assert_eq(ChatBox.sanitize_message("  hello there  "), "hello there")


func test_sanitize_truncates_to_the_max_length() -> void:
	var raw := "a".repeat(ChatBox.MAX_MESSAGE_LENGTH + 20)
	assert_eq(ChatBox.sanitize_message(raw).length(), ChatBox.MAX_MESSAGE_LENGTH)


func test_escape_bbcode_neutralizes_tags() -> void:
	assert_eq(ChatBox.escape_bbcode("[img]evil[/img]"), "[lb]img]evil[lb]/img]")


func test_format_line_colors_the_sender_and_keeps_the_text() -> void:
	var line := ChatBox.format_line("Alice", "hi there!")
	assert_true(line.begins_with("[color=%s]Alice:[/color] " % ChatBox.NAME_COLOR))
	assert_true(line.ends_with("hi there!"))


func test_format_line_escapes_a_sender_name_trying_to_close_the_color_tag() -> void:
	var line := ChatBox.format_line("[/color]Evil", "hi")
	assert_false(line.contains("[/color]Evil"))


func test_is_command_detects_a_leading_slash() -> void:
	assert_true(ChatBox.is_command("/suicide"))
	assert_false(ChatBox.is_command("hello"))


func test_parse_command_lowercases_the_first_word() -> void:
	assert_eq(ChatBox.parse_command("/SUICIDE"), "suicide")


func test_parse_command_drops_anything_after_the_first_word() -> void:
	assert_eq(ChatBox.parse_command("/suicide please"), "suicide")
