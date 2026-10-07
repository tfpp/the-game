extends Node3D
## Opt-in actual saved-level and modal captures; not a web performance benchmark.

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const FEATURE := preload("res://features/adventure_machine/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _machine: AdventureMachine
var _player: Player
var _camera: Camera3D
var _folder := "/tmp/adventure-machine"


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_folder = args[0]
	DirAccess.make_dir_recursive_absolute(_folder)
	get_window().size = Vector2i(960, 640)
	add_child(ROOM.instantiate())
	_machine = FEATURE.instantiate() as AdventureMachine
	add_child(_machine)
	_player = PLAYER.instantiate() as Player
	_player.get_node("Sync").free()
	_player.position = _machine.position + Vector3(0, 1, 1.6)
	add_child(_player)
	_player.set_physics_process(false)
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	_camera.position = _machine.position + Vector3(.9, 1.45, 2)
	_camera.look_at(_machine.position + Vector3(0, .85, 0))
	await _save("cabinet")
	_camera.position = Vector3(11, 1.6, -14)
	_camera.look_at(_machine.position + Vector3(0, .9, 0))
	await _save("promenade")
	_camera.position = _machine.position + Vector3(0, 1.65, 1.6)
	_camera.look_at(_machine.position + Vector3(0, 1.17, .22))
	await get_tree().physics_frame
	_machine.use()
	assert(_machine._screen != null and _machine._screen.is_open())
	await _save("desktop")
	get_window().size = Vector2i(390, 844)
	await _save("phone")
	get_window().size = Vector2i(844, 390)
	await _save("landscape")
	_machine._screen.close(false)
	get_window().size = Vector2i(390, 844)
	for id: String in ["go_tavern", "learn", "go_quay", "go_fort", "challenge"]:
		_machine._next_action.clear()
		_machine.request_choice(id, _machine._stories[1].revision)
	_machine.use()
	await _save("duel-phone")
	get_tree().quit()


func _save(title: String) -> void:
	for frame: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_folder.path_join(title + ".png"))
