class_name GarageJobPanel
extends CanvasLayer
## Private desktop shell, existing jobs application and pinned job readout.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")

var terminal: GarageJobTerminal
var message := ""
var desktop: GarageDesktop
var _body_font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()
var _root: ColorRect
var _list: VBoxContainer
var _header: Label
var _details: Label
var _pin: Label
var _buttons: Array[Button] = []
var _claim_button: Button
var _back: Button
var _pending := false
var _refresh := 0.0


func _ready() -> void:
	layer = 21
	_build()
	Controls.menu_requested.connect(func() -> void: close(false))
	Network.mode_changed.connect(_session_changed)


func _session_changed(_mode: Network.Mode) -> void:
	close(false)
	desktop.reset_session()


func open(computer: GarageJobTerminal) -> void:
	terminal = computer
	message = ""
	_pending = false
	_root.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	_update()
	desktop.minimize()


func close(resume := true) -> void:
	var was_open := is_open()
	_root.hide()
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
	if was_open and resume and get_tree().get_first_node_in_group(&"modal_ui") == null:
		Controls.start()


func is_open() -> bool:
	return _root != null and _root.visible


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0:
		return
	_refresh = .2
	if (
		multiplayer.multiplayer_peer == null
		or (
			multiplayer.multiplayer_peer.get_connection_status()
			!= MultiplayerPeer.CONNECTION_CONNECTED
		)
	):
		_pin.hide()
		close(false)
		desktop.reset_session()
		return
	_update()
	if not is_open():
		return
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or not is_instance_valid(terminal) or not terminal.can_use(player):
		close()


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed(&"release_mouse"):
		get_viewport().set_input_as_handled()
		close()


func _choose(job: int) -> void:
	_pending = true
	message = "Contacting dispatch…"
	terminal.entity.request_action(&"accept", {"job": job})
	_update()


func _claim() -> void:
	_pending = true
	message = "Sending report…"
	terminal.entity.request_action(&"claim")
	_update()


func request_result(_action: StringName, result: NetworkedEntity.Result) -> void:
	_pending = false
	message = "" if result == NetworkedEntity.Result.ACCEPTED else "Unavailable. Try again."
	_update()


func _update() -> void:
	if not is_instance_valid(terminal):
		_pin.hide()
		return
	var data := terminal.record(multiplayer.get_unique_id())
	var job := int(data["job"])
	var xp := int(data["xp"])
	_pin.visible = job >= 0 and not is_open()
	if job >= 0:
		var task := "Return upstairs to CRT · claim $10 + 25 XP"
		if not bool(data["ready"]):
			task = "Take the van; stay near arrival for 3 seconds"
		_pin.text = "JOB · %s\n%s\nSession XP: %d" % [OperationsVan.ZONE_NAMES[job], task, xp]
	_header.text = "GARAGE / FIELDWORK\nJOBS.EXE · Session XP: %d" % xp
	_details.text = message
	if message.is_empty():
		_details.text = (
			"Choose one survey. Visit its van arrival for 3 seconds, then return here."
			+ "\nEach report pays $10 + 25 XP. Each job is available once per session."
		)
		if job >= 0:
			_details.text = "Pinned: " + OperationsVan.ZONE_NAMES[job]
			_details.text += (
				"\nReport ready. Collect below."
				if bool(data["ready"])
				else "\nVisit the arrival point, then return here."
			)
	for i: int in _buttons.size():
		_buttons[i].disabled = (
			_pending or job >= 0 or i in data["done"] or terminal.van.arrival(i) == null
		)
		_buttons[i].text = (
			"%s · $10 + 25 XP%s"
			% [OperationsVan.ZONE_NAMES[i], " · DONE" if i in data["done"] else ""]
		)
	_claim_button.disabled = _pending or not bool(data["ready"])


func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color("071710")
	_root.theme = UI_THEME
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	_root.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	margin.add_child(scroll)
	desktop = GarageDesktop.new()
	desktop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desktop.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(desktop)
	desktop.exit_requested.connect(close)
	_list = desktop.app_body("Jobs")
	_header = _label()
	_details = _label()
	for i: int in OperationsVan.ZONE_NAMES.size():
		var button := _button(OperationsVan.ZONE_NAMES[i])
		button.pressed.connect(_choose.bind(i))
		_buttons.append(button)
	_claim_button = _button("Submit report · collect $10 + 25 XP")
	_claim_button.pressed.connect(_claim)
	_back = _button("Log off computer")
	_back.pressed.connect(close)
	_pin = Label.new()
	_pin.add_theme_font_override("font", _body_font)
	_pin.add_theme_color_override("font_color", Color("b4f5c7"))
	_pin.add_theme_color_override("font_outline_color", Color.BLACK)
	_pin.add_theme_constant_override("outline_size", 6)
	_pin.add_theme_font_size_override("font_size", 14)
	_pin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pin)
	get_viewport().size_changed.connect(_resize)
	_resize()
	_root.hide()
	_pin.hide()


func _label() -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", _body_font)
	label.add_theme_font_size_override("font_size", 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("b4f5c7"))
	_list.add_child(label)
	return label


func _button(title: String) -> Button:
	var button := Button.new()
	button.text = title
	button.add_theme_font_override("font", _body_font)
	button.add_theme_font_size_override("font_size", 16)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("102f20") if state != "disabled" else Color("122018")
		style.border_color = Color("90d6a6") if state == "focus" else Color("386c4a")
		style.set_border_width_all(2)
		style.set_content_margin_all(10)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("b4f5c7"))
	button.add_theme_color_override("font_hover_color", Color("e0ffe9"))
	button.custom_minimum_size.y = 52
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(button)
	return button


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_body_font.set("oversampling", ui_scale)
	desktop.body_font.set("oversampling", ui_scale)
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.size = logical / ui_scale
	# Below the existing player-count / connection readout, above touch actions.
	_pin.position = Vector2(maxf(8, _root.size.x - 318), 96)
	_pin.size = Vector2(minf(310, _root.size.x - 16), 90)
