extends CanvasLayer
## Local keypad: mouse, touch and controller all send the same validated request.

var _root: Control
var _digits: Label
var _status: Label
var _code := ""
var _waiting := false
var _close_button: Button
var _first: Button

@onready var bomb: Node3D = get_parent()
@onready var entity: NetworkedInteraction = get_parent().get_node("NetworkedEntity")


func _ready() -> void:
	layer = 9
	_build()
	entity.event_received.connect(_event)
	entity.request_finished.connect(_finished)
	Controls.menu_requested.connect(_close.bind(false))
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: _close(false))
	get_viewport().size_changed.connect(_resize)
	_resize()


func _process(_delta: float) -> void:
	if not _root.visible:
		return
	if not entity.in_range(entity.player_for_peer(multiplayer.get_unique_id())):
		_close()
	elif bomb.net_state == "exploded":
		_status.text = "Bomb has gone off. Close to return to the game."
	elif bomb.net_state == "defused":
		_status.text = "Bomb defused! Close to return to the game."


func _input(event: InputEvent) -> void:
	if (
		_root.visible
		and (event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"))
	):
		get_viewport().set_input_as_handled()
		_close()


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"keypad":
		_code = ""
		_waiting = false
		_digits.text = "____"
		_status.text = "Secret code: four digits. One guess every 5s."
		_root.show()
		add_to_group(&"modal_ui")
		Controls.pause()
		_first.grab_focus()
	elif event == &"reply":
		_waiting = false
		_status.text = str(payload.get("text", ""))


func _digit(digit: String) -> void:
	if _waiting or _code.length() >= 4:
		return
	_code += digit
	_digits.text = _code + "_".repeat(4 - _code.length())


func _clear() -> void:
	if not _waiting:
		_code = ""
		_digits.text = "____"


func _submit() -> void:
	if _waiting or _code.length() != 4:
		return
	_waiting = true
	_status.text = "Checking…"
	entity.request_action(&"defuse", {"code": _code})


func _finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"defuse" and result != NetworkedEntity.Result.ACCEPTED:
		_waiting = false
		_status.text = "Keypad unavailable. Wait or move closer."


func _close(resume := true) -> void:
	if not _root.visible:
		return
	_root.hide()
	remove_from_group(&"modal_ui")
	_code = ""
	if resume:
		Controls.start()


func _exit_tree() -> void:
	if is_in_group(&"modal_ui"):
		Controls.start()


func _build() -> void:
	_root = Control.new()
	_root.theme = preload("res://ui/theme/ui_theme.tres")
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 280
	panel.add_child(column)
	var title := Label.new()
	title.text = "TIMED BOMB — DEFUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_digits = Label.new()
	_digits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_digits)
	var grid := GridContainer.new()
	grid.columns = 3
	column.add_child(grid)
	for digit: String in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]:
		var button := _button(grid, digit, _digit.bind(digit))
		if digit == "1":
			_first = button
	_button(grid, "Clear", _clear)
	_button(grid, "Defuse", _submit)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(280, 54)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_close_button = _button(column, "Close", _close)
	_close_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_root.hide()


func _button(parent: Node, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(90, 44)
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_root.size = logical / ui_scale
