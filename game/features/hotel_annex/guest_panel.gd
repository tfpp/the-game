extends CanvasLayer
## One local modal per used door; requests always go through its server component.

var _door: HotelGuestDoor
var _root: PanelContainer
var _heading: Label
var _status: Label
var _rows: VBoxContainer
var _snapshot := ""
var _is_owner := false
var _body_font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()


func _ready() -> void:
	layer = 12
	_root = PanelContainer.new()
	var theme := preload("res://ui/theme/ui_theme.tres").duplicate() as Theme
	theme.set_font("font", "Label", _body_font)
	theme.set_font("font", "Button", _body_font)
	_root.theme = theme
	add_child(_root)
	var box := VBoxContainer.new()
	_root.add_child(box)
	_heading = Label.new()
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_heading)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var back := Button.new()
	back.text = "Close"
	back.custom_minimum_size.y = 56
	back.pressed.connect(close)
	box.add_child(back)
	_root.hide()
	get_viewport().size_changed.connect(_resize)
	_resize()


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_body_font.set("oversampling", ui_scale)
	var available := logical / ui_scale
	_root.size = Vector2(minf(520, available.x * 0.9), minf(640, available.y * 0.9))
	_root.position = (available - _root.size) * 0.5


func open(door: HotelGuestDoor, is_owner: bool) -> void:
	_door = door
	_is_owner = is_owner
	if not _door._entity.request_finished.is_connected(_result):
		_door._entity.request_finished.connect(_result)
	if not _door._entity.event_received.is_connected(_event):
		_door._entity.event_received.connect(_event)
	_root.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	_snapshot = ""
	_resize()
	_status.text = "Owners control locks and guest access. No refunds."
	_refresh()


func close() -> void:
	if not _root.visible:
		return
	_root.hide()
	remove_from_group(&"modal_ui")
	Controls.start()


func _exit_tree() -> void:
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
		Controls.start()


func _input(event: InputEvent) -> void:
	if (
		_root.visible
		and (event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"))
	):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	if not _root.visible:
		return
	var player := _door._entity.player_for_peer(multiplayer.get_unique_id())
	if player == null or not _door.can_use(player):
		close()
		return
	_refresh()


func _refresh() -> void:
	_heading.text = (
		"%s · %s\n%s · %s"
		% [
			_door.door_label,
			_door.occupant if not _door.occupant.is_empty() else "Available",
			_door.tenure if not _door.tenure.is_empty() else "Unclaimed",
			"Locked" if _door.locked else "Unlocked"
		]
	)
	var roster: Array[Player] = []
	var snapshot := str([_door.occupant, _door.locked, _door.guests, _door.reservation])
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() != multiplayer.get_unique_id():
			roster.append(player)
			snapshot += str([player.get_multiplayer_authority(), player.display_name])
	if snapshot == _snapshot:
		return
	_snapshot = snapshot
	for child: Node in _rows.get_children():
		child.free()
	_button("Open / close door", "toggle")
	if _door.occupant.is_empty():
		if not _door.reservation.is_empty():
			var notice := Label.new()
			notice.text = "Payment reserved for " + _door.reservation + ". Retry the same choice."
			notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_rows.add_child(notice)
		_button("Rent · $10 / 30 minutes", "rent")
		_button("Purchase · $100 / until server restart", "buy")
	elif _is_owner:
		_button("Owner: " + ("Unlock" if _door.locked else "Lock"), "lock")
		_button("Owner: release room (no refund)", "leave")
		for player: Player in roster:
			var peer := player.get_multiplayer_authority()
			var label := player.display_name if not player.display_name.is_empty() else "Guest"
			_button(
				"Owner: " + ("Revoke " if peer in _door.guests else "Allow ") + label, "guest", peer
			)
	(_rows.get_child(0) as Button).grab_focus()


func _button(label: String, operation: String, guest: int = 0) -> void:
	var button := Button.new()
	button.text = label
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 56
	button.pressed.connect(_door.request_manage.bind(operation, guest))
	_rows.add_child(button)


func _result(action: StringName, result: NetworkedEntity.Result) -> void:
	if action != &"manage" or not _root.visible:
		return
	_status.text = (
		"Request accepted. Payments may take a moment."
		if result == NetworkedEntity.Result.ACCEPTED
		else "Not allowed: check ownership, lock, range or door clearance; wait and retry."
	)


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"notice":
		_status.text = str(payload.get("text", ""))
		_is_owner = bool(payload.get("owner", false))
		_snapshot = ""
