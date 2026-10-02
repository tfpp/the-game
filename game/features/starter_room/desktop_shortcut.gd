extends Button
## Small native-drawn shortcut icons; no runtime textures or external assets.

var application := ""


func _ready() -> void:
	custom_minimum_size = Vector2(96, 84)
	text = application
	var normal := StyleBoxEmpty.new()
	normal.content_margin_top = 44
	for state: String in ["normal", "hover", "pressed"]:
		add_theme_stylebox_override(state, normal)
	for state: String in [
		"font_color", "font_hover_color", "font_pressed_color", "font_focus_color"
	]:
		add_theme_color_override(state, Color.WHITE)
	add_theme_color_override("font_outline_color", Color("204848"))
	add_theme_constant_override("outline_size", 2)


func _draw() -> void:
	var at := Vector2(size.x / 2 - 16, 8)
	if application == "Files":
		draw_rect(Rect2(at + Vector2(0, 4), Vector2(14, 8)), Color("d9ae46"))
		draw_rect(Rect2(at + Vector2(0, 10), Vector2(32, 22)), Color("f1ce66"))
		draw_line(at + Vector2(1, 11), at + Vector2(31, 11), Color("fff1bc"), 2)
	elif application == "Calculator":
		draw_rect(Rect2(at, Vector2(30, 34)), Color("404860"))
		draw_rect(Rect2(at + Vector2(4, 3), Vector2(22, 8)), Color("b6d8b6"))
		for row: int in 3:
			for column: int in 3:
				draw_rect(
					Rect2(at + Vector2(4 + column * 8, 15 + row * 6), Vector2(5, 4)),
					Color("e0e0e0")
				)
	else:
		draw_rect(Rect2(at + Vector2(4, 0), Vector2(25, 34)), Color("faf3df"))
		draw_rect(Rect2(at + Vector2(4, 0), Vector2(25, 34)), Color("37486a"), false, 2)
		for row: int in 4:
			draw_line(
				at + Vector2(9, 10 + row * 5), at + Vector2(24, 10 + row * 5), Color("586c8a")
			)
		if application == "Jobs":
			draw_rect(Rect2(at + Vector2(10, -2), Vector2(13, 6)), Color("ab8a4f"))
		elif application == "Help":
			draw_circle(at + Vector2(25, 25), 10, Color("164ea0"))
			draw_string(
				ThemeDB.fallback_font,
				at + Vector2(20, 31),
				"?",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				18,
				Color.WHITE
			)
	# Familiar shortcut arrow in the lower-left corner.
	draw_rect(Rect2(at + Vector2(-2, 24), Vector2(12, 12)), Color.WHITE)
	draw_line(at + Vector2(0, 33), at + Vector2(7, 27), Color("000080"), 2)
	draw_line(at + Vector2(3, 27), at + Vector2(7, 27), Color("000080"), 2)
	draw_line(at + Vector2(7, 27), at + Vector2(7, 31), Color("000080"), 2)
