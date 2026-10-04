extends SceneTree
## Reduce the retained painting to the runtime world-texture budget.


func _initialize() -> void:
	var image := Image.load_from_file(
		"res://../docs/design/model-sources/pawn-street/cityscape-source.png"
	)
	image.resize(128, 64, Image.INTERPOLATE_LANCZOS)
	var result := image.save_png("res://assets/pawn_shop/textures/cityscape.png")
	quit(result)
