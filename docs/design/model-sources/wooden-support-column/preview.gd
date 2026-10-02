extends SceneTree
## Actual Godot Compatibility renderer review: solo, reverse, stacked and UV checker.

var scene := Node3D.new()
var camera := Camera3D.new()
var material: StandardMaterial3D


func _initialize() -> void:
	root.size = Vector2i(900, 900)
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("29262a")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("fff0d5")
	settings.ambient_light_energy = 0.55
	environment.environment = settings
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -40, 0)
	light.light_color = Color("ffe4ba")
	light.light_energy = 1.3
	scene.add_child(light)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.4
	scene.add_child(camera)
	_capture.call_deferred()


func _capture() -> void:
	var prefab := load("res://features/room_kits/wooden_support_column.tscn") as PackedScene
	var column := prefab.instantiate() as Node3D
	scene.add_child(column)
	material = (column.get_node("Column") as MeshInstance3D).material_override.duplicate()
	(column.get_node("Column") as MeshInstance3D).material_override = material
	camera.position = Vector3(7, 5.0, 10)
	camera.look_at(Vector3(0, 2.5, 0))
	await _save("godot-solo")
	camera.position = Vector3(-7, 4, -10)
	camera.look_at(Vector3(0, 2.5, 0))
	await _save("godot-reverse")
	var upper := prefab.instantiate() as Node3D
	upper.position.y = 5.0
	scene.add_child(upper)
	camera.size = 11.4
	camera.position = Vector3(9, 7.8, 12)
	camera.look_at(Vector3(0, 5, 0))
	await _save("godot-stacked")
	upper.queue_free()
	await process_frame
	var checker := Image.create(32, 128, false, Image.FORMAT_RGB8)
	for y: int in 128:
		for x: int in 32:
			var bright := (x / 4 + y / 4) % 2 == 0
			checker.set_pixel(x, y, Color("d0baa0") if bright else Color("564f60"))
	material.albedo_texture = ImageTexture.create_from_image(checker)
	camera.size = 6.4
	camera.position = Vector3(7, 5.0, 10)
	camera.look_at(Vector3(0, 2.5, 0))
	await _save("godot-checker")
	quit()


func _save(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path(
		"res://../docs/design/previews/wooden-support-column/" + label + ".png"
	)
	assert(root.get_texture().get_image().save_png(output) == OK)
	print("Saved ", label)
