class_name VanTravelPanel
extends CanvasLayer

const MAP := preload("res://features/starter_room/route_map.gd")
const DRIVE := preload("res://features/starter_room/travel_drive.gd")
const UI_THEME := preload("res://ui/theme/ui_theme.tres")

var _body_font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()
var _root: ColorRect
var _status: Label
var _drive: SubViewportContainer
var _map: Control
var _buttons: Array[Button] = []
var _close: Button
var _van: OperationsVan
var _travelling := false
var _waiting := false
var _elapsed := 0.0
var _destination := Vector3.ZERO


func _ready() -> void:
	layer = 20
	_build()
	Controls.menu_requested.connect(_dismiss)
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: close(false))


func open_map(van: OperationsVan) -> void:
	_van = van
	_travelling = false
	_waiting = false
	_close.disabled = false
	_status.text = "VAN ROUTE MAP · choose a destination"
	_map.show()
	_drive.hide()
	_close.show()
	for i: int in _buttons.size():
		_buttons[i].visible = i not in van.dev_routes or DevGate.cheats_enabled(get_tree())
		_buttons[i].disabled = van.arrival(i) == null
	_show()
	_buttons[0].grab_focus()


func depart(van: OperationsVan, zone: int, destination: Vector3) -> void:
	_van = van
	_travelling = true
	_waiting = false
	_elapsed = 0
	_destination = destination
	_status.text = "ENGINE STARTING…\n" + OperationsVan.ZONE_NAMES[zone]
	_map.hide()
	_drive.start()
	_close.hide()
	for button: Button in _buttons:
		button.hide()
	_show()


func update_destination(position: Vector3) -> void:
	_destination = position


func reject_trip() -> void:
	_waiting = false
	_close.disabled = false
	Controls.pause()
	_status.text = "Trip unavailable. Stay beside the van and try again."
	for i: int in _buttons.size():
		_buttons[i].disabled = not is_instance_valid(_van) or _van.arrival(i) == null


func close(resume: bool = true) -> void:
	var was_open := is_open()
	_root.hide()
	_drive.hide()
	_travelling = false
	_waiting = false
	_van = null
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
	if was_open and resume and get_tree().get_first_node_in_group(&"modal_ui") == null:
		Controls.start()


func is_open() -> bool:
	return _root != null and _root.visible


func _show() -> void:
	_root.show()
	add_to_group(&"modal_ui")
	# Travel is a noninteractive overlay: keep the pointer lock obtained in the
	# destination button gesture. The modal group still blocks all gameplay.
	if not _travelling:
		Controls.pause()


func _process(delta: float) -> void:
	if not is_open():
		return
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or not is_instance_valid(_van):
		close(false)
		return
	if _travelling:
		_elapsed += delta
		if _elapsed > .6:
			_status.text = "ON THE ROAD…\nArriving at your destination"
		if (
			_elapsed >= OperationsVan.TRAVEL_SECONDS
			and player.net_position.distance_to(_destination) < 4
		):
			close()
		elif _elapsed > 10:
			close()
	elif not _van.entity.in_range(player):
		close()
	elif _waiting:
		_elapsed += delta
		if _elapsed > 10:
			reject_trip()


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed(&"release_mouse"):
		get_viewport().set_input_as_handled()
		if not _travelling and not _waiting:
			close()


func _dismiss() -> void:
	if is_open() and not _travelling and not _waiting:
		close(false)


func _choose(zone: int) -> void:
	if _waiting or _travelling or not is_instance_valid(_van):
		return
	_waiting = true
	_elapsed = 0
	_close.disabled = true
	_status.text = "Checking route…"
	for button: Button in _buttons:
		button.disabled = true
	# Browsers require a user gesture for pointer lock, not a later RPC/timer.
	# Keep modal_ui until arrival so this cannot enable movement or firing.
	Controls.start()
	_van.request_trip(zone)


func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color("202828")
	_root.theme = UI_THEME
	add_child(_root)
	_status = Label.new()
	_status.add_theme_font_override("font", _body_font)
	_status.add_theme_color_override("font_color", Color("e1d5b5"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_status)
	_map = MAP.new()
	_root.add_child(_map)
	_drive = DRIVE.new()
	_root.add_child(_drive)
	_drive.hide()
	for i: int in OperationsVan.ZONE_NAMES.size():
		var button: Button = _map.add_destination(i, _body_font)
		button.pressed.connect(_choose.bind(i))
		_buttons.append(button)
	_close = Button.new()
	_close.add_theme_font_override("font", _body_font)
	_close.add_theme_font_size_override("font_size", 16)
	_close.text = "Back to garage"
	_close.pressed.connect(close)
	_root.add_child(_close)
	get_viewport().size_changed.connect(_resize)
	_resize()
	_root.hide()


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_body_font.set("oversampling", ui_scale)
	_root.size = logical / ui_scale
	_status.position = Vector2(12, 4)
	_status.size = Vector2(_root.size.x - 24, 52)
	var side := maxf(1, minf(_root.size.x - 24, _root.size.y - 116))
	_map.position = Vector2((_root.size.x - side) * .5, 58 + (_root.size.y - 116 - side) * .5)
	_map.size = Vector2.ONE * side
	_drive.position = _map.position
	_drive.size = _map.size
	_close.position = Vector2((_root.size.x - 200) * .5, _root.size.y - 52)
	_close.size = Vector2(200, 44)
