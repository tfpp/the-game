extends Node3D
## Inspect a saved scene: godot --path game res://features/world_builder/preview.tscn -- SCENE
## Hold right mouse to look, WASD to fly, Q/E to descend/ascend, Shift to move faster.

@export var sky_panorama: Texture2D = preload("res://assets/kenney/skyboxes/skybox-day.png")
@export_range(-180.0, 180.0) var sky_rotation_degrees := 0.0

var _camera: Camera3D
var _dragging := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not ResourceLoader.exists(args[0], "PackedScene"):
		printerr("WORLD_PREVIEW: pass a generated .tscn or .scn after --")
		get_tree().quit(1)
		return
	var scene := (load(args[0]) as PackedScene).instantiate() as Node3D
	add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = sky_panorama
	var sky := Sky.new()
	sky.sky_material = panorama
	environment.environment.background_mode = Environment.BG_SKY
	environment.environment.sky = sky
	environment.environment.sky_rotation.y = deg_to_rad(sky_rotation_degrees)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = (
		0.5 if scene.get_meta("theme", "prototype") == "hotel" else 2.0
	)
	add_child(environment)
	_camera = Camera3D.new()
	add_child(_camera)
	var rooms := scene.get_node_or_null("Rooms")
	var center := Vector3.ZERO
	if rooms != null and rooms.get_child_count() > 0:
		center = (rooms.get_child(0) as Node3D).global_position
	_camera.position = center + Vector3(0, 1.7, 0)
	_camera.current = true
	var light := OmniLight3D.new()
	light.omni_range = 25
	light.light_energy = 0.2 if scene.get_meta("theme", "prototype") == "hotel" else 4.0
	if scene.has_meta("baked_lighting"):
		light.light_energy = 0.0
	_camera.add_child(light)
	var label := Label.new()
	label.text = (
		"WORLD BUILDER  |  Hold right mouse + WASD to fly"
		+ "  |  Q/E down/up  |  Shift fast  |  Esc release"
	)
	label.position = Vector2(16, 16)
	add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_dragging = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _dragging else Input.MOUSE_MODE_VISIBLE
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		_dragging = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and _dragging and _camera != null:
		_camera.rotation.y -= event.relative.x * 0.003
		_camera.rotation.x = clampf(_camera.rotation.x - event.relative.y * 0.003, -1.5, 1.5)


func _process(delta: float) -> void:
	if _camera == null or not _dragging:
		return
	var direction := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	var speed := 20.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0
	_camera.position += _camera.basis * direction.normalized() * speed * delta
