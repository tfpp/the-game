extends SubViewportContainer
## A private, noninteractive driving vignette using the actual operations van.

var elapsed := 0.0
var _van: Node3D
var _marks: Array[MeshInstance3D] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202828")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c8d3c6")
	environment.environment.ambient_light_energy = .8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	world.add_child(light)
	_van = preload("res://features/starter_room/van_model.tscn").instantiate()
	_van.get_node("Collision").free()
	world.add_child(_van)
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 40)
	road.mesh = plane
	road.material_override = _paint(Color("303638"))
	world.add_child(road)
	for i: int in 14:
		var mark := MeshInstance3D.new()
		var stripe := PlaneMesh.new()
		stripe.size = Vector2(.12, 1.6)
		mark.mesh = stripe
		mark.material_override = _paint(Color("c9b788"))
		mark.position = Vector3(2.1, .015, i * 3 - 21)
		world.add_child(mark)
		_marks.append(mark)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(8, 4.5, 8)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.5
	camera.current = true


func start() -> void:
	elapsed = 0
	show()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	elapsed += delta
	_van.position.y = sin(elapsed * 13) * .035
	_van.rotation.z = sin(elapsed * 7) * .008
	for i: int in _marks.size():
		_marks[i].position.z = fposmod(i * 3 - elapsed * 8, 42) - 21


func _paint(color: Color) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.roughness = 1
	return paint
