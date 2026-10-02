extends CanvasLayer
## Local presentation; all paid mutations remain in GunMachine.purchase.

var entity: NetworkedEntity
var _font: Font = ThemeDB.fallback_font.duplicate()
var _panel: ColorRect
var _rows: VBoxContainer
var _heading: Label
var _status: Label
var _wallet: Label
var _buttons: Array[Button] = []
var _category := -1
var _pending := false


func _ready() -> void:
	layer = 9
	add_to_group(&"chat_commands")
	add_to_group(&"esc_menu_links")
	entity = NetworkedEntity.new()
	entity.name = "NetworkedEntity"
	add_child(entity)
	entity.register_action(&"buy", _may_buy, _buy)
	entity.event_received.connect(_event)
	entity.request_finished.connect(_finished)
	Network.mode_changed.connect(_reset)
	Controls.menu_requested.connect(_dismiss)
	_build()


func handle_chat_command(peer: int, command: String) -> void:
	if multiplayer.is_server() and command == "guns" and _player_exists(peer):
		entity.send_event(&"open", {}, peer)


func esc_menu_label() -> String:
	return "Buy guns"


func esc_menu_open() -> void:
	open_menu()


func open_menu() -> void:
	if not _panel.visible and get_tree().get_first_node_in_group(&"modal_ui") != null:
		return
	add_to_group(&"modal_ui")
	Controls.pause()
	_panel.show()
	_show_category(-1)


func close_menu(resume: bool = true) -> void:
	_panel.hide()
	remove_from_group(&"modal_ui")
	if resume and get_tree().get_first_node_in_group(&"modal_ui") == null:
		Controls.start()


func _input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _category >= 0:
			_show_category(-1)
		else:
			close_menu()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			if code == KEY_0:
				close_menu()
			elif code >= KEY_1 and code <= KEY_9:
				var index := code - KEY_1
				if index < _buttons.size() and not _buttons[index].disabled:
					_buttons[index].pressed.emit()
			else:
				return
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		close_menu(false)
		return
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	_wallet.text = (
		"Wallet: "
		+ (
			PlayerMoney.format_money(int(wallet.balances.get(multiplayer.get_unique_id(), 0)))
			if wallet != null
			else "unavailable"
		)
	)


func _may_buy(peer: int, payload: Dictionary) -> bool:
	return (
		payload.size() == 1
		and payload.get("id") is String
		and not GunBuyCatalog.find(payload["id"]).is_empty()
		and _player_exists(peer)
	)


func _player_exists(peer: int) -> bool:
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.multiplayer == multiplayer and player.get_multiplayer_authority() == peer:
			return true
	return false


func _buy(peer: int, payload: Dictionary) -> bool:
	_complete_purchase(peer, str(payload["id"]))
	return true


func _complete_purchase(peer: int, id: String) -> void:
	var machine := get_parent() as GunMachine
	var result: String = await machine.purchase(peer, id)
	if not _player_exists(peer) or result == "Session ended":
		return
	var text := result
	if text.is_empty():
		text = "Purchased! Ammo goes to backpack; classic guns ship empty; generated guns replace rig."
	entity.send_event(&"receipt", {"text": text}, peer)


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"open":
		open_menu()
	elif event == &"receipt":
		_pending = false
		_status.text = str(payload.get("text", ""))
		_set_pending(false)


func _finished(action: StringName, result: int) -> void:
	if action == &"buy" and result != NetworkedEntity.Result.ACCEPTED:
		_status.text = "Purchase denied. Wait a moment and try again."
		_set_pending(false)


func _select(id: String) -> void:
	if _pending:
		return
	_status.text = "Buying…"
	_set_pending(true)
	entity.request_action(&"buy", {"id": id})


func _set_pending(value: bool) -> void:
	_pending = value
	for button: Button in _buttons:
		button.disabled = value and _category >= 0


func _show_category(category: int) -> void:
	_category = category
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_heading.text = "BUY EQUIPMENT" if category < 0 else GunBuyCatalog.CATEGORIES[category]
	if category < 0:
		for index: int in GunBuyCatalog.CATEGORIES.size():
			_buttons.append(
				_button(
					_rows,
					"%d. %s" % [index + 1, GunBuyCatalog.CATEGORIES[index]],
					_show_category.bind(index)
				)
			)
	else:
		var entries := GunBuyCatalog.entries(category)
		for index: int in entries.size():
			var entry := entries[index]
			_buttons.append(
				_button(
					_rows,
					(
						"%d. %s — %s"
						% [index + 1, entry["name"], PlayerMoney.format_money(entry["price"])]
					),
					_select.bind(entry["id"])
				)
			)
		_button(_rows, "Back to categories", _show_category.bind(-1))
	_set_pending(_pending)
	_buttons[0].grab_focus()


func _build() -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.06, 0.08, 0.05, 0.94)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.hide()
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_heading = _label(box, "BUY EQUIPMENT")
	_heading.add_theme_font_size_override("font_size", 24)
	_wallet = _label(box, "Wallet: …")
	_label(
		box,
		"1–9: select  •  0: exit  •  Esc: back\n!guns anywhere • Generated stats roll on purchase"
	)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_status = _label(box, "Choose a category. All purchases use your wallet.")
	_button(box, "0. Exit", close_menu)
	get_viewport().size_changed.connect(_resize)
	_resize()


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_font.set("oversampling", ui_scale)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.size = logical / ui_scale


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", _font)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 44
	button.add_theme_color_override("font_color", Color(0.9, 0.78, 0.42))
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.19, 0.12) if state == "normal" else Color(0.25, 0.28, 0.16)
		style.border_color = Color(0.65, 0.56, 0.28)
		style.set_border_width_all(1)
		style.content_margin_left = 10
		style.content_margin_right = 10
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _reset(_mode: Network.Mode) -> void:
	close_menu(false)
	_pending = false


func _dismiss() -> void:
	if _panel.visible:
		close_menu(false)
