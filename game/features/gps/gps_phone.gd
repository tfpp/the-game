class_name GpsPhone
extends CanvasLayer
## The dual-screen "iPhone Duo" held up in front of the view: the left screen
## searches the place list, the right one shows the active route. Also owns the
## direction banner shown at the top of the screen while a route is active.

signal destination_chosen(destination: GpsDestination)
signal route_cleared

const CATEGORIES: Array[String] = ["Places", "People", "Animals", "Objects"]

const MODAL_GROUP := &"modal_ui"
const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const SCREEN := Vector2(230, 380)
const HINGE := 14.0
const BEZEL := 12.0
const BODY_COLOR := Color("1c1d22")
const SCREEN_COLOR := Color("0d1117")
const ACCENT := Color("c86bff")

var _phone: Control
var _search: LineEdit
var _list: ItemList
var _route_title: Label
var _route_text: Label
var _end_button: Button
var _banner: PanelContainer
var _banner_arrow: Arrow
var _banner_text: Label
var _entries: Array[GpsDestination] = []
var _shown: Array[GpsDestination] = []
var _tween: Tween


func _ready() -> void:
	layer = 9
	_build_banner()
	_build_phone()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton and event.pressed:
		var wheel := event as InputEventMouseButton
		if wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1.0 if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
			_list.get_v_scroll_bar().value += direction * 48.0 * maxf(wheel.factor, 1.0)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func is_open() -> bool:
	return _phone.visible


func open(entries: Array[GpsDestination], active: GpsDestination) -> void:
	_entries = entries
	_search.text = ""
	_filter("")
	if active != null:
		_route_title.text = active.label
	_fit()
	_phone.visible = true
	add_to_group(MODAL_GROUP)
	Controls.pause()
	# Raise the phone from below the screen, like lifting it into view.
	var rest := _phone.position.y
	_phone.position.y = rest + 480.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_phone, "position:y", rest, 0.22).set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	if not Controls.touch_visible():
		_search.grab_focus()


func close() -> void:
	if not is_open():
		return
	if _tween != null:
		_tween.kill()
		_phone.position.y = _rest_y()
	_phone.visible = false
	remove_from_group(MODAL_GROUP)
	Controls.start()


## Case-insensitive match on label and hint; an empty query lists everything.
static func matches(destination: GpsDestination, query: String) -> bool:
	var needle := query.strip_edges().to_lower()
	if needle == "":
		return true
	return (
		destination.category.to_lower().contains(needle)
		or destination.label.to_lower().contains(needle)
		or destination.hint.to_lower().contains(needle)
	)


## Shows `text` in the banner with an arrow turned `angle` radians clockwise.
func set_guidance(text: String, angle: float, place: String) -> void:
	_banner.visible = text != ""
	_banner_text.text = text
	_banner_arrow.angle = angle
	_banner_arrow.queue_redraw()
	_route_title.text = place if place != "" else "No route"
	_route_text.text = text if text != "" else "Pick a place on the left screen."
	_end_button.disabled = text == ""


func shown() -> Array[GpsDestination]:
	return _shown


func choose(index: int) -> void:
	if index < 0 or index >= _shown.size():
		return
	if not is_instance_valid(_shown[index]) or not _shown[index].available():
		_filter(_search.text)
		return
	destination_chosen.emit(_shown[index])
	_route_title.text = _shown[index].label
	_route_text.text = "Routing..."
	close()


func _filter(query: String) -> void:
	_list.clear()
	_shown.clear()
	for category: String in CATEGORIES:
		var header := -1
		for destination: GpsDestination in _entries:
			if not is_instance_valid(destination) or not destination.available():
				continue
			if destination.category != category or not matches(destination, query):
				continue
			if header < 0:
				header = _list.add_item(category)
				_list.set_item_selectable(header, false)
				_list.set_item_custom_fg_color(header, ACCENT)
				_list.set_item_metadata(header, -1)
			var caption := destination.label
			var player := get_tree().get_first_node_in_group(&"local_player") as Node3D
			if player != null and destination.tracks_source:
				var distance := player.global_position.distance_to(
					destination.destination_position()
				)
				caption += " · %d m" % roundi(distance)
			var index := _list.add_item(caption)
			_list.set_item_metadata(index, _shown.size())
			_list.set_item_tooltip(index, destination.hint)
			_shown.append(destination)
	if not _shown.is_empty():
		_list.select(1)


func _submit(_text: String) -> void:
	var selected := _list.get_selected_items()
	if not selected.is_empty():
		_choose_row(selected[0])


func _choose_row(index: int) -> void:
	choose(int(_list.get_item_metadata(index)))


func _rest_y() -> float:
	return -(SCREEN.y + BEZEL * 2.0) * _phone.scale.y - 12.0


## Shrinks the phone to fit small (phone) screens.
func _fit() -> void:
	var view := get_viewport().get_visible_rect().size
	var fit := minf(1.0, minf((view.x - 16.0) / _phone.size.x, (view.y - 16.0) / _phone.size.y))
	_phone.scale = Vector2.ONE * maxf(fit, 0.3)
	_phone.position = Vector2(-_phone.size.x * _phone.scale.x * 0.5, _rest_y())


func _build_phone() -> void:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.theme = UI_THEME
	add_child(anchor)
	var width := SCREEN.x * 2.0 + HINGE + BEZEL * 4.0
	_phone = Panel.new()
	_phone.size = Vector2(width, SCREEN.y + BEZEL * 2.0)
	_phone.add_theme_stylebox_override(&"panel", _rounded(BODY_COLOR, 26, Color("5a5d66")))
	_phone.visible = false
	anchor.add_child(_phone)
	var hinge := ColorRect.new()
	hinge.color = Color("3a3c44")
	hinge.position = Vector2(BEZEL * 2.0 + SCREEN.x, 18)
	hinge.size = Vector2(HINGE, SCREEN.y + BEZEL * 2.0 - 36)
	_phone.add_child(hinge)
	var left := _screen(Vector2(BEZEL, BEZEL))
	var right := _screen(Vector2(BEZEL * 3.0 + SCREEN.x + HINGE, BEZEL))
	left.add_child(_heading("Maps"))
	_search = LineEdit.new()
	_search.placeholder_text = "Search destinations"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_filter)
	_search.text_submitted.connect(_submit)
	left.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_clicked.connect(
		func(index: int, _at: Vector2, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_choose_row(index)
	)
	_list.item_activated.connect(_choose_row)
	left.add_child(_list)
	right.add_child(_heading("Route"))
	_route_title = Label.new()
	_route_title.text = "No route"
	_route_title.add_theme_font_size_override(&"font_size", 20)
	_route_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_route_title)
	_route_text = Label.new()
	_route_text.text = "Pick a place on the left screen."
	_route_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_route_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_route_text)
	_end_button = Button.new()
	_end_button.text = "End route"
	_end_button.disabled = true
	_end_button.pressed.connect(func() -> void: route_cleared.emit())
	right.add_child(_end_button)
	var done := Button.new()
	done.text = "Put phone away"
	done.pressed.connect(close)
	right.add_child(done)


func _screen(at: Vector2) -> VBoxContainer:
	var glass := PanelContainer.new()
	glass.position = at
	glass.size = SCREEN
	glass.add_theme_stylebox_override(&"panel", _rounded(SCREEN_COLOR, 16, Color("000000"), 10))
	_phone.add_child(glass)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	glass.add_child(column)
	return column


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", ACCENT)
	label.add_theme_font_size_override(&"font_size", 22)
	return label


func _build_banner() -> void:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_CENTER_TOP)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_banner = PanelContainer.new()
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.position = Vector2(-160, 12)
	_banner.custom_minimum_size = Vector2(320, 0)
	_banner.add_theme_stylebox_override(
		&"panel", _rounded(Color(0.07, 0.05, 0.1, 0.85), 10, ACCENT, 8)
	)
	anchor.add_child(_banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	_banner.add_child(row)
	_banner_arrow = Arrow.new()
	_banner_arrow.custom_minimum_size = Vector2(28, 28)
	row.add_child(_banner_arrow)
	_banner_text = Label.new()
	_banner_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_banner_text)


static func _rounded(color: Color, radius: int, border: Color, margin: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(margin)
	return box


## The banner's direction arrow; `angle` is clockwise from straight ahead.
class Arrow:
	extends Control

	var angle := 0.0

	func _draw() -> void:
		var middle := size * 0.5
		var points := PackedVector2Array()
		for point: Vector2 in [Vector2(0, -12), Vector2(9, 9), Vector2(0, 4), Vector2(-9, 9)]:
			points.append(middle + point.rotated(angle))
		draw_colored_polygon(points, ACCENT)
