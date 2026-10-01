extends Node3D

const LAYOUT := preload("res://features/street_district/layout.gd")
const OBJECTS := preload("res://features/street_district/street_objects.tscn")
const PRESENTATION := preload("res://features/street_district/presentation.gd")


func _ready() -> void:
	LAYOUT.build(self)
	add_child(OBJECTS.instantiate())
	PRESENTATION.add(self)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if not args.is_empty() else "user://street-previews"
	DirAccess.make_dir_recursive_absolute(folder)
	var shots := [
		["overview", Vector3(67, 63, -49), Vector3(0, 0, 28)],
		["main-street", Vector3(-25, 1.7, 1), Vector3(-1, 2, 1)],
		["alley", Vector3(-14, 1.7, 7), Vector3(-14, 2, 20)],
		["closure", Vector3(26, 1.7, 1), Vector3(34, 1.6, 0)],
		["casino-frontage", Vector3(18.75, 1.7, 27), Vector3(18.75, 3.2, 35)],
		["shop-interior", Vector3(-9.25, 1.7, 7.8), Vector3(-9.25, 1.7, 18)],
		["workshop-interior", Vector3(9.25, 1.7, 35.8), Vector3(9.25, 1.7, 46)]
	]
	for shot: Array in shots:
		camera.position = shot[1]
		camera.look_at(shot[2])
		camera.projection = (
			Camera3D.PROJECTION_ORTHOGONAL
			if shot[0] == "overview"
			else Camera3D.PROJECTION_PERSPECTIVE
		)
		camera.size = 102
		camera.fov = 78
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		assert(image.save_png(folder + "/" + shot[0] + ".png") == OK)
		print("STREET_CAPTURE: ", shot[0])
	get_tree().quit()
