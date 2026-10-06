extends SceneTree
## Renders the actual exported GLB. No gameplay or map dependency.

const SOURCE := "res://../docs/design/model-sources/r44-metro"
const OUT := "res://../docs/design/previews/r44-metro"
var world: Node3D
var camera: Camera3D
var model: Node3D
var caption: Label


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1600, 1000)
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("1e282e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c1cbd2")
	environment.environment.ambient_light_energy = 0.75
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -32, 0)
	light.light_energy = 1.1
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(28, 110, 0)
	fill.light_energy = 0.4
	world.add_child(fill)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file("res://assets/metro/models/r44_five_car_set.glb", state) == OK)
	model = document.generate_scene(state)
	world.add_child(model)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.far = 400
	caption = Label.new()
	caption.position = Vector2(34, 30)
	caption.add_theme_font_size_override("font_size", 23)
	caption.add_theme_color_override("font_color", Color("e1dac5"))
	root.add_child(caption)
	await capture(
		"01-five-car-set",
		Vector3(67, 49, 77),
		Vector3(0, 1.5, 0),
		87,
		(
			"R44 / FIVE-CAR SET    |    CASINO ROYALE\n"
			+ "Exterior asset • low-poly steel • 128px painted atlases"
		)
	)
	await capture(
		"02-cab-and-graffiti",
		Vector3(14, 7, 65),
		Vector3(0, 1.7, 48),
		21,
		"R44 / CAB + BODY\nFaceted roof • four paired doors per side • separate trucks and door leaves"
	)
	await capture(
		"03-side",
		Vector3(32, 5, 45.72),
		Vector3(0, 1.8, 45.72),
		16,
		"R44 / SIDE PROFILE\n22.86 m car pitch • original weathered graffiti"
	)
	await capture(
		"04-rear",
		Vector3(-10, 6, -65),
		Vector3(0, 1.8, -48),
		18,
		"R44 / REAR CAB\nOpposing cab ends • five independently addressable cars"
	)
	await capture(
		"05-coupling",
		Vector3(7, 2.1, 33.3),
		Vector3(0, 1.4, 34.29),
		5,
		"R44 / INTER-CAR JOIN\nCoupler markers • end hardware • no open gangway"
	)
	await capture(
		"06-underbody",
		Vector3(8, -3, 53),
		Vector3(0, 0.65, 50),
		9,
		"R44 / TRUCK + UNDERBODY\nFaceted wheelsets • axles • attached equipment"
	)
	await capture(
		"07-front",
		Vector3(0, 2.5, 65),
		Vector3(0, 2.0, 56.8),
		5,
		"R44 / CAB FACE\nPaired lamps • rollsign • windowed end door • safety rails"
	)
	var doors := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(doors != null)
	print("Exported animations: ", doors.get_animation_list())
	doors.play("open_all")
	doors.seek(1.2, true)
	doors.pause()
	await capture(
		"09-open-doors",
		Vector3(9, 3.8, 55),
		Vector3(0, 2.0, 49),
		10,
		"R44 / BOARDING DOORS OPEN\nSliding pockets • moving collision • clear passenger entrance"
	)
	await capture(
		"10-interior",
		Vector3(0, 2.825, 55.2),
		Vector3(0, 2.5, 39),
		-1,
		(
			"R44 / PASSENGER CABIN\nMolded seats • wood-look lining"
			+ " • stainless grab rails • fluorescent lighting"
		)
	)
	await capture(
		"11-vestibule",
		Vector3(0, 2.825, 49.5),
		Vector3(1.4, 2.15, 48.22),
		-1,
		"R44 / VESTIBULE\nDoors retract between the exterior skin and interior lining"
	)
	doors.play("close_all")
	doors.seek(0.6, true)
	doors.pause()
	await capture(
		"12-half-open",
		Vector3(6, 2.5, 48.22),
		Vector3(0, 2.15, 48.22),
		4,
		"R44 / DOOR TRAVEL\nHalfway through the 1.2 second animation"
	)
	var checker := StandardMaterial3D.new()
	checker.albedo_texture = ImageTexture.create_from_image(
		Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "/checker.png"))
	)
	checker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	for mesh: Node in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = checker
	await capture(
		"08-checker",
		Vector3(14, 7, 65),
		Vector3(0, 1.7, 48),
		21,
		"R44 / EXPORTED MESH UV CHECK\nStacked material charts • explicit UV1 • two-pixel gutters"
	)
	print("R44_PREVIEW PASS")
	quit()


func capture(id: String, position: Vector3, target: Vector3, size: float, text: String) -> void:
	camera.projection = (
		Camera3D.PROJECTION_PERSPECTIVE if size < 0 else Camera3D.PROJECTION_ORTHOGONAL
	)
	camera.position = position
	camera.look_at(target)
	camera.size = maxf(size, 1)
	caption.text = text
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	assert(
		(
			root.get_texture().get_image().save_png(
				ProjectSettings.globalize_path(OUT + "/" + id + ".png")
			)
			== OK
		)
	)
