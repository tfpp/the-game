extends SceneTree
## Convert the generated source atlas into four small runtime texture assets.


func _initialize() -> void:
	var source := Image.load_from_file("res://features/world_builder/tools/source_atlas.png")
	var half := source.get_width() / 2
	var names: Array[String] = ["plaster", "wallpaper", "walnut", "carpet"]
	for index: int in 4:
		var tile := source.get_region(Rect2i((index % 2) * half, (index / 2) * half, half, half))
		tile.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		tile.save_png("res://features/world_builder/textures/%s.png" % names[index])
	quit()
