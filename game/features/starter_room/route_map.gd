extends TextureRect
## Screen-only paper map. Normalized pins stay attached to landmarks on resize.

const POINTS: Array[Vector2] = [
	Vector2(.22, .23), Vector2(.76, .23), Vector2(.22, .75), Vector2(.76, .75), Vector2(.5, .49)
]
const LABELS: Array[String] = [
	"Golden Crown", "Garage · B1", "Street District", "Pawn & Gun", "Strip Mall"
]
var _pins: Array[Button] = []


func _ready() -> void:
	texture = preload("res://assets/starter_room/travel_map.png")
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)


func add_destination(zone: int, font: Font) -> Button:
	var pin := Button.new()
	pin.text = "%d · %s" % [zone + 1, LABELS[zone]]
	pin.tooltip_text = OperationsVan.ZONE_NAMES[zone] + "\n" + OperationsVan.ZONE_HINTS[zone]
	pin.add_theme_font_override("font", font)
	pin.add_theme_font_size_override("font_size", 12)
	pin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("273e3b")
	normal.border_color = Color("dfb56b")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	pin.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("67532f")
	pin.add_theme_stylebox_override("hover", hover)
	pin.add_theme_stylebox_override("pressed", hover)
	pin.add_theme_color_override("font_color", Color("fff1ce"))
	add_child(pin)
	_pins.append(pin)
	_layout()
	return pin


func _layout() -> void:
	for i: int in _pins.size():
		var pin := _pins[i]
		pin.size = Vector2(minf(140, maxf(110, size.x * .42)), 44)
		pin.position = POINTS[i] * size - pin.size * .5
		pin.position = pin.position.clamp(Vector2.ZERO, (size - pin.size).max(Vector2.ZERO))
	queue_redraw()


func _draw() -> void:
	for point: Vector2 in POINTS:
		var at := point * size + Vector2(0, 25)
		draw_line(at, at + Vector2(0, 10), Color("273e3b"), 3)
		draw_circle(at + Vector2(0, 10), 5, Color("dfb56b"))
