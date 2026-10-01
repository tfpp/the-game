extends CanvasLayer
## Source-engine style chat: Enter opens a line in the top-left corner, typing composes
## it, Enter sends and Esc cancels. Lines fade out a few seconds after they arrive.
##
## Server-authoritative: a client only asks to say something (`request_chat_message`);
## the server re-validates the text, attaches the sender's real name, and relays it to
## everyone, including the sender, via `receive_chat_message`. Nothing is shown locally
## until it comes back from the server.

## Emitted only for accepted public messages, once on the authoritative server.
signal message_accepted(sender_name: String, text: String)

const DiscordRelay := preload("res://features/chat_box/discord_relay.gd")

const MAX_MESSAGE_LENGTH := 120
const MAX_VISIBLE_LINES := 8
const FADE_AFTER_S := 6.0
const FADE_DURATION_S := 1.2
const PANEL_WIDTH := 460.0
const NAME_COLOR := "#ffd166"
const NOTICE_COLOR := "#83e59b"
const OPEN_ACTION := &"chat_open"
const MODAL_GROUP := &"modal_ui"

## Group other features listen on to handle a slash command (see `handle_chat_command`).
const COMMAND_GROUP := &"chat_commands"

## Movement and jump poll raw key state, not GUI focus, so typing a message containing
## "w" or a space would also move or jump the player unless these are held released for
## as long as the chat line is open.
const SUPPRESSED_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"jump"
]

var _log: VBoxContainer
var _line_edit: LineEdit


func _ready() -> void:
	add_to_group(&"chat_box")
	Controls.ensure_action(OPEN_ACTION, [_key_event(KEY_ENTER), _key_event(KEY_KP_ENTER)])
	_build()
	var relay := DiscordRelay.new()
	relay.name = "DiscordRelay"
	add_child(relay)
	message_accepted.connect(relay.enqueue)


func _input(event: InputEvent) -> void:
	if _is_open():
		if event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			_close()
		return
	# Leave chat alone while a menu (e.g. the login screen) is up.
	if get_tree().get_first_node_in_group(MODAL_GROUP):
		return
	if event.is_action_pressed(OPEN_ACTION):
		get_viewport().set_input_as_handled()
		_open()


func _process(_delta: float) -> void:
	if not _is_open():
		return
	for action: StringName in SUPPRESSED_ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)


## Text ready to send: trimmed and capped, same limit the server enforces.
static func sanitize_message(raw: String) -> String:
	return raw.strip_edges().left(MAX_MESSAGE_LENGTH)


## Neutralizes BBCode so a chat message can't inject tags into the RichTextLabel log.
static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


## The BBCode line shown in the log: a colored, escaped sender name plus escaped text.
## An empty sender makes a system notice, shown in NOTICE_COLOR without a name.
static func format_line(sender_name: String, text: String) -> String:
	if sender_name.is_empty():
		return "[color=%s]%s[/color]" % [NOTICE_COLOR, escape_bbcode(text)]
	return (
		"[color=%s]%s:[/color] %s" % [NAME_COLOR, escape_bbcode(sender_name), escape_bbcode(text)]
	)


## A sent line is a command, not a chat message, if it starts with "/".
static func is_command(text: String) -> bool:
	return text.begins_with("/")


## The lowercase command word of a slash command, e.g. "/Suicide now" -> "suicide".
static func parse_command(text: String) -> String:
	return text.substr(1).split(" ")[0].to_lower()


## Client -> server: asks to say `text`. The server re-validates and supplies the
## sender's name itself, so a modified client can't spoof either.
@rpc("any_peer", "call_local", "reliable")
func request_chat_message(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var peer_id := sender_id if sender_id != 0 else multiplayer.get_unique_id()
	var trimmed := sanitize_message(text)
	if trimmed.is_empty() or is_command(trimmed):
		return
	var sender_name := _display_name(peer_id)
	receive_chat_message.rpc(sender_name, trimmed)
	message_accepted.emit(sender_name, trimmed)


## Server -> everyone (including itself): shows an already-validated message.
@rpc("authority", "call_local", "reliable")
func receive_chat_message(sender_name: String, text: String) -> void:
	_add_line(sender_name, text)


## Server-only: shows a system line (no sender name) in one peer's log, such as
## `features/money`'s "+$10.00: Picked up a coin".
func send_notice(peer_id: int, text: String) -> void:
	if not multiplayer.is_server():
		return
	if peer_id == multiplayer.get_unique_id():
		receive_notice(text)
	elif peer_id in multiplayer.get_peers():
		receive_notice.rpc_id(peer_id, text)


@rpc("authority", "call_remote", "reliable")
func receive_notice(text: String) -> void:
	_add_line("", text)


## Client -> server: asks to run a slash command. Commands never appear in the log;
## they're dispatched to whichever feature is listening on `COMMAND_GROUP`, which
## re-validates the real sender itself (the server here only trusts its own peer id).
@rpc("any_peer", "call_local", "reliable")
func request_chat_command(command: String) -> void:
	if not multiplayer.is_server() or command.is_empty():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var peer_id := sender_id if sender_id != 0 else multiplayer.get_unique_id()
	get_tree().call_group(COMMAND_GROUP, &"handle_chat_command", peer_id, command)


func _open() -> void:
	add_to_group(MODAL_GROUP)
	_line_edit.text = ""
	_line_edit.visible = true
	_line_edit.grab_focus()


func _close() -> void:
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	_line_edit.visible = false
	_line_edit.release_focus()


func _is_open() -> bool:
	return _line_edit.visible


func _on_text_submitted(text: String) -> void:
	_close()
	var trimmed := sanitize_message(text)
	if trimmed.is_empty():
		return
	if is_command(trimmed):
		request_chat_command.rpc_id(1, parse_command(trimmed))
	else:
		request_chat_message.rpc_id(1, trimmed)


## Server-side: the display name of a connected player, or a fallback for one with none
## (the local player in offline play, which the server never authenticates).
func _display_name(peer_id: int) -> String:
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.get_multiplayer_authority() == peer_id and not player.display_name.is_empty():
			return player.display_name
	return "Player %d" % peer_id


func _add_line(sender_name: String, text: String) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	line.add_theme_color_override("default_color", Color.WHITE)
	line.text = format_line(sender_name, text)
	_log.add_child(line)
	_fade_out_later(line)
	while _log.get_child_count() > MAX_VISIBLE_LINES:
		_remove_line(_log.get_child(0) as Control)


func _fade_out_later(line: Control) -> void:
	var tween := create_tween()
	line.set_meta(&"fade_tween", tween)
	tween.tween_interval(FADE_AFTER_S)
	tween.tween_property(line, "modulate:a", 0.0, FADE_DURATION_S)
	tween.tween_callback(line.queue_free)


func _remove_line(line: Control) -> void:
	var tween: Variant = line.get_meta(&"fade_tween", null)
	if tween is Tween:
		(tween as Tween).kill()
	_log.remove_child(line)
	line.queue_free()


func _build() -> void:
	var panel := Control.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12.0, 56.0)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	add_child(panel)

	_log = VBoxContainer.new()
	_log.name = "Log"
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 2)
	panel.add_child(_log)

	_line_edit = LineEdit.new()
	_line_edit.name = "Input"
	_line_edit.visible = false
	_line_edit.max_length = MAX_MESSAGE_LENGTH
	_line_edit.placeholder_text = "Public chat (may be recorded in Discord)…"
	_line_edit.custom_minimum_size = Vector2(PANEL_WIDTH, 32.0)
	_line_edit.text_submitted.connect(_on_text_submitted)
	panel.add_child(_line_edit)


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
