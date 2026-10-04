extends Node
## Render the actual shop fixtures for plaque size and attachment review.

const SCENES: Array[String] = [
	"res://features/food_court/wendys_stand.tscn",
	"res://features/food_court/poke_stand.tscn",
	"res://features/kebab_shop/shop_view.tscn",
	"res://features/gun_machine/kiosk.tscn",
	"res://features/slot_machine/machine.tscn",
]


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world := Node3D.new()
	add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("25232b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	get_tree().root.size = Vector2i(960, 720)
	var output := ProjectSettings.globalize_path("res://../docs/design/previews/phase-one-signs")
	DirAccess.make_dir_recursive_absolute(output)
	for index: int in SCENES.size():
		var fixture := (load(SCENES[index]) as PackedScene).instantiate() as Node3D
		world.add_child(fixture)
		camera.position = Vector3(1.1, 1.9, 5.5 if index < 3 else 3.9)
		camera.look_at(Vector3(0, 1.45, 0))
		for frame: int in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("shop-%d.png" % index))
		world.remove_child(fixture)
		fixture.queue_free()
	get_tree().quit()
