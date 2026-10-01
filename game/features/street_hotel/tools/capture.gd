extends Node3D

const HOTEL := preload("res://features/street_hotel/feature.tscn")
const STREET := preload("res://features/street_district/layout.gd")
const PRESENTATION := preload("res://features/street_district/presentation.gd")
const SPEC := preload("res://features/street_hotel/spec.gd")


func _ready() -> void:
	PRESENTATION.add(self)
	var hotel := HOTEL.instantiate() as Node3D
	add_child(hotel)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 75
	add_child(camera)
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if not args.is_empty() else "user://hotel-previews"
	DirAccess.make_dir_recursive_absolute(folder)
	var shots: Array[Array] = [
		["reception", 0, Vector3(-1.5, 1.7, 6), Vector3(-6, 1.4, 2)],
		["elevator", 0, Vector3(6, 1.7, 9), Vector3(6, 1.5, 4)],
		["lounge", 0, Vector3(0, 1.7, 6), Vector3(-7.3, 1.2, 8.6)],
		["corridor", 0, Vector3(0, 1.7, 13), Vector3(0, 1.7, 68)],
		["guest-102", 0, Vector3(2.8, 1.7, 15), Vector3(8, 1.4, 15)],
		["blue-hour-room", 3, Vector3(2.8, 1.7, 15), Vector3(8, 1.4, 15)],
		["upper-floor-street-view", 9, Vector3(8.8, 1.7, 15), Vector3(42, -20, 29)],
		["penthouse-room", 9, Vector3(2.8, 1.7, 15), Vector3(8, 1.4, 15)],
	]
	for shot: Array in shots:
		for room: StreamedRoom in hotel.floors:
			room.unload_room()
		var room: StreamedRoom = hotel.floors[shot[1]]
		room.load_room(3000)
		camera.position = room.to_global(shot[2])
		camera.look_at(room.to_global(shot[3]))
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(
			get_viewport().get_texture().get_image().save_png(folder + "/" + shot[0] + ".png") == OK
		)
		print("HOTEL_CAPTURE: ", shot[0])
	for room: StreamedRoom in hotel.floors:
		room.unload_room()
	STREET.build(self)
	camera.position = Vector3(-17, 35, -35)
	camera.look_at(Vector3(-43, 19, 28))
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(folder + "/exterior.png") == OK)
	get_tree().quit()
