extends SceneTree
## Fixed-step presentation demo. Preview outcomes do not debit a player's wallet.

var _machine: Node3D
var _elapsed := 0.0
var _started := false


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	root.size = Vector2i(1280, 720)
	var audio: Node = (load("res://features/game_audio/game_audio.gd") as GDScript).new()
	root.add_child(audio)
	var stage := Node3D.new()
	root.add_child(stage)
	_machine = (load("res://features/slot_machine/machine.tscn") as PackedScene).instantiate()
	stage.add_child(_machine)
	_machine.set_process(false)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(3, 2.4, 6)
	camera.look_at(Vector3(0, 1.55, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.8
	camera.current = true
	var listener := AudioListener3D.new()
	stage.add_child(listener)
	listener.position = Vector3(0, 1.65, 2)
	listener.make_current()
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("181e20")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("dcc6a1")
	world.environment.ambient_light_energy = .45
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = .7
	stage.add_child(light)


func _process(delta: float) -> bool:
	if _machine == null:
		return false
	_elapsed += delta
	if _elapsed >= .7 and not _started:
		_started = true
		var reels: Array[int] = [0, 0, 0]
		_machine._begin_spin(1, "Preview", reels, 3000)
	if _started:
		_machine._advance(delta)
	return false
