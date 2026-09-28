class_name ScummArcadeView
extends Node3D
## Cabinet geometry and the in-world play/watch controls. Only the cabinet owns networking.

const GOLD := Color("e9b94d")

var _cabinet: ScummArcadeCabinet
var _screen_material: StandardMaterial3D
var _layer: CanvasLayer
var _panel: Button
var _world_screen: MeshInstance3D
var _player: Player
var _play_camera: Camera3D
var _previous_fov := 73.74
var _look_drag := false
var _held_buttons: Array[int] = []
var _claim_in := 0.0
var _heartbeat := 0.0
var _motion_in := 0.0
var _point := Vector2i(160, 100)
var _sign: Label3D


func build(cabinet: ScummArcadeCabinet) -> void:
	_cabinet = cabinet
	var model := preload("res://features/scumm_arcade/model/cabinet.glb").instantiate()
	add_child(model)
	_style_model(model)
	_label(str(_cabinet.details()["kicker"]), Vector3(0, 2.475, 0.603), 18, GOLD)
	_label(str(_cabinet.details()["marquee"]), Vector3(0, 2.391, 0.604), 60, Color("fbe5ad"))
	_label(str(_cabinet.details()["subtitle"]), Vector3(0, 2.308, 0.604), 15, GOLD)
	_screen_material = StandardMaterial3D.new()
	_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_material.albedo_color = Color("152339")
	_screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var quad := QuadMesh.new()
	quad.size = Vector2(1.18, 0.885)
	_world_screen = MeshInstance3D.new()
	_world_screen.mesh = quad
	_world_screen.material_override = _screen_material
	_world_screen.position = Vector3(0, 1.774, 0.493)
	_world_screen.rotation.x = deg_to_rad(-16)
	add_child(_world_screen)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.8, 1.05)
	light.light_color = Color("99d6df")
	light.light_energy = 0.35
	light.omni_range = 2.0
	add_child(light)
	_label(
		"FREE PLAY" if _cabinet.is_interactive() else "DISPLAY DEMO",
		Vector3(0, 0.837, 0.477),
		22,
		GOLD
	)
	_label("TAKE A TURN · SHARE THE ADVENTURE", Vector3(0, 0.760, 0.468), 10, Color("b8c8c4"))
	_sign = _label(str(_cabinet.details()["marquee"]), Vector3(0, 1.778, 0.508), 28, GOLD)
	_sign.rotation.x = deg_to_rad(-16)
	_build_panel()
	get_window().focus_exited.connect(_focus_lost)


func set_screen(texture: Texture2D) -> void:
	_screen_material.albedo_color = Color.WHITE
	_screen_material.albedo_texture = texture
	_sign.hide()


func open() -> void:
	if _panel.visible:
		return
	_play_camera = get_viewport().get_camera_3d()
	if _play_camera != null:
		_previous_fov = _play_camera.fov
		_play_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_previous_fov) / 2.0) / 1.7))
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	add_to_group(&"modal_ui")
	_panel.show()
	_layout_panel.call_deferred()
	Controls.pause()
	_claim_in = 0.0
	if not _cabinet.local_error.is_empty():
		_cabinet.retry_local()


func close(resume: bool = true) -> void:
	if _panel == null or not _panel.visible:
		return
	_release_buttons()
	_look_drag = false
	# Also cancel a claim whose ownership update has not reached this peer yet.
	_cabinet.request_release.rpc_id(1)
	_panel.hide()
	if is_instance_valid(_play_camera):
		_play_camera.fov = _previous_fov
	_play_camera = null
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _focus_lost() -> void:
	close(false)


func _process(delta: float) -> void:
	_motion_in -= delta
	if _cabinet == null or _panel == null or not _panel.visible:
		return
	var owns := _cabinet.controls_local()
	_panel.text = "Release controls & leave" if owns else "Leave"
	_claim_in -= delta
	if not owns and int(_cabinet.state["owner"]) == 0 and _claim_in <= 0:
		_claim_in = 1.0
		if (
			_cabinet.is_interactive()
			and _cabinet.local_tick > 0
			and int(_cabinet.state["tick"]) - _cabinet.local_tick <= 25
			and _cabinet.local_error.is_empty()
			and str(_cabinet.state.get("error", "")).is_empty()
		):
			_cabinet.request_control.rpc_id(1)
	_heartbeat -= delta
	if owns and _heartbeat <= 0:
		_heartbeat = 2.0
		_cabinet.keep_control.rpc_id(1)


func _input(event: InputEvent) -> void:
	if _panel == null or not _panel.visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close(not OS.has_feature("web"))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index in _held_buttons:
			_cabinet.send_input(
				[2 if button.button_index == MOUSE_BUTTON_LEFT else 4, _point.x, _point.y, 0]
			)
			_held_buttons.erase(button.button_index)
		if button.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
			_look_drag = false
	elif event is InputEventMouseMotion and _look_drag:
		if is_instance_valid(_player):
			var motion := event as InputEventMouseMotion
			_player.yaw -= motion.screen_relative.x * Controls.look_radians_per_count()
			_player.pitch = clampf(
				_player.pitch - motion.screen_relative.y * Controls.look_radians_per_count(),
				deg_to_rad(-89),
				deg_to_rad(89)
			)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.echo and key.keycode in [KEY_PERIOD, KEY_ENTER]:
			_cabinet.send_input(
				[
					5 if key.pressed else 6,
					_point.x,
					_point.y,
					13 if key.keycode == KEY_ENTER else 46
				]
			)
		get_viewport().set_input_as_handled()


func _release_buttons() -> void:
	for button: int in _held_buttons:
		_cabinet.send_input([2 if button == MOUSE_BUTTON_LEFT else 4, _point.x, _point.y, 0])
	_held_buttons.clear()


func _unhandled_input(event: InputEvent) -> void:
	if _panel == null or not _panel.visible:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_MIDDLE:
			_release_buttons()
			_look_drag = true
			get_viewport().set_input_as_handled()
			return
	if _look_drag or not _cabinet.controls_local() or not _cabinet.is_interactive():
		return
	if not event is InputEventMouse:
		return
	var point := _screen_point((event as InputEventMouse).position)
	if point.x < 0:
		return
	_point = point
	if event is InputEventMouseMotion and _motion_in <= 0:
		_motion_in = 0.04
		_cabinet.send_input([0, _point.x, _point.y, 0])
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_cabinet.send_input([0, _point.x, _point.y, 0])
			_cabinet.send_input(
				[1 if button.button_index == MOUSE_BUTTON_LEFT else 3, _point.x, _point.y, 0]
			)
			if button.button_index not in _held_buttons:
				_held_buttons.append(button.button_index)
	get_viewport().set_input_as_handled()


func _screen_point(position: Vector2) -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector2i(-1, -1)
	var origin := camera.project_ray_origin(position)
	var direction := camera.project_ray_normal(position)
	var point := ScummArcadePointer.project(_world_screen.global_transform, origin, direction)
	if point.x < 0:
		return point
	var exclusions: Array[RID] = []
	if is_instance_valid(_player):
		exclusions.append(_player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 8.0, 1, exclusions)
	if get_world_3d().direct_space_state.intersect_ray(query).get("collider") != _cabinet:
		return Vector2i(-1, -1)
	return point


func _build_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	_panel = Button.new()
	_panel.text = "Leave"
	_panel.custom_minimum_size = Vector2(220, 42)
	_panel.focus_mode = Control.FOCUS_NONE
	_panel.hide()
	_layer.add_child(_panel)
	_panel.pressed.connect(close)
	get_viewport().size_changed.connect(_layout_panel)
	_panel.minimum_size_changed.connect(func() -> void: _layout_panel.call_deferred())


func _label(text: String, at: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = font_size
	label.pixel_size = 0.002
	label.modulate = color
	label.outline_size = 0
	add_child(label)
	return label


func _layout_panel() -> void:
	# The game's fixed reference viewport otherwise shrinks buttons to a few
	# pixels on phones. Keep the leave button in readable physical pixels locally.
	var stretch := get_viewport().get_stretch_transform().get_scale().x
	var ui_scale := maxf(1.0, 1.0 / maxf(stretch, 0.1))
	_layer.scale = Vector2.ONE * ui_scale
	var viewport_size := get_viewport().get_visible_rect().size / ui_scale
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position = Vector2(
		(viewport_size.x - _panel.size.x) / 2, viewport_size.y - _panel.size.y - 12
	)


func _style_model(model: Node) -> void:
	var tint: Color = _cabinet.details()["color"]
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface: int in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material != null and material.resource_name.begins_with("Petrol"):
				var enamel := material.duplicate() as StandardMaterial3D
				enamel.albedo_color = tint
				enamel.emission = tint * 0.15
				part.set_surface_override_material(surface, enamel)
	var badge: String = _cabinet.details()["badge"]
	if badge.is_empty():
		return
	for side: float in [-1.0, 1.0]:
		var disk := MeshInstance3D.new()
		var circle := CylinderMesh.new()
		circle.top_radius = 0.255
		circle.bottom_radius = 0.255
		circle.height = 0.012
		disk.mesh = circle
		disk.rotation.z = PI / 2
		disk.position = Vector3(side * 0.802, 1.62, -0.035)
		var ink := StandardMaterial3D.new()
		ink.albedo_color = Color("152536")
		disk.material_override = ink
		add_child(disk)
		var stamp := _label(badge, Vector3(side * 0.815, 1.62, -0.035), 25, GOLD)
		stamp.rotation.y = side * PI / 2
