extends Node3D
## Standalone inspection using the game's existing player and movement controller.

const PLAYER := preload("res://core/player/player.tscn")
var _player: Player
var _camera: Camera3D
var _caption: Label


func _ready() -> void:
	# Keep the layout visible from the review camera; the live room keeps its roof.
	for name: String in ["Ceiling", "PawnRoof", "FoodRoof", "CorridorRoof"]:
		($Casino.get_node(name) as Node3D).visible = false
	_camera = $Casino/Overview as Camera3D
	_player = PLAYER.instantiate() as Player
	_player.position = ($Casino/Spawn as Marker3D).position
	add_child(_player)
	_overview()
	Controls.menu_requested.connect(_overview)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 20)
	_caption.text = (
		"Golden Crown / GridMap layout preview\n"
		+ "F1: overview / F2 or click: walk / Esc: release mouse\n"
		+ "Arrow keys: move / Shift: jump / Controller: left stick + A\n"
		+ "Gaming pit: -1.5 m / Surrounding floor: 0 m"
	)
	canvas.add_child(_caption)
	_capture.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		_overview()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_overview()
	elif (
		(event is InputEventKey and event.pressed and event.keycode == KEY_F2)
		or (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		)
	):
		_player.set_physics_process(true)
		_player.set_process(true)
		(_player.get_node("Camera") as Camera3D).current = true
		Controls.start()


func _overview() -> void:
	Controls.pause()
	_player.set_physics_process(false)
	_player.set_process(false)
	_camera.current = true


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	get_tree().root.size = Vector2i(1400, 1000)
	DirAccess.make_dir_recursive_absolute(args[0])
	_caption.visible = false
	await _save(args[0], "overview")
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.position = Vector3(16, 5, 18)
	_camera.look_at(Vector3(0, -0.8, 0))
	await _save(args[0], "gaming-pit")
	_camera.position = Vector3(4, 1.8, 15)
	_camera.look_at(Vector3(0, -0.7, 8))
	await _save(args[0], "ramp")
	_camera.position = Vector3(1.5, 1.65, -16)
	_camera.look_at(Vector3(0, 1.2, -20))
	await _save(args[0], "wood-walls")
	print("CASINO_GRIDMAP_CAPTURE: actual saved GridMaps rendered")
	get_tree().quit()


func _save(folder: String, label: String) -> void:
	for frame: int in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(folder.path_join(label + ".png")) == OK)
