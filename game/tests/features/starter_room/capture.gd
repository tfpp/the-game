extends Node
## Actual Compatibility-renderer review. Run with a display, not --headless.

const FEATURE := preload("res://features/starter_room/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _output := "/tmp/operations-garage"
var _camera: Camera3D
var _van: OperationsVan
@onready var root: Window = get_tree().root


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		_output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_output)
	ThemeDB.fallback_font = preload("res://assets/fonts/inter/Inter-Regular.ttf")
	root.size = Vector2i(960, 540)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("252b30")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("9baca6")
	environment.environment.ambient_light_energy = .65
	world.add_child(environment)
	var garage := preload("res://features/procedural_rooms/prototype.tscn").instantiate() as Node3D
	garage.name = "procedural_rooms"
	world.add_child(garage)
	var street := preload("res://features/street_district/feature.tscn").instantiate() as Node3D
	street.name = "street_district"
	world.add_child(street)
	var shop := preload("res://features/pawn_shop/feature.tscn").instantiate() as Node3D
	shop.name = "pawn_shop"
	world.add_child(shop)
	var mall := preload("res://features/strip_mall/feature.tscn").instantiate() as Node3D
	mall.name = "strip_mall"
	world.add_child(mall)
	var feature := FEATURE.instantiate() as Node3D
	feature.name = "starter_room"
	world.add_child(feature)
	var room := feature.get_node("Room") as StreamedRoom
	room.load_room(60000)
	_van = room.get_node("Van")
	var player := PLAYER.instantiate() as Player
	player.position = _van.to_global(Vector3(-1.6, 1, 1))
	player.net_position = player.position
	world.add_child(player)
	player.set_physics_process(false)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.current = true
	_camera.position = room.to_global(Vector3(-2, 1.65, 4))
	_camera.look_at(_van.global_position + Vector3.UP)
	await _save("garage-arrival")
	_camera.position = _van.to_global(Vector3(-3.5, 2.8, -4))
	_camera.look_at(_van.global_position + Vector3.UP)
	await _save("van-rear")
	_camera.position = _van.to_global(Vector3(-3, .15, 4))
	_camera.look_at(_van.global_position + Vector3(0, .4, 0))
	await _save("van-underside")
	_van.panel.open_map(_van)
	await _save("route-map")
	root.size = Vector2i(390, 844)
	await _save("route-map-phone")
	root.size = Vector2i(844, 390)
	await _save("route-map-landscape")
	_van.panel.depart(_van, 0, _van.arrival(0).global_position)
	_van.panel.set_process(false)
	await _save("driving-transition")
	_van.panel.close(false)
	root.size = Vector2i(960, 540)
	_camera.position = room.to_global(Vector3(-2, 1.65, 2))
	_camera.look_at(room.to_global(Vector3(-6, 2, -4)))
	await _save("upstairs-stairs")
	_camera.position = room.to_global(Vector3(-7.5, .6, -.5))
	_camera.look_at(room.to_global(Vector3(-6, 1.5, -2.2)))
	await _save("stair-guard-underside")
	_camera.position = room.to_global(Vector3(-4, 3.5, -5.2))
	_camera.look_at(room.to_global(Vector3(-2, 3.1, -6)))
	await _save("mezzanine-guard")
	for board: String in ["WorldMap", "CasinoBlueprints"]:
		var at := (room.get_node("Content/" + board) as Node3D).global_position
		_camera.position = at + Vector3(-2.8, 0, 0)
		_camera.look_at(at)
		await _save(board.to_snake_case())
	_camera.position = room.to_global(Vector3(3.8, 1.65, 4.8))
	_camera.look_at(room.to_global(Vector3(7.9, 2.4, 4.8)))
	await _save("planning-wall-in-room")
	_camera.position = room.to_global(Vector3(-5.8, 4.1, -5.2))
	_camera.look_at(room.to_global(Vector3(-4, 3.55, -7.8)))
	await _save("upstairs-crt")
	var computer := room.get_node("JobTerminal") as GarageJobTerminal
	player.net_position = computer.to_global(Vector3(0, 0, .8))
	computer.panel.open(computer)
	await _save("crown-desktop")
	computer.panel.desktop._start.show_popup()
	await _save("start-menu")
	computer.panel.desktop._start.get_popup().hide()
	computer.panel.desktop.launch_app("Jobs")
	await _save("jobs-application")
	root.size = Vector2i(1200, 800)
	computer.panel.desktop.launch_app("Notes")
	computer.panel.desktop._filename.text = "Van plan"
	computer.panel.desktop._editor.text = "Meet upstairs, then take the van."
	computer.panel.desktop._save_note()
	computer.panel.desktop.launch_app("Calculator")
	await _save("multitasking")
	computer.panel.desktop.minimize()
	computer.panel.desktop.launch_app("Jobs")
	root.size = Vector2i(390, 844)
	await _save("jobs-phone")
	computer.panel.desktop.launch_app("Notes")
	computer.panel.desktop._filename.text = "Van plan"
	computer.panel.desktop._editor.text = "Meet upstairs, then take the van."
	computer.panel.desktop._save_note()
	await _save("notes-phone")
	computer.panel.desktop._editor.text += " Unsaved edit."
	computer.panel.desktop._editor.text_changed.emit()
	computer.panel.desktop._new_note()
	await _save("notes-discard-phone")
	computer.panel.desktop._discard_dialog.canceled.emit()
	computer.panel.desktop.launch_app("Files")
	await _save("files-phone")
	root.size = Vector2i(844, 390)
	computer.panel.desktop.launch_app("Calculator")
	await _save("calculator-landscape")
	computer.panel.close(false)
	root.size = Vector2i(390, 844)
	computer._store(1, {"job": 0, "ready": true, "done": [], "xp": 0})
	computer.panel._update()
	await _save("jobs-pin-phone")
	get_tree().quit()


func _save(title: String) -> void:
	for i: int in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output.path_join(title + ".png"))
