extends Node
## Render the real game scene: shop, services, exterior and travel map.

var _camera: Camera3D
var _output := "/tmp/gun-store"


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		_output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.size = Vector2i(1280, 720)
	var game := preload("res://main.tscn").instantiate()
	get_tree().root.add_child(game)
	var shop := game.get_node("Features/pawn_shop") as Node3D
	var room := shop.get_node("Room") as StreamedRoom
	room.load_room(60000)
	game.get_node("LoginScreen").set_process(false)
	for overlay: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		overlay.hide()
	_camera = Camera3D.new()
	game.add_child(_camera)
	_camera.current = true
	_camera.position = shop.to_global(Vector3(-3.5, 1.65, 27))
	_camera.look_at(shop.to_global(Vector3(-10, 1.7, 22.5)))
	await _save("shop-arrival")
	_camera.position = shop.to_global(Vector3(-9, 1.65, 26.7))
	_camera.look_at(shop.to_global(Vector3(-12.5, 1.45, 24)))
	await _save("pawn-counter")
	_camera.position = shop.to_global(Vector3(-7, 1.65, 26))
	_camera.look_at(shop.to_global(Vector3(-2.5, 1.5, 23.5)))
	await _save("secondhand-goods")
	_camera.position = shop.to_global(Vector3(-12, 1.65, 26.8))
	_camera.look_at(shop.to_global(Vector3(-9, 1.65, 35)))
	await _save("street-and-van")
	_camera.position = shop.to_global(Vector3(-4.5, 1.65, 27))
	_camera.look_at(shop.to_global(Vector3(-3, 1.5, 29.8)))
	await _save("garage-return")
	get_tree().quit()


func _save(label: String) -> void:
	for frame: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png"))
