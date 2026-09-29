extends Control
## Original vector artwork rendered into a small world-screen texture.

const INK := Color("07191e")
const CYAN := Color("64ead0")
const GOLD := Color("ffcc77")
var state: Dictionary = ArcadeComputer.initial_state()
var cursor := Vector2(-20, -20)
var flash := 0.0
var _initialized := false


func set_state(next: Dictionary) -> void:
	if _initialized and int(next.hits) > int(state.hits):
		flash = 0.18
	state = next.duplicate()
	_initialized = true
	queue_redraw()


func set_cursor(point: Vector2) -> void:
	cursor = point * 2
	queue_redraw()


func animate(delta: float) -> bool:
	if flash <= 0:
		return false
	flash = maxf(0, flash - delta)
	queue_redraw()
	return true


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 400), INK)
	draw_rect(Rect2(8, 8, 624, 384), CYAN, false, 2)
	_text(Vector2(24, 30), "UAC // RECREATION TERMINAL", 18, CYAN)
	_text(Vector2(24, 58), "SUPER TURBO TURKEY PUNCHER 3", 27, GOLD)
	_text(Vector2(24, 85), "SCORE %05d   BEST %05d" % [state.score, state.best], 19, Color.WHITE)
	_text(Vector2(496, 85), "%02d SEC" % state.seconds, 19, CYAN)
	# Retro barnyard: blue sky, fence, green ground and a feathered turkey.
	draw_rect(Rect2(24, 96, 592, 206), Color("335b67"))
	draw_circle(Vector2(550, 126), 20, GOLD)
	draw_rect(Rect2(24, 254, 592, 48), Color("52734a"))
	for x: int in range(40, 616, 40):
		draw_rect(Rect2(x, 204, 10, 68), Color("ba9b66"))
	draw_rect(Rect2(24, 222, 592, 9), Color("dbc08b"))
	var shake := Vector2(8 if flash > 0 else 0, 0)
	for index: int in 7:
		var angle := PI + index * PI / 6
		var tip := Vector2(320, 218) + Vector2(cos(angle) * 68, sin(angle) * 77) + shake
		draw_line(Vector2(320, 231) + shake, tip, Color("b75b34"), 24)
		draw_circle(tip, 12, GOLD)
	draw_circle(
		Vector2(320, 227) + shake,
		44,
		Color("79412d") if int(state.hits) / 3 % 2 == 0 else Color("8c5436")
	)
	draw_circle(Vector2(324, 185) + shake, 24, Color("9dcbd1"))
	draw_circle(Vector2(333, 180) + shake, 5, INK)
	draw_colored_polygon(
		PackedVector2Array(
			[Vector2(340, 187) + shake, Vector2(365, 196) + shake, Vector2(339, 203) + shake]
		),
		GOLD
	)
	draw_line(Vector2(336, 203) + shake, Vector2(338, 222) + shake, Color("df4d3e"), 9)
	for x: float in [306, 334]:
		draw_line(Vector2(x, 260), Vector2(x, 281), GOLD, 5)
		draw_line(Vector2(x - 8, 281), Vector2(x + 9, 281), GOLD, 5)
	if flash > 0:
		draw_circle(Vector2(357, 233), 26, Color("e8ad7a"))
		draw_rect(Rect2(368, 232, 82, 32), Color("967551"))
		_text(Vector2(398, 166), "+10!", 30, GOLD)
		if int(state.hits) % 3 == 0:
			_text(Vector2(70, 180), "GOBBLE!", 25, Color.WHITE)
	if state.running:
		_text(Vector2(38, 121), "TURKEYS %d" % (int(state.hits) / 3), 17, Color.WHITE)
		for index: int in 3:
			draw_circle(
				Vector2(46 + index * 20, 142), 6, GOLD if index >= int(state.hits) % 3 else INK
			)
	if not state.running:
		var rect := Rect2(ArcadeComputer.START)
		rect.position *= 2
		rect.size *= 2
		draw_rect(rect, CYAN)
		_text(Vector2(218, 351), "START / RETRY", 24, INK)
	else:
		_text(Vector2(119, 340), "CLICK THE TURKEY TO PUNCH", 24, GOLD)
		_text(Vector2(168, 367), "Three punches = one turkey!", 18, CYAN)
	_text(Vector2(24, 389), "FREE PLAY // " + str(state.name).left(22), 15, CYAN)
	if cursor.x >= 0:
		draw_arc(cursor, 7, 0, TAU, 16, Color.WHITE, 2)
		draw_line(cursor - Vector2(11, 0), cursor + Vector2(11, 0), Color.WHITE)
		draw_line(cursor - Vector2(0, 11), cursor + Vector2(0, 11), Color.WHITE)


func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
