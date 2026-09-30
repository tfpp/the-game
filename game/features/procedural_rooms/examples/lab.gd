extends Node3D
## Standalone first-person socket lab; never auto-loaded into the live casino.

const Layout := preload("res://features/procedural_rooms/example_layout.gd")
const PLAYER := preload("res://core/player/player.tscn")
const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const Shell := preload("res://features/procedural_rooms/shell_mesh.gd")
var player: Player
var examples: Node3D
var _hud: Label
var _prompt: Label


func _ready() -> void:
	examples = Layout.build(self)
	Showcase.decorate(examples)
	Showcase.gallery(examples)
	Shell.rebuild(examples)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202a35")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d8e6ee")
	environment.environment.ambient_light_energy = 0.75
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 0.8
	add_child(sun)
	player = PLAYER.instantiate() as Player
	player.position = Vector3(-20, 1.0, 3)
	player.yaw = PI
	add_child(player)
	Controls.apply_scheme(Controls.Scheme.RIGHT_HANDED)
	Controls.playing = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = Label.new()
	_hud.text = (
		"SOCKET LAB   |   1 Garage/ramp   2 Utility/stairs   3 Pump/sewer   4 Assembly gallery\n"
		+ "WASD / mouse / Space jump / E door / G socket guides / Esc release"
	)
	_hud.position = Vector2(22, 18)
	_hud.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_hud)
	_prompt = Label.new()
	_prompt.position = Vector2(22, 78)
	_prompt.add_theme_font_size_override("font_size", 22)
	canvas.add_child(_prompt)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_1, KEY_2, KEY_3]:
			player.position = Vector3((event.keycode - KEY_1 - 1) * 20, 1.0, 3)
			player.velocity = Vector3.ZERO
			player.yaw = PI
		if event.keycode == KEY_4:
			player.position = Vector3(-14, 1, -53)
			player.velocity = Vector3.ZERO
			player.yaw = PI
		if event.keycode == KEY_E and Controls.gameplay_active():
			var door := nearby_door()
			if door != null:
				door.use()
		if event.keycode == KEY_G:
			for guide: Node3D in get_tree().get_nodes_in_group(&"socket_displays"):
				guide.visible = not guide.visible
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Controls.playing = false
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Controls.playing = true


func nearby_door() -> ProceduralSlidingDoor:
	var nearest: ProceduralSlidingDoor
	var distance := 2.5
	for node: Node in get_tree().get_nodes_in_group(&"prototype_doors"):
		var door := node as ProceduralSlidingDoor
		var current := (door.global_position + Vector3.UP).distance_to(player.global_position)
		if current < distance:
			distance = current
			nearest = door
	return nearest


func _process(_delta: float) -> void:
	var door := nearby_door()
	_prompt.text = "" if door == null else "[E] " + ("Close" if door.net_open else "Open") + " door"
