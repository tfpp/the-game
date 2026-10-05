extends SceneTree
## Keep the generated painting source, import a small mipmapped UI panel.


func _initialize() -> void:
	var image := Image.load_from_file(
		"res://../docs/design/model-sources/workbench-ui/paint-source.png"
	)
	image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	image.save_png("res://assets/starter_room/workbench_blueprint.png")
	quit()
