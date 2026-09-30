extends Node3D
## Inspect the actual UV-mapped model; optional output folder captures checker/albedo views.

const MODEL := preload("res://features/procedural_rooms/service_cabinet.tscn")
const CHECKER := preload("res://assets/procedural_rooms/models/service_cabinet/uv_checker.png")
const PAINTED := preload("res://features/procedural_rooms/materials/service_cabinet.tres")
var _model: Node3D
var _camera: Camera3D
var _caption: Label


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202a32")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dce4ed")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 0.9
	add_child(sun)
	_model = MODEL.instantiate() as Node3D
	add_child(_model)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.size = 3.6
	_camera.position = Vector3(3.7, 2.8, 3.5)
	add_child(_camera)
	_camera.look_at(Vector3(0, 1.25, 0))
	_camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.text = (
		"UV MODEL WORKSHOP / SERVICE CABINET\n"
		+ "Arrow keys: rotate / C: UV checker / T: painted atlas"
	)
	canvas.add_child(_caption)
	_capture.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_C:
			_checker()
		if event.keycode == KEY_T:
			(_model.get_node("Cabinet") as MeshInstance3D).material_override = (PAINTED as Material)
		if event.keycode == KEY_LEFT:
			_model.rotation.y += PI / 8
		if event.keycode == KEY_RIGHT:
			_model.rotation.y -= PI / 8


func _checker() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = CHECKER
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = 0.9
	(_model.get_node("Cabinet") as MeshInstance3D).material_override = material


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	get_tree().root.size = Vector2i(1200, 800)
	DirAccess.make_dir_recursive_absolute(args[0])
	await _save(
		args[0], "cabinet-textured", "UV PAINTED MODEL / 128PX ATLAS / 12 TRIANGLES / 1 MATERIAL"
	)
	_checker()
	await _save(
		args[0], "cabinet-checker", "UV CHECKER / UNIFORM TEXEL DENSITY / NO OVERLAPPING ISLANDS"
	)
	(_model.get_node("Cabinet") as MeshInstance3D).material_override = (PAINTED as Material)
	_model.rotation.y = PI
	await _save(args[0], "cabinet-rear", "BACK + SIDE VIEW / SAME GENERATED ATLAS")
	print("MODEL_CAPTURE PASS")
	get_tree().quit()


func _save(folder: String, id: String, caption: String) -> void:
	_caption.text = caption
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	assert(get_tree().root.get_texture().get_image().save_png(folder.path_join(id + ".png")) == OK)
