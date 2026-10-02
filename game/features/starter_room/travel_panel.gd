class_name VanTravelPanel
extends CanvasLayer

const MAP := preload("res://features/starter_room/route_map.gd")
const UI_THEME := preload("res://ui/theme/ui_theme.tres")

var _body_font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()
var _root: ColorRect
var _box: VBoxContainer
var _status: Label
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
	_close.show()
	for i: int in _buttons.size():
		_buttons[i].show()
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
	_close.hide()
	for button: Button in _buttons:
		button.hide()
	_show()


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
	_root.color = Color(.025, .03, .04, 1)
	_root.theme = UI_THEME
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	_root.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	center.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_box)
	_status = Label.new()
	_status.add_theme_font_override("font", _body_font)
	_status.add_theme_color_override("font_color", Color("e1d5b5"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 55
	_box.add_child(_status)
	_map = MAP.new()
	_map.set("map_font", _body_font)
	_box.add_child(_map)
	for i: int in OperationsVan.ZONE_NAMES.size():
		var button := Button.new()
		button.add_theme_font_override("font", _body_font)
		button.add_theme_font_size_override("font_size", 16)
		button.text = (
			"%d · %s\n%s" % [i + 1, OperationsVan.ZONE_NAMES[i], OperationsVan.ZONE_HINTS[i]]
		)
		button.custom_minimum_size.y = 58
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_choose.bind(i))
		_box.add_child(button)
		_buttons.append(button)
	_close = Button.new()
	_close.add_theme_font_override("font", _body_font)
	_close.add_theme_font_size_override("font_size", 16)
	_close.text = "Back to garage"
	_close.custom_minimum_size.y = 44
	_close.pressed.connect(close)
	_box.add_child(_close)
	get_viewport().size_changed.connect(_resize.bind(scroll))
	_resize(scroll)
	_root.hide()


func _resize(scroll: ScrollContainer) -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_body_font.set("oversampling", ui_scale)
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.size = logical / ui_scale
	var available := _root.size - Vector2(32, 32)
	scroll.custom_minimum_size = Vector2(minf(560, available.x), minf(520, available.y))
	_box.custom_minimum_size.x = maxf(150, scroll.custom_minimum_size.x - 16)
