extends SceneTree
## Render the actual prefab, including seams between neighbouring wall modules.

var scene := Node3D.new()
var camera := Camera3D.new()
var wall: MeshInstance3D


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
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_color = Color("ffe9d3")
	light.light_energy = 0.9
	scene.add_child(light)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.8
	scene.add_child(camera)
	_capture.call_deferred()


func _capture() -> void:
	var prefab := load("res://features/room_kits/beige_stucco_wall_full.tscn") as PackedScene
	wall = prefab.instantiate() as MeshInstance3D
	scene.add_child(wall)
	camera.position = Vector3(2, 4, 7)
	camera.look_at(Vector3(0, 2.5, 0))
	await _save("godot-front")
	camera.position = Vector3(-2, 4, -7)
	camera.look_at(Vector3(0, 2.5, 0))
	await _save("godot-back")
	var checker := Image.create(64, 128, false, Image.FORMAT_RGB8)
	for y: int in 128:
		for x: int in 64:
			checker.set_pixel(
				x, y, Color("d0baa0") if (x / 4 + y / 4) % 2 == 0 else Color("564f60")
			)
	var original := wall.material_override
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_texture = ImageTexture.create_from_image(checker)
	diagnostic.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	wall.material_override = diagnostic
	camera.position = Vector3(2, 4, 7)
	camera.look_at(Vector3(0, 2.5, 0))
	await _save("godot-checker")
	wall.material_override = original
	for x: float in [-1.0, 1.0]:
		var neighbour := prefab.instantiate() as Node3D
		neighbour.position.x = x
		scene.add_child(neighbour)
	camera.size = 8.2
	camera.position = Vector3(3, 4, 8)
	camera.look_at(Vector3(0, 2.5, 0))
	await _save("godot-modules")
	quit()


func _save(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path(
		"res://../docs/design/previews/beige-stucco-wall-full/" + label + ".png"
	)
	assert(root.get_texture().get_image().save_png(output) == OK)
	print("Saved ", label)
