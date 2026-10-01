extends SceneTree
## Render actual Godot prefabs from below, including a mixed ceiling and UV checker.

var scene := Node3D.new()
var camera := Camera3D.new()


func _initialize() -> void:
	root.add_child(scene)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("29262a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff0db")
	environment.ambient_light_energy = 0.5
	world.environment = environment
	scene.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(65, -30, 0)
	light.light_color = Color("ffe9c8")
	light.light_energy = 1.1
	scene.add_child(light)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	scene.add_child(camera)
	_capture.call_deferred()


func _capture() -> void:
	var tin := load("res://features/room_kits/tin_ceiling_tile.tscn") as PackedScene
	var plain := load("res://features/room_kits/basic_ceiling_tile.tscn") as PackedScene
	var pair := Node3D.new()
	scene.add_child(pair)
	var left := tin.instantiate() as MeshInstance3D
	left.position.x = -0.6
	pair.add_child(left)
	var right := plain.instantiate() as MeshInstance3D
	right.position.x = 0.6
	pair.add_child(right)
	camera.position = Vector3(0.6, -4, 2.8)
	camera.look_at(Vector3.ZERO)
	await _save("godot-pair")
	var checker := Image.create(128, 64, false, Image.FORMAT_RGB8)
	for y: int in 64:
		for x: int in 128:
			checker.set_pixel(
				x, y, Color("d0baa0") if (x / 4 + y / 4) % 2 == 0 else Color("564f60")
			)
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_texture = ImageTexture.create_from_image(checker)
	diagnostic.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	left.material_override = diagnostic
	right.material_override = diagnostic
	await _save("godot-checker")
	pair.queue_free()
	await process_frame
	var prefab := load("res://features/room_kits/mixed_ceiling_patch.tscn") as PackedScene
	var patch := prefab.instantiate() as Node3D
	scene.add_child(patch)
	camera.size = 5.8
	camera.position = Vector3(3, -6, 4)
	camera.look_at(Vector3.ZERO)
	await _save("godot-mixed")
	patch.position.y = 5
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 68
	camera.position = Vector3(0, 1.7, 1.2)
	camera.look_at(Vector3(0, 5, -0.2))
	await _save("godot-ceiling-height")
	quit()


func _save(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path(
		"res://../docs/design/previews/ceiling-tiles/" + label + ".png"
	)
	assert(root.get_texture().get_image().save_png(output) == OK)
	print("Saved ", label)
