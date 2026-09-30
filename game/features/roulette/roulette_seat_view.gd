class_name RouletteSeatView
extends CanvasLayer
## Local spectator mode while seated at a roulette table: the player keeps their own
## first-person view and can look around, but cannot walk. A small panel shows the
## round; the bet key (C / controller Y / the touch button) opens the overhead betting
## view, and jump stands up when the player has nothing riding on the spin.

const ACTION := &"roulette_bets"

var table: RouletteTable
var view: RouletteTableView

var _player: Player
var _panel: PanelContainer
var _status: Label
var _swatch: Control
var _hint: Label
var _bets_button: Button
var _leave_button: Button
var _released := false


func _ready() -> void:
	layer = 7
	add_to_group(&"roulette_seat_view")
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	if _player != null:
		# Movement is client-owned; pausing our own simulation holds us in the seat.
		_player.set_physics_process(false)
		_player.velocity = Vector3.ZERO
	_build()
	refresh()


## Registers the rebindable bet-view key: C / controller Y. Every table view calls
## this at startup so the binding shows on the Controls page.
static func register_action() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_Y
	Controls.ensure_action(ACTION, [key, pad])


## Returns movement to the player and removes the panel.
func release() -> void:
	if _released:
		return
	_released = true
	if is_instance_valid(_player):
		# Drop the jump that stood us up so it doesn't fire on the first free frame.
		Controls.clear_input()
		_player.set_physics_process(true)
	queue_free()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	# Player._physics_process is paused, so apply stick/touch look here. Mouse look
	# still reaches Player._unhandled_input directly.
	var look := Controls.consume_look(delta)
	_player.yaw -= look.x
	_player.pitch = clampf(_player.pitch - look.y, deg_to_rad(-89.0), deg_to_rad(89.0))
	_player.net_yaw = _player.yaw
	_player.net_pitch = _player.pitch
	_player.velocity = Vector3.ZERO
	if Controls.consume_jump():
		stand_up()


func _unhandled_input(event: InputEvent) -> void:
	if not Controls.gameplay_active() or event.is_echo():
		return
	if event.is_action_pressed(ACTION):
		get_viewport().set_input_as_handled()
		open_bets()
	elif event.is_action_pressed(&"jump"):
		get_viewport().set_input_as_handled()
		stand_up()


func open_bets() -> void:
	view.open_betting()


## Leaves the seat if allowed (cancelling unlocked bets).
func stand_up() -> void:
	if table.may_leave(multiplayer.get_unique_id()):
		table.request_leave()


func refresh() -> void:
	if _status == null:
		return
	visible = view.screen == null
	var peer := multiplayer.get_unique_id()
	var on_table := RouletteBets.total(table.placements_for(peer))
	var seat := maxi(0, table.seat_of(peer))
	RouletteUiTheme.color_swatch(_swatch, RouletteTableView.SEAT_COLORS[seat])
	var parts := PackedStringArray(["ROULETTE · SEAT %d" % (seat + 1)])
	match table.phase():
		RouletteTable.PHASE_BETTING:
			parts.append("Bets close in %s" % RouletteTableView.clock_text(table.net_seconds_left))
		RouletteTable.PHASE_SPINNING:
			parts.append("No more bets")
		RouletteTable.PHASE_RESULT:
			parts.append(RouletteTableView.pocket_text(int(table.state["number"])))
	if table.phase() != RouletteTable.PHASE_RESULT:
		parts.append("Your bets %s" % PlayerMoney.format_money(on_table))
	_status.text = "   ·   ".join(parts)
	var betting := table.phase() == RouletteTable.PHASE_BETTING
	_bets_button.text = "Place bets" if betting else "Bet view"
	_leave_button.disabled = not table.may_leave(peer)
	_hint.text = _hint_text(betting)


func _hint_text(betting: bool) -> String:
	var pad := Controls.device == Controls.Device.GAMEPAD
	var bets := InputLabels.action_label(ACTION, pad)
	var jump := InputLabels.action_label(&"jump", pad)
	var verb := "place bets" if betting else "watch from above"
	if Controls.device == Controls.Device.TOUCH:
		return "Tap Place bets to open the table"
	if table.may_leave(multiplayer.get_unique_id()):
		return "[%s] %s   ·   [%s] leave table" % [bets, verb, jump]
	return "[%s] %s   ·   your bets are riding" % [bets, verb]


func _build() -> void:
	var root := RouletteUiTheme.root()
	add_child(root)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.position.y = -12
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_swatch = RouletteUiTheme.seat_swatch()
	row.add_child(_swatch)
	_status = _label(row, "", 16)
	_hint = _label(box, "", 14)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	# Clickable on touch (and whenever the pointer is free); keys cover the rest.
	_bets_button = _button(actions, "Place bets", open_bets)
	_leave_button = _button(actions, "Leave table", stand_up)


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
