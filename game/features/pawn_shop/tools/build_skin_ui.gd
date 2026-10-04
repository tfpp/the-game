extends SceneTree
## Keep the generated UI painting compact. UI art is separate from world atlases.


func _initialize() -> void:
	var image := Image.load_from_file(
		"res://../docs/design/model-sources/prawn-skin-ui/panel-source.png"
	)
	image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	quit(image.save_png("res://assets/pawn_shop/ui/case_panel.png"))
