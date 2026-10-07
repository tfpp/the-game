extends CanvasLayer
## Recipient-only UI. Buttons send choice IDs and the observed revision, never story state.

var machine: AdventureMachine
var _root: PanelContainer
var _heading: Label
var _place: Label
var _description: Label
var _message: Label
var _inventory: Label
var _history: Label
var _status: Label
var _scroll: ScrollContainer
var _buttons: Array[Button] = []
var _close_button: Button
var _log_button: Button
var _revision := 0
var _waiting := false
var _sent_msec := 0
var _check_in := 0.0
var _font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()


func _ready() -> void:
	layer = 12
	_build()
	machine.entity.request_finished.connect(_finished)
	Controls.menu_requested.connect(close.bind(false))
	get_viewport().size_changed.connect(_resize)
	_resize()
	set_process(false)


func open(page: Dictionary) -> void:
	_root.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	set_process(true)
	_history.hide()
	_log_button.text = "Log"
	_render(page)


func is_open() -> bool:
	return _root.visible


## A delayed choice reply may update an open screen, but never reopens a closed modal.
func update_page(page: Dictionary) -> void:
	if is_open() and int(page["revision"]) >= _revision:
		_render(page)


func close(resume := true) -> void:
	if not is_open():
		return
	_root.hide()
	_waiting = false
	set_process(false)
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _exit_tree() -> void:
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
		Controls.start()


func _input(event: InputEvent) -> void:
	if (
		is_open()
		and (event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"))
	):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	_check_in -= delta
	if _check_in <= 0:
		_check_in = .2
		if not machine.can_play(machine.entity.player_for_peer(multiplayer.get_unique_id())):
			close()
	if _waiting and Time.get_ticks_msec() - _sent_msec > 5000:
		_set_waiting(false)
		_status.text = "Connection slow. Close and Use the cabinet to refresh."


func _render(page: Dictionary) -> void:
	_revision = int(page["revision"])
	_heading.text = str(page["title"]) + " · FREE PLAY"
	_place.text = str(page["place"])
	_description.text = str(page["description"])
	_message.text = str(page["message"])
	_inventory.text = "Pockets: " + str(page["inventory"])
	_history.text = str(page["history"])
	_status.text = ""
	_set_waiting(false)
	var choices: Array = page["choices"]
	var previous := ""
	for button: Button in _buttons:
		if button.has_focus():
			previous = str(button.get_meta("choice", ""))
	var focus: Button
	for index: int in _buttons.size():
		var button := _buttons[index]
		button.visible = index < choices.size()
		if not button.visible:
			continue
		var choice: Dictionary = choices[index]
		button.text = str(choice["label"])
		button.set_meta("choice", str(choice["id"]))
		if focus == null or str(choice["id"]) == previous:
			focus = button
	if focus != null:
		focus.grab_focus()
	else:
		_close_button.grab_focus()
	_scroll.scroll_vertical = 0
	_resize.call_deferred()


func _choose(button: Button) -> void:
	if _waiting or not is_open():
		return
	_sent_msec = Time.get_ticks_msec()
	_set_waiting(true)
	_status.text = "Turning the page…"
	machine.request_choice(str(button.get_meta("choice")), _revision)


func _set_waiting(waiting: bool) -> void:
	_waiting = waiting
	for button: Button in _buttons:
		button.disabled = waiting


func _finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"choose" and result != NetworkedEntity.Result.ACCEPTED and is_open():
		_set_waiting(false)
		_status.text = "Not available yet. Wait and retry, or Close and Use to refresh."


func _toggle_log() -> void:
	_history.visible = not _history.visible
	_log_button.text = "Hide log" if _history.visible else "Log"
	_resize.call_deferred()


func _build() -> void:
	_root = PanelContainer.new()
	_root.theme = preload("res://ui/theme/ui_theme.tres").duplicate() as Theme
	_root.theme.default_font = _font
	_root.theme.default_font_size = 17
	_root.theme.set_font("font", "Button", _font)
	_root.theme.set_font_size("font_size", "Button", 16)
	add_child(_root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_root.add_child(column)
	_heading = _label(column)
	_heading.add_theme_font_size_override("font_size", 19)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	_scroll.add_child(body)
	_place = _label(body)
	_place.add_theme_font_size_override("font_size", 20)
	_description = _label(body)
	_message = _label(body)
	_message.add_theme_color_override("font_color", Color("285543"))
	_inventory = _label(body)
	_inventory.add_theme_font_size_override("font_size", 15)
	_history = _label(body)
	_history.add_theme_font_size_override("font_size", 15)
	_history.hide()
	for index: int in 14:
		var button := _button(body, "", Callable())
		button.pressed.connect(_choose.bind(button))
		_buttons.append(button)
	_status = _label(column)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_log_button = _button(footer, "Log", _toggle_log)
	_close_button = _button(footer, "Close / pause", close)
	# Pointer capture must happen within the web button press's user gesture.
	_close_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_root.hide()


func _label(parent: Node) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 56
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if pressed.is_valid():
		button.pressed.connect(pressed)
	parent.add_child(button)
	return button


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_font.set("oversampling", ui_scale)
	var available := logical / ui_scale
	_root.size = Vector2(minf(700, available.x - 24), minf(760, available.y - 24))
	_root.position = (available - _root.size) * .5
