extends Node
## Opt-in Compatibility rendering probe; uses existing geometry and UI.


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var window := get_tree().root
	window.size = Vector2i(400, 700)
	var scene := Node3D.new()
	add_child(scene)
	var door := (
		preload("res://features/hotel_annex/guest_door.tscn").instantiate() as HotelGuestDoor
	)
	scene.add_child(door)
	door.door_label = "Room 101"
	door.occupant = "Preview resident"
	door.tenure = "Rental"
	door.locked = true
	door._owner = "guest:1"
	door.remaining = 1800
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.position = Vector3(0, 1, -1.5)
	player.net_position = player.position
	scene.add_child(player)
	player.set_physics_process(false)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.7, -4)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1.7, 0))
	camera.current = true
	await _save("/tmp/hotel-door.png")
	door.request_use()
	await _save("/tmp/hotel-phone.png")
	window.size = Vector2i(700, 400)
	door._panel.call("_resize")
	await _save("/tmp/hotel-landscape.png")
	door._panel.call("close")
	scene.free()
	get_tree().quit()


func _save(path: String) -> void:
	for frame: int in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(path)
