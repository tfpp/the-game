extends Node3D
## Actual prefab viewer, with painted/checker captures and individual inspection views.

const CRATE := preload("res://features/procedural_rooms/props/crate.tscn")
const BARREL := preload("res://features/procedural_rooms/props/barrel.tscn")
const CAR := preload("res://features/procedural_rooms/props/car.tscn")
const CAR_CHECKER := preload("res://assets/procedural_rooms/models/car/uv_checker.png")
const CHECKERS := {
	"Crate": preload("res://assets/procedural_rooms/models/crate/uv_checker.png"),
	"Barrel": preload("res://assets/procedural_rooms/models/barrel/uv_checker.png"),
	"Car": CAR_CHECKER,
	"Wheel": CAR_CHECKER
}
var _models: Array[Node3D] = []
var _camera: Camera3D
var _caption: Label


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202a32")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dce4ed")
	environment.environment.ambient_light_energy = .7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = .9
	add_child(sun)
	var scenes: Array[PackedScene] = [BARREL, CRATE, CAR]
	for index: int in scenes.size():
		var model := scenes[index].instantiate() as Node3D
		model.position.x = [-2.7, -1.3, 1.4][index]
		_models.append(model)
		add_child(model)
		for visual: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			visual.set_meta("painted", visual.material_override)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_gallery_camera()
	_camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.text = (
		"REUSABLE PROP KIT / BARREL + CRATE + CAR\n"
		+ "C: UV checker / T: painted / Arrow keys: rotate"
	)
	canvas.add_child(_caption)
	_capture.call_deferred()


func _gallery_camera() -> void:
	_camera.size = 5.8
	_camera.position = Vector3(7, 5, 8)
	_camera.look_at(Vector3(0, .7, 0))


func _paint(checker: bool) -> void:
	for model: Node3D in _models:
		for visual: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if not checker:
				visual.material_override = visual.get_meta("painted") as Material
				continue
			var material := StandardMaterial3D.new()
			material.albedo_texture = CHECKERS[
				"Wheel" if str(visual.name).begins_with("Wheel") else str(model.name)
			]
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			visual.material_override = material


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_C or event.keycode == KEY_T:
			_paint(event.keycode == KEY_C)
		if event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT:
			for model: Node3D in _models:
				model.rotation.y += PI / 8 if event.keycode == KEY_LEFT else -PI / 8


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	assert(DisplayServer.get_name() != "headless")
	get_tree().root.size = Vector2i(1200, 800)
	DirAccess.make_dir_recursive_absolute(args[0])
	await _save(args[0], "prop-kit", "REUSABLE PROPS / 128PX GOLDSRC TEXTURES / FITTED COLLISION")
	_paint(true)
	await _save(
		args[0],
		"prop-checkers",
		"UV CHECK / SHARED FACES / ROTATED PACKING / VISIBLE SURFACE BUDGETS"
	)
	_paint(false)
	for model: Node3D in _models:
		for other: Node3D in _models:
			other.visible = other == model
		_camera.size = 4.8 if model.name == &"Car" else 2.4
		_camera.position = model.position + Vector3(4, 3, -5)
		_camera.look_at(model.position + Vector3(0, .65, 0))
		await _save(
			args[0],
			str(model.name).to_lower(),
			str(model.name).to_upper() + " / REUSABLE STATIC PREFAB / 128PX ATLAS"
		)
	print("PROP_CAPTURE PASS")
	get_tree().quit()


func _save(folder: String, id: String, caption: String) -> void:
	_caption.text = caption
	await get_tree().create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	assert(get_tree().root.get_texture().get_image().save_png(folder.path_join(id + ".png")) == OK)
