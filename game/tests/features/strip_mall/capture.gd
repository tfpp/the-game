extends Node
## Actual main-game renderer review, plus exported awning/planter contact views.

var _camera: Camera3D
var _output := "/tmp/strip-mall"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		_output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.size = Vector2i(1280, 720)
	var game := preload("res://main.tscn").instantiate()
	get_tree().root.add_child(game)
	var room := game.get_node("Features/strip_mall/Room") as StreamedRoom
	room.load_room(60000)
	game.get_node("LoginScreen").set_process(false)
	for overlay: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		overlay.hide()
	_camera = Camera3D.new()
	game.add_child(_camera)
	_camera.current = true
	_view(Vector3(0, 1.65, 25), Vector3(2, 1.8, 25))
	await _save("casino-entrance")
	_view(room.to_global(Vector3(4, 1.65, 28)), room.to_global(Vector3(30, 2, 28)))
	await _save("arrival")
	_view(room.to_global(Vector3(-6, 10, 44)), room.to_global(Vector3(20, 1, 28)))
	await _save("overview")
	_view(room.to_global(Vector3(26, 1.65, 29.35)), room.to_global(Vector3(31, 1.8, 29)))
	await _save("kebab")
	_view(room.to_global(Vector3(28.3, 1.65, 35)), room.to_global(Vector3(30, 1.7, 35)))
	await _save("wendys")
	_view(room.to_global(Vector3(28.3, 1.65, 22.5)), room.to_global(Vector3(30, 1.7, 22.5)))
	await _save("poke")
	var rivalry := room.get_node("Rivalry")
	rivalry.set_physics_process(false)
	rivalry.net_turn = 0
	rivalry.net_remaining = 4.0
	_view(room.to_global(Vector3(15, 4, 33)), room.to_global(Vector3(15, 1.5, 43)))
	await _save("rival-plaza")
	_view(room.to_global(Vector3(12, 1.65, 39)), room.to_global(Vector3(9, 1.3, 41)))
	await _save("city-wok")
	rivalry.net_turn = 1
	_view(room.to_global(Vector3(18, 1.65, 39)), room.to_global(Vector3(21, 1.3, 41)))
	await _save("city-sushi")
	assert(room.get_node("FrogDisplay/Colony/Pond").get_child_count() == 3)
	_view(room.to_global(Vector3(24, 1.65, 42.5)), room.to_global(Vector3(30, 2, 42.5)))
	await _save("zabka")
	_view(room.to_global(Vector3(28.8, 1.65, 41.5)), room.to_global(Vector3(31.25, 1.4, 41.5)))
	await _save("frogs")
	_view(room.to_global(Vector3(6, 1.65, 28)), room.to_global(Vector3(2.3, 1.5, 28)))
	await _save("return")
	_view(room.to_global(Vector3(24, 2.6, 20)), room.to_global(Vector3(28, 3.15, 20)))
	await _save("awning-underside")
	_view(room.to_global(Vector3(4, 1.65, 21)), room.to_global(Vector3(5, .8, 19)))
	await _save("planter")
	get_tree().quit()


func _view(eye: Vector3, target: Vector3) -> void:
	_camera.position = eye
	_camera.look_at(target)


func _save(label: String) -> void:
	for frame: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png"))
