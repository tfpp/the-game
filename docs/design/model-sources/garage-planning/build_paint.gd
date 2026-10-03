extends SceneTree
## Two planar UV islands. Repainting is explicit; ordinary geometry builds preserve paint.

const BASE := "res://../docs/design/model-sources/garage-planning/"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">'
		svg += '<rect width="1024" height="1024" fill="#737773"/>'
		svg += '<rect x="20" y="20" width="472" height="984" fill="#d2c7a3"/>'
		svg += '<rect x="532" y="20" width="472" height="984" fill="#234451"/>'
		svg += "</svg>"
		var template := Image.new()
		template.load_svg_from_string(svg)
		template.save_png(BASE + "uv-template.png")
	else:
		var source := Image.load_from_file(args[0])
		source.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		source.save_png("res://assets/starter_room/planning_paper.png")
	quit()
