extends VBoxContainer
## Native framed reel card; the live painted weapon remains the first child.

var rarity := Color.WHITE


func _draw() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("171d19")
	frame.border_color = rarity.darkened(0.4)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(4)
	draw_style_box(frame, Rect2(Vector2(3, 0), Vector2(size.x - 6, size.y)))
	draw_rect(Rect2(5, size.y - 4, size.x - 10, 3), rarity)
