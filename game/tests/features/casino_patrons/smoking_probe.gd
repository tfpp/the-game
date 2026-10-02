extends Node3D
## Render actual rigs and wisps: -- --smoking-capture=/tmp/smoking.png
## Add --smoking-seated, --smoking-back or --smoking-exhale.

const GUEST := preload("res://features/casino_patrons/stationary_guest.tscn")
const SEATED := preload("res://features/casino_patrons/stationary_lady.tscn")

var _model: SalonGuestModel
var _phase := 2.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seated := "--smoking-seated" in args
	var back := "--smoking-back" in args
	_phase = 3.8 if "--smoking-exhale" in args else 2.0
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(1.1, 1.4, -1.8 if back else 1.8)
	camera.look_at(Vector3(0, 1.2 if not seated else 0.9, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("262127")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d6c2a4")
	world.environment.ambient_light_energy = 0.6
	add_child(world)
	var npc := (SEATED if seated else GUEST).instantiate() as StationaryPatron
	_model = npc.get_node("Body") as SalonGuestModel
	_model.smoking = true
	add_child(npc)
	_model.set_process(false)
	for arg: String in args:
		if arg.begins_with("--smoking-capture="):
			await get_tree().create_timer(1.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.split("=", true, 1)[1])
			get_tree().quit()


func _process(delta: float) -> void:
	_model._time = _phase
	_model._update(delta)
