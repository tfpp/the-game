extends CanvasLayer
## Local topic menu / journal. All topic changes are independently server-validated.

var _root: Control
var _heading: Label
var _text: Label
var _choices: VBoxContainer
var _buttons: Array[Button] = []
var _close_button: Button
var _entity: NetworkedInteraction
var _stand: Node3D
var _font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()


func _ready() -> void:
	layer = 9
	_stand = get_parent() as Node3D
	if _stand != null:
		_entity = _stand.get_node("NetworkedEntity") as NetworkedInteraction
		_entity.event_received.connect(_event)
		_entity.request_finished.connect(_finished)
	_build()
	get_viewport().size_changed.connect(_resize)
	_resize()
	Controls.menu_requested.connect(_close.bind(false))
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: _close(false))


func _input(event: InputEvent) -> void:
	if (
		_root.visible
		and (event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"))
	):
		get_viewport().set_input_as_handled()
		_close()


func _process(_delta: float) -> void:
	if _root.visible and _stand != null:
		var player := _entity.player_for_peer(multiplayer.get_unique_id())
		if not _entity.in_range(player):
			_close()


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"case_page":
		show_page(
			str(payload.get("title", "VIVIENNE'S CASE")),
			str(payload.get("text", "")),
			payload.get("choices", []) as Array
		)


func show_page(title: String, text: String, choices: Array) -> void:
	_heading.text = title
	_text.text = text
	for index: int in _buttons.size():
		var button := _buttons[index]
		button.visible = index < choices.size()
		button.disabled = false
		if button.visible:
			var choice: Dictionary = choices[index]
			button.text = str(choice["label"])
			button.set_meta("choice", str(choice["id"]))
	_root.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	if not choices.is_empty():
		(_choices.get_child(0) as Button).grab_focus()
	else:
		_close_button.grab_focus()


func _choose(id: String) -> void:
	if _entity == null:
		return
	for button: Button in _choices.get_children():
		button.disabled = true
	_close_button.grab_focus()
	if id == "hire":
		_close()
		_entity.request_use()
	else:
		_entity.request_action(&"case", {"step": int(id)})


func _finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"case" and result != NetworkedEntity.Result.ACCEPTED and _root.visible:
		_text.text = "That topic is no longer available. Close and Use to refresh."


func _close(resume := true) -> void:
	if not is_instance_valid(_root) or not _root.visible:
		return
	_root.hide()
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _exit_tree() -> void:
	if is_instance_valid(_root) and _root.visible:
		remove_from_group(&"modal_ui")
		Controls.start()


func _build() -> void:
	_root = Control.new()
	_root.theme = preload("res://ui/theme/ui_theme.tres").duplicate()
	_root.theme.default_font = _font
	_root.theme.default_font_size = 16
	_root.theme.set_font("font", "Button", _font)
	_root.theme.set_font_size("font_size", "Button", 14)
	add_child(_root)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_heading = Label.new()
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_text)
	_choices = VBoxContainer.new()
	body.add_child(_choices)
	for index: int in 2:
		var button := Button.new()
		button.custom_minimum_size.y = 48
		button.pressed.connect(func() -> void: _choose(str(button.get_meta("choice", ""))))
		_choices.add_child(button)
		_buttons.append(button)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size.y = 48
	_close_button.pressed.connect(_close)
	column.add_child(_close_button)
	_root.hide()


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_font.set("oversampling", ui_scale)
	var size := logical / ui_scale
	_root.size = Vector2(minf(540, size.x - 24), minf(560, size.y - 24))
	_root.position = (size - _root.size) * 0.5
