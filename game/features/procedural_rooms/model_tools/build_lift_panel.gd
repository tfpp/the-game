extends SceneTree
## Deterministic 128px painted control face; readable bitmap lettering stays exact.

const FONT := {
	"C": [15, 16, 16, 16, 16, 16, 15],
	"B": [30, 17, 17, 30, 17, 17, 30],
	"1": [4, 12, 4, 4, 4, 4, 14],
	"2": [14, 17, 1, 2, 4, 8, 31],
	"3": [30, 1, 1, 14, 1, 1, 30],
	"4": [2, 6, 10, 18, 31, 2, 2],
	"5": [31, 16, 16, 30, 1, 1, 30],
	"F": [31, 16, 16, 30, 16, 16, 16],
	"L": [16, 16, 16, 16, 16, 16, 31],
	"O": [14, 17, 17, 17, 17, 17, 14],
	"R": [30, 17, 17, 30, 20, 18, 17],
	"S": [15, 16, 16, 14, 1, 1, 30]
}


func _initialize() -> void:
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1964
	for y: int in 128:
		for x: int in 128:
			var wear := rng.randf_range(-.025, .025) + sin(y * .8) * .025
			image.set_pixel(x, y, Color(.42 + wear, .32 + wear, .17 + wear))
	image.fill_rect(Rect2i(4, 4, 120, 120), Color("8b7045"))
	image.fill_rect(Rect2i(8, 8, 112, 18), Color("341e18"))
	_text(image, "FLOORS", Vector2i(46, 13), Color("ebd39a"))
	for index: int in 6:
		var y := 34 + index * 15
		image.fill_rect(Rect2i(14, y - 7, 100, 15), Color("302c25"))
		image.fill_rect(Rect2i(17, y - 5, 94, 11), Color("6c6656"))
		_text(image, "C" if index == 0 else "B%d" % index, Vector2i(32, y - 3), Color("f4e7bd"))
		image.fill_rect(Rect2i(85, y - 4, 14, 9), Color("29271f"))
		image.fill_rect(Rect2i(88, y - 2, 8, 5), Color("ac9c68"))
	for x: int in [8, 119]:
		for y: int in [6, 121]:
			image.fill_rect(Rect2i(x - 2, y - 2, 5, 5), Color("302b23"))
			image.fill_rect(Rect2i(x - 1, y, 3, 1), Color("aa996f"))
	assert(image.save_png("res://assets/procedural_rooms/models/elevator/panel.png") == OK)
	print("LIFT_PANEL_BUILD PASS 128x128")
	quit()


func _text(image: Image, text: String, origin: Vector2i, ink: Color) -> void:
	for character: int in text.length():
		var rows: Array = FONT[text[character]]
		for y: int in 7:
			for x: int in 5:
				if int(rows[y]) & (1 << (4 - x)):
					image.set_pixelv(origin + Vector2i(character * 6 + x, y), ink)
