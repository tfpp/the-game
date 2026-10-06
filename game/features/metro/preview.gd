extends Node3D
## Local art-review scene. Uses the existing player; does not register a metro system.

const PLAYER := preload("res://core/player/player.tscn")
const TRAIN := preload("res://features/metro/r44_five_car_set.tscn")
const TILES := preload("res://features/metro/cabin_tiles.tres")
var _player: Player
var _camera: Camera3D
var _doors: AnimationPlayer
var _left_open := false
var _right_open := false


func _ready() -> void:
	var train := TRAIN.instantiate() as Node3D
	add_child(train)
	_doors = train.get_node("Doors") as AnimationPlayer
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("263038")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b8c3c9")
	environment.environment.ambient_light_energy = 0.55
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	add_child(light)
	# Review platforms share the cabin floor tile and align with its boarding height.
	for side: int in [-1, 1]:
		var platform := GridMap.new()
		platform.mesh_library = TILES
		platform.cell_size = Vector3(3.04, 1, 2)
		platform.cell_center_x = false
		platform.cell_center_y = false
		platform.cell_center_z = false
		platform.position = Vector3(side * 3.04, 0, 45.72)
		for z: int in range(-5, 6):
			platform.set_cell_item(Vector3i(0, 0, z), 0)
		add_child(platform)
	_camera = Camera3D.new()
	_camera.far = 400
	add_child(_camera)
	_player = PLAYER.instantiate() as Player
	_player.position = Vector3(0, 2.13, 53.22)
	add_child(_player)
	_overview()
	Controls.menu_requested.connect(_overview)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var caption := Label.new()
	caption.position = Vector2(24, 20)
	caption.add_theme_font_size_override("font_size", 20)
	caption.text = (
		"R44 / FIVE-CAR ASSET PREVIEW\n"
		+ "F1: exterior / F2: walk inside / Esc: release mouse\n"
		+ "L: toggle left doors / R: toggle right doors / O: open all / C: close all\n"
		+ "Arrow keys: move / Shift: jump"
	)
	canvas.add_child(caption)


func _overview() -> void:
	Controls.pause()
	_player.set_physics_process(false)
	_player.set_process(false)
	_camera.position = Vector3(17, 9, 68)
	_camera.look_at(Vector3(0, 1.7, 46))
	_camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		_overview()
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1:
			_overview()
		KEY_F2:
			_player.set_physics_process(true)
			_player.set_process(true)
			(_player.get_node("Camera") as Camera3D).current = true
			Controls.start()
		KEY_L, KEY_R, KEY_O, KEY_C:
			if _doors.is_playing():
				return
			if event.keycode == KEY_L:
				_left_open = not _left_open
				_doors.play("open_left" if _left_open else "close_left")
			elif event.keycode == KEY_R:
				_right_open = not _right_open
				_doors.play("open_right" if _right_open else "close_right")
			else:
				# Queue only the side that needs movement, avoiding a reset of an open side.
				var opening: bool = event.keycode == KEY_O
				if _left_open != opening and _right_open != opening:
					_doors.play("open_all" if opening else "close_all")
				elif _left_open != opening:
					_doors.play("open_left" if opening else "close_left")
				elif _right_open != opening:
					_doors.play("open_right" if opening else "close_right")
				_left_open = opening
				_right_open = opening
