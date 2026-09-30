extends Control
## Passive graph; no pointer capture while playing.

var samples: Array[Dictionary] = []
var budget_ms := 1000.0 / 60.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.9))
	var maximum := budget_ms * 2.0
	for frame: Dictionary in samples:
		maximum = maxf(maximum, float(frame["duration_ms"]))
	var height := maxf(size.y - 24.0, 1.0)
	var budget_y := size.y - height * budget_ms / maximum
	draw_line(Vector2(0, budget_y), Vector2(size.x, budget_y), Color.YELLOW)
	var points := PackedVector2Array()
	for index: int in samples.size():
		var x := float(index) / maxf(samples.size() - 1, 1) * size.x
		var y := size.y - height * float(samples[index]["duration_ms"]) / maximum
		points.append(Vector2(x, y))
	if points.size() > 1:
		draw_polyline(points, Color.CYAN, 1.5)
	var current := 0.0 if samples.is_empty() else float(samples[-1]["duration_ms"])
	draw_string(
		ThemeDB.fallback_font,
		Vector2(4, 17),
		"Frame %.2f ms | budget %.2f ms" % [current, budget_ms],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color.WHITE
	)
