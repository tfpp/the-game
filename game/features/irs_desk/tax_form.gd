extends CanvasLayer
## Local form: no winnings lookup, suggested rate or truthfulness calculation.

const Desk := preload("res://features/irs_desk/irs_desk.gd")

var _root: Control
var _panel: PanelContainer
var _winnings: LineEdit
var _tax: LineEdit
var _status: Label
var _submit: Button
var _close_button: Button
var _token := ""
var _waiting := false
var _font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()

@onready var entity: NetworkedInteraction = get_parent().get_node("NetworkedEntity")


func _ready() -> void:
	layer = 9
	_build()
	get_viewport().size_changed.connect(_resize)
	_resize()
	entity.event_received.connect(_event)
	entity.request_finished.connect(_finished)
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
	if _root.visible and not entity.in_range(entity.player_for_peer(multiplayer.get_unique_id())):
		_close()


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"form":
		_token = payload["token"]
		var locked: bool = payload["locked"]
		_winnings.text = _amount_text(payload["winnings"]) if locked else ""
		_tax.text = _amount_text(payload["tax"]) if locked else ""
		_winnings.editable = not locked
		_tax.editable = not locked
		_waiting = payload["busy"]
		_submit.disabled = _waiting
		_submit.text = "Retry same filing" if locked else "Declare and pay"
		_status.text = "Payment pending…" if _waiting else ""
		_root.show()
		add_to_group(&"modal_ui")
		Controls.pause()
		if _waiting:
			_close_button.grab_focus()
		else:
			_winnings.grab_focus()
	elif event == &"receipt" and payload.get("token") == _token:
		_winnings.editable = false
		_tax.editable = false
		_waiting = false
		_status.text = payload["text"]
		_submit.disabled = not payload["retry"]
		_submit.text = "Retry same filing" if payload["retry"] else "Filed"
		_close_button.grab_focus()


func _pay() -> void:
	if _waiting or _submit.disabled:
		return
	var winnings := Desk.parse_amount(_winnings.text, Desk.MAX_WINNINGS_CENTS)
	var tax := Desk.parse_amount(_tax.text, Desk.MAX_TAX_CENTS)
	if winnings < 0 or tax < 0:
		_status.text = "Enter nonnegative dollar amounts with at most two decimal places."
		return
	_waiting = true
	_winnings.editable = false
	_tax.editable = false
	_submit.disabled = true
	_close_button.grab_focus()
	_status.text = "Submitting…"
	entity.request_action(&"file", {"token": _token, "winnings": winnings, "tax": tax})


func _finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"file" and result != NetworkedEntity.Result.ACCEPTED and _waiting:
		_waiting = false
		_submit.disabled = false
		_status.text = "Filing unavailable. Return to the desk or retry the same filing."


func _close(resume := true) -> void:
	if not _root.visible:
		return
	_root.hide()
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _build() -> void:
	_root = Control.new()
	_root.theme = preload("res://ui/theme/ui_theme.tres").duplicate()
	_root.theme.default_font = _font
	_root.theme.default_font_size = 16
	_root.theme.set_font("font", "Button", _font)
	_root.theme.set_font("font", "LineEdit", _font)
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	_label(column, "IRS — GAMBLING DECLARATION")
	_label(column, "We provide no assistance in figuring out the correct amounts.")
	_label(column, Desk.WARNING)
	_label(column, "Gambling winnings declared ($)")
	_winnings = _field(column)
	_label(column, "Tax you choose to pay ($)")
	_tax = _field(column)
	_label(column, "Payment limit: $100 per filing. Payments are final.")
	_submit = Button.new()
	_submit.text = "Declare and pay"
	_submit.custom_minimum_size.y = 48
	_submit.pressed.connect(_pay)
	column.add_child(_submit)
	_status = _label(column, "")
	_close_button = Button.new()
	_close_button.text = "Leave"
	_close_button.custom_minimum_size.y = 48
	_close_button.pressed.connect(_close)
	column.add_child(_close_button)
	_root.hide()


func _label(parent: Node, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _field(parent: Node) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = "0.00"
	field.max_length = 14
	field.custom_minimum_size.y = 48
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	parent.add_child(field)
	return field


func _amount_text(cents: int) -> String:
	return "%d.%02d" % [cents / 100, cents % 100]


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var factor := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * factor
	_font.set("oversampling", factor)
	_root.size = logical / factor
	_panel.custom_minimum_size = Vector2(minf(420, _root.size.x - 24), minf(560, _root.size.y - 24))
