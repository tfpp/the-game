extends Control
## Schematic, not geographic distances: destinations are separate streamed districts.

var map_font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(0, 140)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var base := Vector2(size.x * .5, 116)
	var pins: Array[Vector2] = []
	for index: int in OperationsVan.ZONE_NAMES.size():
		var fraction := float(index + 1) / float(OperationsVan.ZONE_NAMES.size() + 1)
		pins.append(Vector2(size.x * fraction, 24 + 10 * absf(fraction - .5)))
	for i: int in pins.size():
		var point := pins[i]
		draw_polyline(
			PackedVector2Array([base, Vector2(point.x, 85), point]), Color("b29a62"), 3, true
		)
		draw_circle(point, 12, Color("c6ac72"))
		draw_string(
			map_font,
			point + Vector2(-4, 5),
			str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color("202830")
		)
	draw_rect(Rect2(base - Vector2(30, 9), Vector2(60, 18)), Color("738886"))
	draw_string(map_font, base + Vector2(-20, 5), "BASE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
