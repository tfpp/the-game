class_name InventoryPreview
extends SubViewportContainer

var model := BlockPlayerModel.new()
var viewport := SubViewport.new()


func _ready() -> void:
	custom_minimum_size = Vector2(210, 260)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.size = Vector2i(320, 360)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.size_changed.connect(_redraw)
	var world := Node3D.new()
	viewport.add_child(world)
	world.add_child(model)
	model.rotation.y = -0.3
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.35
	world.add_child(camera)
	camera.position = Vector3(0, 0.3, -4)
	camera.look_at(Vector3(0, 0.06, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -150, 0)
	light.light_energy = 1.5
	world.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7cde2")
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)


func show_clothing(shirt: String, pants: String, hat := "") -> void:
	model.set_clothing(shirt, pants)
	model.set_hat(hat)
	_redraw()


func _redraw() -> void:
	# The pose is static. Refresh after clothing or size changes without rendering
	# another 3D scene every frame while the player browses the backpack.
	viewport.render_target_update_mode = (
		SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	)
