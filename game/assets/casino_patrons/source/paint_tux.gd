extends SceneTree
## Paints the 64×64 dealer vest texture. Run from game/:
## godot --headless -s assets/casino_patrons/source/paint_tux.gd
## Columns wrap around the torso (front at the centre). The bottom rows sit at the
## collar because the avatar shader maps torso height upwards from the waist.

const SIZE := 64
const VEST := Color("16161a")
const SATIN := Color("24242b")
const SHIRT := Color("eeeeea")
const SHADE := Color("cfcfcb")
const TIE := Color("b3121c")
const KNOT := Color("7e0b12")


func _init() -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y: int in SIZE:
		var height := float(y) / float(SIZE - 1)
		for x: int in SIZE:
			var across := absf(float(x) + 0.5 - SIZE * 0.5)
			# The vest opens into a V towards the collar, showing the white shirt.
			var opening := 2.5 + maxf(height - 0.5, 0.0) * 14.0
			var color := VEST if (x + y) % 7 else SATIN
			if across < opening or height > 0.93:
				color = SHIRT if (y % 5) else SHADE
			if across < 1.0 and height < 0.8 and y % 6 == 0:
				color = VEST
			if height < 0.06:
				color = VEST
			image.set_pixel(x, y, color)
	# Bow tie just under the collar: two wings around a darker knot.
	for y: int in range(SIZE - 7, SIZE - 2):
		for x: int in range(SIZE / 2 - 7, SIZE / 2 + 7):
			var dx := absf(float(x) + 0.5 - SIZE * 0.5)
			var wing := absf(float(y) - float(SIZE - 5)) <= 0.5 + dx * 0.3
			if dx < 1.5:
				image.set_pixel(x, y, KNOT)
			elif wing:
				image.set_pixel(x, y, TIE)
	image.save_png("res://assets/casino_patrons/textures/dealer_tux.png")
	quit()
