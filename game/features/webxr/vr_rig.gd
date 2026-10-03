extends Node3D
## Local presentation/input adapter. Player retains collision, movement and replication.

signal exit_requested

var player: Player
var camera: XRCamera3D
var left: XRController3D
var right: XRController3D
var prompt: Label3D
var heading := 0.0
var anchor := Vector3.ZERO
var last_yaw := 0.0
var calibrated := false
var turn_armed := true
var firing := false


func _ready() -> void:
	process_priority = 15  # After first/third-person cameras, before held-item mounts.
	process_physics_priority = -10  # Feed inputs before Player's movement tick.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var origin := XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	camera.current = false
	origin.add_child(camera)
	left = _controller(origin, &"left_hand")
	right = _controller(origin, &"right_hand")
	left.button_pressed.connect(_button.bind(false))
	right.button_pressed.connect(_button.bind(true))
	right.button_released.connect(_released)
	Controls.input_reset.connect(release_actions)
	prompt = Label3D.new()
	prompt.position = Vector3(0, -0.25, -1.3)
	prompt.font_size = 28
	prompt.pixel_size = 0.001
	prompt.no_depth_test = true
	camera.add_child(prompt)


func _controller(origin: XROrigin3D, tracker_name: StringName) -> XRController3D:
	var controller := XRController3D.new()
	controller.tracker = tracker_name
	origin.add_child(controller)
	return controller


func attach(local_player: Player) -> void:
	player = local_player
	heading = player.yaw
	last_yaw = player.yaw
	camera.make_current()


func recenter() -> void:
	calibrated = false


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if not Controls.gameplay_active():
		release_actions()
		Controls.xr_move = Vector2.ZERO
		return
	var head := XRServer.get_tracker(&"head") as XRPositionalTracker
	if head == null or not head.has_pose(&"default"):
		release_actions()
		Controls.xr_move = Vector2.ZERO
		return
	var pose := head.get_pose(&"default")
	if not pose.has_tracking_data:
		release_actions()
		Controls.xr_move = Vector2.ZERO
		return
	if not right.get_is_active():
		release_actions()
	update_pose(pose.transform)
	var stick := left.get_vector2(&"thumbstick") if left.get_is_active() else Vector2.ZERO
	# Godot XR's positive Y is forward; Controls uses negative Y for forward.
	Controls.xr_move = Controls.deadzone(Vector2(stick.x, -stick.y))
	update_turn(right.get_vector2(&"thumbstick").x if right.get_is_active() else 0.0)


func update_pose(head: Transform3D) -> void:
	# Preserve owner teleports that specify a yaw instead of overwriting them next tick.
	heading += angle_difference(last_yaw, player.yaw)
	if not calibrated:
		anchor = head.origin
		heading = player.yaw - head.basis.get_euler().y
		calibrated = true
	player.yaw = heading + head.basis.get_euler().y
	player.pitch = clampf(head.basis.get_euler().x, deg_to_rad(-89), deg_to_rad(89))
	last_yaw = player.yaw


func update_turn(axis: float) -> void:
	if absf(axis) < 0.3:
		turn_armed = true
	if absf(axis) < 0.7 or not turn_armed:
		return
	turn_armed = false
	var turn := -signf(axis) * deg_to_rad(30)
	# Turn around the headset, keeping the player's physical lean in place.
	var offset := camera.position - anchor
	anchor = camera.position - Basis(Vector3.UP, -turn) * offset
	heading += turn
	player.yaw += turn
	last_yaw = player.yaw


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	rotation.y = heading
	var eye := player.get_global_transform_interpolated().origin
	eye.y += player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5
	global_position = eye - global_basis * anchor
	(player.get_node("Body") as Node3D).visible = false
	# Existing item mounts and local aim checks keep their original camera interface.
	(player.get_node("Camera") as Camera3D).global_transform = camera.global_transform
	var interaction := get_tree().get_first_node_in_group(&"interaction")
	var text := str(interaction.call("target_text")) if interaction != null else ""
	prompt.text = "Trigger: " + text if not text.is_empty() else "B / Y: leave VR"
	prompt.modulate = interaction.call("target_color") if interaction != null else Color.WHITE


func _button(button: StringName, right_hand: bool) -> void:
	if button == &"by_button":
		exit_requested.emit()
		return
	if not Controls.gameplay_active():
		return
	if button == &"ax_button" and right_hand:
		Controls.jump_queued = true
	elif button == &"trigger_click":
		get_tree().call_group(&"interaction", "use")
	elif button == &"grip_click" and right_hand:
		firing = true
		_action(&"primary_action", true)
		_action(&"gun_fire", true)
	elif button == &"grip_click":
		_action(&"gun_reload", true)
		_action(&"gun_reload", false)
	elif button == &"ax_button":
		_action(&"inventory", true)
		_action(&"inventory", false)


func _released(button: StringName) -> void:
	if button == &"grip_click":
		release_actions()


func release_actions() -> void:
	if not firing:
		return
	firing = false
	_action(&"primary_action", false)
	_action(&"gun_fire", false)


func _action(action: StringName, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
