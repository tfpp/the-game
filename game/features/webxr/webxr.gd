extends Node
## Opt-in browser VR. No XR state or controller poses are sent over the network.

const Rig := preload("res://features/webxr/vr_rig.gd")
const VrPanel := preload("res://features/webxr/vr_panel.gd")

var interface: WebXRInterface
var rig: Rig
var panel: VrPanel
var supported := false
var pending := false
var active := false
var previous_device := Controls.Device.KEYBOARD
var previous_scale := 1.0
var previous_canvas_mask := 0xFFFFFFFF
var status := "VR requires a WebXR browser and HTTPS (Quest Browser recommended)."


func _ready() -> void:
	set_process(false)
	if DisplayServer.get_name() == "headless":
		return
	panel = VrPanel.new()
	add_child(panel)
	panel.enter_requested.connect(enter_vr)
	add_to_group(&"esc_menu_links")
	if not OS.has_feature("web"):
		return
	interface = XRServer.find_interface("WebXR") as WebXRInterface
	if interface == null:
		return
	interface.session_supported.connect(_supported)
	interface.session_started.connect(_started)
	interface.session_ended.connect(_ended)
	interface.session_failed.connect(_failed)
	interface.reference_space_reset.connect(_recenter)
	interface.visibility_state_changed.connect(_visibility_changed)
	interface.is_session_supported("immersive-vr")


func esc_menu_label() -> String:
	return "Quest / WebXR"


func esc_menu_open() -> void:
	panel.show_panel(status, supported and not pending)


func _supported(mode: String, available: bool) -> void:
	if mode != "immersive-vr":
		return
	supported = available
	if available:
		status = "VR is available. Enter VR to grant headset access."
	if panel.visible:
		esc_menu_open()


func enter_vr() -> void:
	if not supported or pending or active or interface == null:
		return
	if get_tree().get_first_node_in_group(&"local_player") == null:
		panel.show_panel("Join the game or choose Play offline first.", false)
		return
	pending = true
	panel.enter.disabled = true
	interface.session_mode = "immersive-vr"
	interface.required_features = "local-floor"
	interface.requested_reference_space_types = "local-floor"
	interface.optional_features = ""
	# Must remain synchronous inside the button's browser user gesture.
	if not interface.initialize():
		_failed("The browser could not request a VR session.")


func _started() -> void:
	pending = false
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or not panel.visible:
		interface.uninitialize()
		return
	previous_device = Controls.device
	previous_scale = get_viewport().scaling_3d_scale
	previous_canvas_mask = get_viewport().canvas_cull_mask
	active = true
	Controls.select_device(Controls.Device.XR)
	panel.hide_panel()
	Controls.start()
	rig = Rig.new()
	add_child(rig)
	rig.attach(player)
	rig.exit_requested.connect(leave_vr)
	get_viewport().use_xr = true
	get_viewport().canvas_cull_mask = 0
	get_viewport().scaling_3d_scale = 1.0
	set_process(true)


func _process(_delta: float) -> void:
	if not is_instance_valid(rig.player) or rig.player.is_queued_for_deletion():
		leave_vr()
	elif get_tree().get_first_node_in_group(&"modal_ui") != null:
		leave_vr()
	elif interface != null and interface.visibility_state != "visible":
		Controls.pause()


func leave_vr() -> void:
	if interface != null and interface.is_initialized():
		interface.uninitialize()
	_ended()


func _ended() -> void:
	pending = false
	if not active:
		return
	active = false
	set_process(false)
	get_viewport().use_xr = false
	get_viewport().canvas_cull_mask = previous_canvas_mask
	get_viewport().scaling_3d_scale = previous_scale
	if is_instance_valid(rig):
		rig.release_actions()
		rig.set_process(false)
		rig.set_physics_process(false)
		# Preserve a modal's replacement camera (e.g. an arcade machine).
		if get_viewport().get_camera_3d() == rig.camera and is_instance_valid(rig.player):
			(rig.player.get_node("Camera") as Camera3D).make_current()
		(rig as Node).queue_free()
		rig = null
	Controls.select_device(previous_device)
	Controls.pause()


func _failed(message: String) -> void:
	pending = false
	_ended()
	status = "Could not enter VR: " + message + " Try again in Quest Browser over HTTPS."
	if is_instance_valid(panel):
		panel.show_panel(status, supported)


func _recenter() -> void:
	if is_instance_valid(rig):
		rig.recenter()


func _visibility_changed() -> void:
	if not active:
		return
	if interface.visibility_state == "visible":
		Controls.start()
	else:
		Controls.pause()


func _exit_tree() -> void:
	leave_vr()
