extends Node3D
## Production metro preview. F1 platform, F2 ride, F3 elevator bank, F4 walk.

var metro: MetroService
var camera: Camera3D
var player: Player


func _ready() -> void:
	metro = (load("res://features/metro/feature.tscn") as PackedScene).instantiate() as MetroService
	add_child(metro)
	for index: int in 6:
		var access := MetroAccess.new()
		access.name = "Room%d" % index
		access.zone_id = "preview%d" % index
		access.label = [
			"Golden Crown",
			"Gaming Suites",
			"Grand Lounge",
			"Wine Cellar",
			"Backroom Book",
			"Mirror Club"
		][index]
		access.slot = index
		access.position = Vector3(index * 20, 0, 200)
		add_child(access)
	camera = Camera3D.new()
	camera.far = 200
	add_child(camera)
	player = (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	player.name = "1"
	player.position = MetroRules.station_position(0) + Vector3(4, 2.1244, 2.5)
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("161c1b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b7b6a1")
	world.environment.ambient_light_energy = 0.45
	add_child(world)
	_view(1)
	if "--capture-metro" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _view(which: int) -> void:
	Controls.pause()
	player.set_physics_process(false)
	player.set_process(false)
	metro.stations[0].load_room(60000)
	metro.rides[0].load_room(60000)
	if which == 2:
		camera.position = MetroRules.ride_position(0) + Vector3(0, 2.8, 8)
		camera.look_at(MetroRules.ride_position(0) + Vector3(0, 2.5, -8))
	elif which == 3:
		camera.position = MetroRules.station_position(0) + Vector3(8, 3.1, 10)
		camera.look_at(MetroRules.station_position(0) + Vector3(18, 2.8, -5))
	else:
		camera.position = MetroRules.station_position(0) + Vector3(8, 3.2, 58)
		camera.look_at(MetroRules.station_position(0) + Vector3(0, 2.3, 28))
	camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				_view(1)
			KEY_F2:
				_view(2)
			KEY_F3:
				_view(3)
			KEY_F4:
				Controls.start()
				player.set_physics_process(true)
				player.set_process(true)
				(player.get_node("Camera") as Camera3D).current = true
			KEY_ESCAPE:
				_view(1)


func _capture() -> void:
	metro.set_physics_process(false)
	metro.net_time = 5
	for view: int in [1, 2, 3]:
		_view(view)
		for frame: int in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/metro-view-%d.png" % view)
	get_tree().quit()
