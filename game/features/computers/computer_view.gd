extends Node3D
## A real 3D screen; the only overlay is Leave. No full-screen game replacement.

var computer: ArcadeComputer
var screen: MeshInstance3D
var display: Control
var viewport: SubViewport
var camera: Camera3D
var previous_camera: Camera3D
var leave: Button
var layer: CanvasLayer
var epoch := -1
var heartbeat := 0.0
var cursor := Vector2(160, 100)
var last_state: Dictionary = {}


func build(owner_node: ArcadeComputer) -> void:
	computer = owner_node
	_box(Vector3(0, 0.55, 0), Vector3(1.4, 1.1, 0.85), Color("182c36"))
	_box(Vector3(0, 1.65, 0), Vector3(1.5, 1.12, 0.9), Color("354b53"))
	_box(Vector3(0, 1.08, 0.35), Vector3(1.5, 0.12, 0.35), Color("b28142"))
	for x: float in [-0.58, 0.58]:
		_box(Vector3(x, 0.55, 0.435), Vector3(0.04, 0.9, 0.02), Color("50dccb"))
	for row: int in 3:
		_box(Vector3(0, 0.3 + row * 0.08, 0.436), Vector3(0.6, 0.03, 0.02), Color("080e15"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 400)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	display = preload("res://features/computers/turkey_screen.gd").new()
	display.size = Vector2(640, 400)
	viewport.add_child(display)
	screen = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = ScummArcadePointer.SIZE
	screen.mesh = quad
	screen.position = Vector3(0, 1.65, 0.46)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = material
	add_child(screen)
	var sign := Label3D.new()
	sign.text = "SUPER TURBO\nTURKEY PUNCHER 3"
	sign.position = Vector3(0, 2.32, 0.46)
	sign.font_size = 28
	sign.pixel_size = 0.003
	sign.modulate = Color("ffcc77")
	add_child(sign)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.65, 2.25)
	camera.fov = 55
	add_child(camera)
	layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	leave = Button.new()
	leave.text = "Leave computer"
	leave.custom_minimum_size = Vector2(210, 48)
	leave.hide()
	layer.add_child(leave)
	leave.pressed.connect(close)
	get_viewport().size_changed.connect(_layout)
	get_window().focus_exited.connect(_focus_lost)
	Controls.menu_requested.connect(_focus_lost)
	_layout()


func open(session: int) -> void:
	if epoch >= 0:
		return
	epoch = session
	previous_camera = get_viewport().get_camera_3d()
	camera.make_current()
	add_to_group(&"modal_ui")
	Controls.pause()
	leave.show()
	heartbeat = 0
	_layout()


func close(resume: bool = true) -> void:
	if epoch < 0:
		return
	computer.request_close.rpc_id(1, epoch)
	epoch = -1
	leave.hide()
	camera.clear_current()
	if is_instance_valid(previous_camera):
		previous_camera.make_current()
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _exit_tree() -> void:
	close(false)


func _focus_lost() -> void:
	close(false)


func _process(delta: float) -> void:
	if computer == null:
		return
	if last_state != computer.state:
		last_state = computer.state.duplicate()
		display.set_state(last_state)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if display.animate(delta):
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if epoch < 0:
		return
	var player := computer.player_for(multiplayer.get_unique_id())
	if player == null or player.global_position.distance_to(computer.global_position) > 4:
		close(false)
		return
	# An open acknowledgement can arrive before its synchronized state.
	if (
		int(computer.state.epoch) >= epoch
		and int(computer.state.owner) != multiplayer.get_unique_id()
	):
		close()
		return
	heartbeat -= delta
	if heartbeat <= 0:
		heartbeat = 1.5
		computer.keep_alive.rpc_id(1, epoch)
	if Controls.device == Controls.Device.GAMEPAD:
		cursor += Controls.stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y) * delta * 180
		cursor = cursor.clamp(Vector2.ZERO, Vector2(319, 199))
		display.set_cursor(cursor)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _input(event: InputEvent) -> void:
	if epoch < 0:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"release_mouse"):
		close(not OS.has_feature("web"))
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept"):
		computer.request_click.rpc_id(1, epoch, Vector2i(cursor))
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if epoch < 0:
		return
	var position_2d := Vector2.ZERO
	var click := false
	if event is InputEventMouse:
		position_2d = (event as InputEventMouse).position
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			click = button.pressed and button.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		position_2d = (event as InputEventScreenTouch).position
		click = (event as InputEventScreenTouch).pressed
	else:
		return
	var point := screen_point(position_2d)
	if point.x >= 0:
		cursor = Vector2(point)
		display.set_cursor(cursor)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if click:
			computer.request_click.rpc_id(1, epoch, point)
	get_viewport().set_input_as_handled()


func screen_point(at: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(at)
	var direction := camera.project_ray_normal(at)
	var point := ScummArcadePointer.project(screen.global_transform, origin, direction)
	var player := computer.player_for(multiplayer.get_unique_id())
	var exclusions: Array[RID] = []
	if player != null:
		exclusions.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 4, 1, exclusions)
	if get_world_3d().direct_space_state.intersect_ray(query).get("collider") != computer:
		return ScummArcadePointer.MISS
	return point


func _layout() -> void:
	var stretch := get_viewport().get_stretch_transform().get_scale().x
	layer.scale = Vector2.ONE * maxf(1, 1 / maxf(0.1, stretch))
	var available := get_viewport().get_visible_rect().size / layer.scale
	leave.size = leave.get_combined_minimum_size()
	leave.position = Vector2((available.x - leave.size.x) / 2, available.y - leave.size.y - 12)
	# Preserve the complete monitor on narrow portrait displays.
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 40 if available.x < available.y else 55


func _box(at: Vector3, dimensions: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	part.mesh = mesh
	part.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = preload("res://features/casino_hub/textures/prop_grain.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	part.material_override = material
	add_child(part)
