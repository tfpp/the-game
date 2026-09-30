class_name RouletteBettingScreen
extends CanvasLayer
## Local-only betting view a seated player opens from their seat with the bet key:
## an overview camera above the table, a chip rack and bet controls. Placing a chip
## only sends a request; the table's replicated state draws the chips. Esc or the bet
## key returns to the seat view. If the table releases the player while this is open,
## the result stays up until they continue or play again.

signal closed

## Table-local overview camera: above the players' side, looking across the layout.
const CAMERA_POSITION := Vector3(0.5, 2.4, -0.42)
const CAMERA_TARGET := Vector3(0.5, 0.86, 0.0)
const CAMERA_FOV := 50.0
## Raises the layout on screen, clear of the chip rack along the bottom.
const CAMERA_V_OFFSET := -0.24
## While the ball spins the camera pans over the wheel (wheel centre is at
## table-local (-0.98, 0.86, 0)), then back to the layout once the ball has settled.
const WHEEL_CAMERA_POSITION := Vector3(-0.98, 1.72, -0.5)
const WHEEL_CAMERA_TARGET := Vector3(-0.98, 0.9, 0.02)
const WHEEL_V_OFFSET := -0.12
## Seconds into the result the camera stays on the wheel (the ball settles in 0.9 s).
const WHEEL_HOLD_S := 2.0
## Exponential pan rate; ~95% of the way in one second.
const PAN_RATE := 3.0
## Controller cursor speed, layout pixels per second.
const CURSOR_SPEED := 110.0

var table: RouletteTable
var view: RouletteTableView
var camera: Camera3D
var selected := 0
## Spot under the mouse or controller cursor.
var hovered := ""

var _ghost: MeshInstance3D
var _cursor := Vector2(127, 83)
var _using_pad := false
var _heading: Label
var _timer: Label
var _hover_label: Label
var _wallet: Label
var _notice: Label
var _hint: Label
var _chip_buttons: Array[Button] = []
var _undo: Button
var _clear: Button
var _leave: Button
var _back: Button
var _again: Button
var _rack: Control
## The local player asked to leave, so close as soon as the seat is released.
var _leaving := false
var _open := true
var _layout_shot: Transform3D
var _wheel_shot: Transform3D
var _result_elapsed := 0.0


func _ready() -> void:
	layer = 8
	add_to_group(&"modal_ui")
	add_to_group(&"roulette_betting_screen")
	Controls.pause()
	camera = Camera3D.new()
	camera.name = "OverviewCamera"
	camera.fov = CAMERA_FOV
	camera.v_offset = CAMERA_V_OFFSET
	view.add_child(camera)
	_layout_shot = Transform3D(Basis(), CAMERA_POSITION).looking_at(CAMERA_TARGET, Vector3.UP)
	_wheel_shot = (Transform3D(Basis(), WHEEL_CAMERA_POSITION).looking_at(
		WHEEL_CAMERA_TARGET, Vector3.UP
	))
	camera.transform = _layout_shot
	camera.make_current()
	_ghost = MeshInstance3D.new()
	_ghost.name = "HoverChip"
	_ghost.scale = Vector3.ONE * RouletteTableView.CHIP_SCALE
	_ghost.transparency = 0.45
	_ghost.visible = false
	view.add_child(_ghost)
	_build()
	table.entity.request_finished.connect(_on_request_finished)
	refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	if is_instance_valid(camera):
		camera.queue_free()
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	remove_from_group(&"modal_ui")
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	var player_camera := player.get_node_or_null("Camera") as Camera3D if player != null else null
	if player_camera != null:
		player_camera.make_current()
	Controls.start()
	closed.emit()
	queue_free()


## True while the local player holds a seat at the table.
func seated() -> bool:
	return table.seat_of(multiplayer.get_unique_id()) >= 0


func _process(delta: float) -> void:
	pan(delta)
	# Another menu may resume play (capturing the mouse) while we are still seated.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var stick := (
		Controls.deadzone(
			Vector2(
				Input.get_joy_axis(Controls.joypad, JOY_AXIS_LEFT_X),
				Input.get_joy_axis(Controls.joypad, JOY_AXIS_LEFT_Y)
			)
		)
		if Controls.joypad >= 0
		else Vector2.ZERO
	)
	if stick != Vector2.ZERO:
		_using_pad = true
		# Seen from the players' side the layout is rotated: screen right is -X.
		_cursor += -stick * CURSOR_SPEED * delta
		_cursor = _cursor.clamp(Vector2.ZERO, RouletteBets.TEXTURE_SIZE)
		_hover(RouletteBets.spot_at(_cursor))
	_refresh_wallet()
	if _again.visible:
		_again.disabled = not _can_play_again()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed(&"release_mouse")
		or event.is_action_pressed(&"ui_cancel")
		or event.is_action_pressed(RouletteSeatView.ACTION)
	):
		get_viewport().set_input_as_handled()
		close()
		return
	if not seated():
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
			var button := (event as InputEventJoypadButton).button_index
			if button == JOY_BUTTON_A:
				_play_again()
			elif button == JOY_BUTTON_B:
				_continue()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_using_pad = false
		_hover(spot_at_screen((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var click := event as InputEventMouseButton
		var spot := spot_at_screen(click.position)
		_hover(spot)
		if click.button_index == MOUSE_BUTTON_LEFT:
			_place(spot)
		elif click.button_index == MOUSE_BUTTON_RIGHT:
			_remove(spot)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_pad_button((event as InputEventJoypadButton).button_index)
		get_viewport().set_input_as_handled()


func _pad_button(button: JoyButton) -> void:
	_using_pad = true
	match button:
		JOY_BUTTON_A:
			_place(hovered)
		JOY_BUTTON_X:
			_remove(hovered)
		JOY_BUTTON_DPAD_DOWN:
			table.request_undo()
		JOY_BUTTON_B:
			close()
		JOY_BUTTON_LEFT_SHOULDER:
			_select(maxi(0, selected - 1))
		JOY_BUTTON_RIGHT_SHOULDER:
			_select(mini(RouletteBets.DENOMINATIONS.size() - 1, selected + 1))


## True while the camera should frame the wheel rather than the layout.
func watching_wheel() -> bool:
	match table.phase():
		RouletteTable.PHASE_SPINNING:
			return true
		RouletteTable.PHASE_RESULT:
			return _result_elapsed < WHEEL_HOLD_S
	return false


## Eases the camera towards the wheel or layout shot for the current phase.
func pan(delta: float) -> void:
	if table.phase() == RouletteTable.PHASE_RESULT:
		_result_elapsed += delta
	else:
		_result_elapsed = 0.0
	var wheel := watching_wheel()
	var t := 1.0 - exp(-PAN_RATE * delta)
	camera.transform = camera.transform.interpolate_with(_wheel_shot if wheel else _layout_shot, t)
	camera.v_offset = lerpf(camera.v_offset, WHEEL_V_OFFSET if wheel else CAMERA_V_OFFSET, t)


## The betting spot under a viewport position, or "".
func spot_at_screen(screen_position: Vector2) -> String:
	if camera == null or not camera.is_inside_tree():
		return ""
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var local_origin := table.to_local(origin)
	var local_direction := table.global_basis.inverse() * direction
	if absf(local_direction.y) < 0.0001:
		return ""
	var distance := (RouletteBets.LAYOUT_Y - local_origin.y) / local_direction.y
	if distance <= 0.0:
		return ""
	var hit := local_origin + local_direction * distance
	return RouletteBets.spot_at(RouletteBets.local_to_pixel(hit))


## Called by the view whenever the replicated table state changes.
func refresh() -> void:
	if _heading == null:
		return
	var peer := multiplayer.get_unique_id()
	var seat := table.seat_of(peer)
	if seat < 0 and _leaving:
		close()
		return
	_heading.text = "ROULETTE  ·  SEAT %d" % (seat + 1) if seat >= 0 else "ROULETTE"
	_timer.visible = true
	match table.phase():
		RouletteTable.PHASE_BETTING:
			_timer.text = "Bets close in %s" % RouletteTableView.clock_text(table.net_seconds_left)
		RouletteTable.PHASE_SPINNING:
			_timer.text = "No more bets — the wheel is spinning"
		RouletteTable.PHASE_RESULT:
			_timer.text = (
				"%s  —  %s"
				% [RouletteTableView.pocket_text(int(table.state["number"])), _result_text(peer)]
			)
		_:
			_timer.text = _idle_text(peer)
	_rack.visible = seat >= 0
	_undo.visible = seat >= 0
	_clear.visible = seat >= 0
	_back.visible = seat >= 0
	_again.visible = seat < 0
	_again.disabled = not _can_play_again()
	if seat < 0:
		_ghost.visible = false
		_hover_label.text = ""
		_leave.text = "Back to game"
		_leave.disabled = false
		_hint.text = _hint_text()
		return
	var betting := table.phase() == RouletteTable.PHASE_BETTING
	if not betting:
		_hover("")
	var mine := not table.placements_for(peer).is_empty()
	_undo.disabled = not betting or not mine
	_clear.disabled = not betting or not mine
	_leave.disabled = not table.may_leave(peer)
	_leave.text = "Cancel bets & leave" if betting and mine else "Leave table"
	_refresh_wallet()


## After release: the last result, or why the round ended.
func _idle_text(peer: int) -> String:
	if not str(table.state["message"]).is_empty():
		return "%s — the table is closed" % table.state["message"]
	if int(table.state["spin"]) > 0:
		return (
			"%s  —  %s"
			% [RouletteTableView.pocket_text(int(table.state["number"])), _result_text(peer)]
		)
	return ""


func _can_play_again() -> bool:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	return player != null and table.can_use(player)


func _play_again() -> void:
	if _can_play_again():
		table.use()


func _continue() -> void:
	close()


func _result_text(peer: int) -> String:
	var result: Dictionary = (table.state["results"] as Dictionary).get(peer, {})
	if result.is_empty():
		return "no bet this round"
	var net := int(result["payout"]) - int(result["wager"])
	if str(result["status"]) == "void":
		return "bet void"
	if net > 0:
		return "you won %s!" % PlayerMoney.format_money(net)
	if net == 0:
		return "you broke even"
	return "you lost %s" % PlayerMoney.format_money(-net)


func _refresh_wallet() -> void:
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var peer := multiplayer.get_unique_id()
	var balance := int(wallet.balances.get(peer, 0)) if wallet != null else 0
	# Once the ball lands the bets are settled into the balance itself.
	var on_table := (
		0
		if table.phase() == RouletteTable.PHASE_RESULT
		else RouletteBets.total(table.placements_for(peer))
	)
	var available := balance - on_table
	_wallet.text = (
		"Balance %s   ·   On the table %s   ·   Available %s"
		% [
			PlayerMoney.format_money(balance),
			PlayerMoney.format_money(on_table),
			PlayerMoney.format_money(maxi(0, available))
		]
	)
	var betting := table.phase() == RouletteTable.PHASE_BETTING
	for index: int in _chip_buttons.size():
		var value := RouletteBets.DENOMINATIONS[index]
		_chip_buttons[index].disabled = not betting or value > available
		_chip_buttons[index].button_pressed = index == selected
		(_chip_buttons[index].get_node("SelectedRing") as Control).visible = index == selected


func _hover(spot: String) -> void:
	hovered = spot
	var text := RouletteBets.describe(spot)
	if _using_pad and text.is_empty():
		text = "Move the cursor onto the layout"
	_hover_label.text = text
	_ghost.visible = (
		not spot.is_empty() and seated() and table.phase() == RouletteTable.PHASE_BETTING
	)
	if _ghost.visible:
		_ghost.mesh = view.chip_meshes[selected]
		var stacks := RouletteBets.stacks(table.placements_for(multiplayer.get_unique_id()))
		var mine: Array = stacks.get(spot, [])
		var height := mini(mine.size(), RouletteTableView.MAX_STACK)
		_ghost.position = (
			RouletteBets.pixel_to_local(RouletteBets.anchor(spot))
			+ Vector3.UP * (height * RouletteTableView.CHIP_HEIGHT_M + 0.001)
		)


func _place(spot: String) -> void:
	if spot.is_empty() or table.phase() != RouletteTable.PHASE_BETTING:
		return
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var peer := multiplayer.get_unique_id()
	var balance := int(wallet.balances.get(peer, 0)) if wallet != null else 0
	var cents := RouletteBets.DENOMINATIONS[selected]
	if RouletteBets.total(table.placements_for(peer)) + cents > balance:
		_notice.text = "Not enough money for another %s chip" % PlayerMoney.format_money(cents)
		return
	_notice.text = ""
	table.request_bet(spot, cents)


func _remove(spot: String) -> void:
	if not spot.is_empty():
		table.request_remove(spot)


func _request_leave() -> void:
	if not seated():
		_continue()
	elif table.may_leave(multiplayer.get_unique_id()):
		_leaving = true
		table.request_leave()
	else:
		_notice.text = "Your bets are riding on this spin"


func _select(index: int) -> void:
	selected = index
	_refresh_wallet()
	_hover(hovered)


func _on_request_finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if result == NetworkedEntity.Result.ACCEPTED:
		return
	match action:
		&"bet":
			_notice.text = "Bet refused — betting may have closed or your balance changed"
		&"leave":
			_leaving = false
			_notice.text = "You can't leave while your bets are riding"


func _build() -> void:
	var root := RouletteUiTheme.root()
	add_child(root)
	var top := PanelContainer.new()
	top.theme_type_variation = RouletteUiTheme.PLAQUE_TYPE
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 12
	root.add_child(top)
	var top_box := HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 18)
	top.add_child(top_box)
	_heading = _label(top_box, "ROULETTE", 18)
	_heading.theme_type_variation = &"HeadingLabel"
	_timer = _label(top_box, "", 18)
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y = -12
	root.add_child(bottom)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 620
	box.add_theme_constant_override("separation", 4)
	bottom.add_child(box)
	_hover_label = _label(box, "", 16)
	var rack := HFlowContainer.new()
	rack.alignment = FlowContainer.ALIGNMENT_CENTER
	box.add_child(rack)
	_rack = rack
	for index: int in RouletteBets.DENOMINATIONS.size():
		var button := _button(
			rack, _chip_label(RouletteBets.DENOMINATIONS[index]), _select.bind(index)
		)
		button.theme_type_variation = RouletteUiTheme.CHIP_TYPE
		button.icon = RouletteUiTheme.CHIP_ICONS[index]
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(64, 84)
		button.tooltip_text = PlayerMoney.format_money(RouletteBets.DENOMINATIONS[index]) + " chip"
		var ring := RouletteUiTheme.chip_ring()
		ring.set_anchors_preset(Control.PRESET_TOP_WIDE)
		ring.offset_left = -4
		ring.offset_right = 4
		ring.offset_top = -4
		ring.offset_bottom = 64
		ring.visible = false
		button.add_child(ring)
		_chip_buttons.append(button)
	_wallet = _label(box, "", 15)
	_notice = _label(box, "", 14)
	_notice.modulate = Color("ffb36b")
	_hover_label.modulate = RouletteUiTheme.BRASS
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	_undo = _button(actions, "Undo", table.request_undo)
	_clear = _button(actions, "Clear bets", table.request_clear)
	_again = _button(actions, "Play again", _play_again)
	_back = _button(actions, "Seat view", close)
	_leave = _button(actions, "Leave table", _request_leave)
	_hint = _label(box, _hint_text(), 13)
	_hint.modulate = Color(1, 1, 1, 0.7)


## "$1", "$500", "$5K", "$25K".
static func _chip_label(cents: int) -> String:
	var dollars := cents / 100
	return "$%dK" % (dollars / 1000) if dollars >= 1000 else "$%d" % dollars


func _hint_text() -> String:
	if _rack != null and not _rack.visible:
		if Controls.device == Controls.Device.GAMEPAD:
			return "A play again · B back to game"
		return "Esc returns to the game"
	if Controls.device == Controls.Device.GAMEPAD:
		return "Stick aim · A place · X remove · LB/RB chip · D-pad down undo · B/Y seat view"
	if Controls.device == Controls.Device.TOUCH:
		return "Tap the layout to place the selected chip"
	return "Click to place the selected chip · Right-click removes a spot · Esc / C seat view"


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
	button.custom_minimum_size.y = 38
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
