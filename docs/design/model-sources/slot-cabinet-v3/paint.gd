extends SceneTree


func _initialize() -> void:
	var source := Image.load_from_file(
		"../docs/design/model-sources/slot-cabinet-v3/glass-paint-source.png"
	)
	var atlas := Image.create(128, 128, false, Image.FORMAT_RGB8)
	atlas.fill(Color("251b18"))
	# Remap each painted chart independently, correcting ImageGen's shifted gutter.
	for pair: Array in [
		[Rect2(.016, .016, .968, .59), Rect2i(2, 2, 124, 72)],
		[Rect2(.016, .631, .968, .352), Rect2i(2, 78, 124, 48)]
	]:
		var region: Rect2 = pair[0]
		var target: Rect2i = pair[1]
		var image := source.get_region(
			Rect2i(
				region.position * Vector2(source.get_size()),
				region.size * Vector2(source.get_size())
			)
		)
		image.resize(target.size.x, target.size.y, Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), target.position)
		for y: int in range(target.position.y - 2, mini(128, target.end.y + 2)):
			for x: int in range(target.position.x - 2, mini(128, target.end.x + 2)):
				atlas.set_pixel(
					x,
					y,
					image.get_pixel(
						clampi(x - target.position.x, 0, image.get_width() - 1),
						clampi(y - target.position.y, 0, image.get_height() - 1)
					)
				)
	atlas.save_png("res://assets/slot_machine/cabinet_v3/glass.png")
	quit()
