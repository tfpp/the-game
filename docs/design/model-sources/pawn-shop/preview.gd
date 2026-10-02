extends SceneTree
## Review the actual exported GLBs, including reverse and underside construction.

var _camera: Camera3D
var _output := "/tmp/pawn-furniture-review"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_output)
	root.size = Vector2i(960, 720)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.09, .11, .13)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.4
	root.add_child(light)
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.current = true
	for asset: String in ["display_case", "shop_shelves"]:
		var path := ProjectSettings.globalize_path(
			"res://../docs/design/model-sources/pawn-shop/" + asset + ".glb"
		)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(path, state) == OK)
		var model := document.generate_scene(state)
		root.add_child(model)
		var aim := Vector3(0, .7 if asset == "display_case" else 1.3, 0)
		_camera.position = Vector3(3, 2.6, 4)
		_camera.look_at(aim)
		await _save(asset + "-front")
		_camera.position = Vector3(-3, 2.6, -4)
		_camera.look_at(aim)
		await _save(asset + "-rear")
		_camera.position = Vector3(2, -1.7, 3)
		_camera.look_at(aim)
		await _save(asset + "-underside")
		model.queue_free()
		await process_frame
	quit()


func _save(label: String) -> void:
	for frame: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output.path_join(label + ".png"))
