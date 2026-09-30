extends SceneTree
## Bakes round UI icons for the roulette chip rack from the chip model textures, so
## the rack always matches the 3D chips. The face is the top 64x64 of each albedo on
## a square background; everything outside the chip's rim becomes transparent.
## Run: godot --headless --path game -s features/roulette/tools/bake_chip_icons.gd

const DOLLARS: Array[int] = [1, 5, 50, 100, 500, 1000, 5000, 25000]
const FACE := 64
## Measured from the textures: the rim spans pixels 3..60 of the 64-pixel face.
const CENTER := Vector2(31.5, 31.5)
const RADIUS := 29.0


func _init() -> void:
	for dollars: int in DOLLARS:
		var source := "res://assets/casino_chips/textures/chip_%d_albedo.png" % dollars
		var image := Image.load_from_file(ProjectSettings.globalize_path(source))
		image.convert(Image.FORMAT_RGBA8)
		var face := image.get_region(Rect2i(0, 0, FACE, FACE))
		for y: int in FACE:
			for x: int in FACE:
				if Vector2(x, y).distance_to(CENTER) > RADIUS:
					face.set_pixel(x, y, Color.TRANSPARENT)
		face.save_png("res://assets/roulette/ui/chip_%d_icon.png" % dollars)
	quit()
