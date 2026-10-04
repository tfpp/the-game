extends SceneTree
## Process approved billboard artwork; never regenerates the painting.


func _initialize() -> void:
	var source := ProjectSettings.globalize_path(
		"res://../docs/design/model-sources/pawn-tree/generated_source.png"
	)
	var image := Image.load_from_file(source)
	if image == null:
		quit(1)
		return
	# Tight alpha bounds anchor the painted trunk exactly to the quad's bottom.
	var bounds := Rect2i()
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a >= 0.5:
				var pixel := Rect2i(x, y, 1, 1)
				bounds = pixel if bounds.size == Vector2i.ZERO else bounds.merge(pixel)
	image = image.get_region(bounds)
	image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	image.save_png("res://assets/pawn_shop/textures/tree.png")
	quit()
