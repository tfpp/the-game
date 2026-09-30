extends CanvasLayer
## A local menu opened only after a validated Use; each buy is validated again.

var _font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()
var _root: Control
var _status: Label
var _buttons: Array[Button] = []
var _waiting := false
var _close_button: Button

@onready var stand: PokeStand = get_parent()
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
	if not _root.visible:
		return
	var player := entity.player_for_peer(multiplayer.get_unique_id())
	if not stand.can_use(player):
		_close()


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"menu":
		_root.show()
		add_to_group(&"modal_ui")
		Controls.pause()
		_status.text = "Choose your tip. Each button buys one bowl."
		_waiting = false
		for button: Button in _buttons:
			button.disabled = false
		_buttons[0].grab_focus()
	elif event == &"receipt":
		_waiting = false
		_status.text = str(payload.get("text", "")) + " Close and Use to order again."


func _buy(tip: int) -> void:
	if _waiting:
		return
	_waiting = true
	for button: Button in _buttons:
		button.disabled = true
	_close_button.grab_focus()
	_status.text = "Paying…"
	entity.request_action(&"order", {"tip": tip})


func _finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"order" and result != NetworkedEntity.Result.ACCEPTED and _waiting:
		_waiting = false
		_status.text = "Order unavailable. Close and Use to try again."


func _close(resume := true) -> void:
	if not _root.visible:
		return
	_root.hide()
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.theme = preload("res://ui/theme/ui_theme.tres").duplicate()
	_root.theme.default_font = _font
	_root.theme.default_font_size = 16
	_root.theme.set_font("font", "Button", _font)
	_root.theme.set_font_size("font_size", "Button", 14)
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 290
	var style := _root.theme.get_stylebox("panel", "PanelContainer").duplicate() as StyleBox
	style.content_margin_left = 12
	style.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "POKE BOWLS — $29"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for tip: int in PokeStand.TIPS:
		var button := Button.new()
		button.text = "%d%% — %s" % [tip, PlayerMoney.format_money(PokeStand.total_cents(tip))]
		button.custom_minimum_size = Vector2(140, 44)
		button.pressed.connect(_buy.bind(tip))
		grid.add_child(button)
		_buttons.append(button)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(280, 60)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size.y = 44
	_close_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_close_button.pressed.connect(_close)
	column.add_child(_close_button)
	_root.hide()


func _resize() -> void:
	if not is_instance_valid(_root):
		return
	# Canvas stretching otherwise shrinks a 44px button to 12px on a phone.
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_font.set("oversampling", ui_scale)
	_root.size = logical / ui_scale
