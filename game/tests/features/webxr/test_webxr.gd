extends GutTest

const Feature := preload("res://features/webxr/webxr.gd")
const Rig := preload("res://features/webxr/vr_rig.gd")
const VrPanel := preload("res://features/webxr/vr_panel.gd")
const PLAYER := preload("res://core/player/player.tscn")

var feature: Feature
var player: Player
var saved_device: int
var saved_playing: bool


func before_each() -> void:
	saved_device = Controls.device
	saved_playing = Controls.playing
	Controls.device = Controls.Device.XR
	Controls.start()
	player = PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	feature = Feature.new()
	add_child_autofree(feature)
	feature.panel = VrPanel.new()
	feature.add_child(feature.panel)
	feature.panel.show_panel("Ready", true)


func after_each() -> void:
	feature.leave_vr()
	Controls.clear_input()
	Controls.device = saved_device
	Controls.playing = saved_playing
	get_viewport().use_xr = false


func _start() -> void:
	feature._started()
	feature.rig.set_physics_process(false)


func test_native_headless_does_not_register_or_initialize_xr() -> void:
	assert_null(feature.interface)
	assert_false(feature.is_in_group(&"esc_menu_links"))
	assert_false(feature.active)


func test_support_callback_and_failed_session_allow_retry() -> void:
	feature._supported("inline", true)
	assert_false(feature.supported)
	feature._supported("immersive-vr", true)
	assert_true(feature.supported)
	feature.pending = true
	feature._failed("Denied")
	assert_false(feature.pending)
	assert_false(feature.active)
	assert_false(feature.panel.enter.disabled)
	assert_string_contains(feature.panel.status.text, "Denied")
	assert_true(feature.panel.is_in_group(&"modal_ui"))


func test_exit_restores_viewport_device_and_clears_motion() -> void:
	Controls.device = Controls.Device.TOUCH
	get_viewport().scaling_3d_scale = 0.6
	_start()
	assert_true(feature.active)
	assert_true(get_viewport().use_xr)
	assert_eq(get_viewport().canvas_cull_mask, 0)
	assert_eq(Controls.device, Controls.Device.XR)
	assert_false(feature.panel.is_in_group(&"modal_ui"))
	Controls.xr_move = Vector2.ONE
	Controls.jump_queued = true
	feature.leave_vr()
	feature.leave_vr()
	assert_false(get_viewport().use_xr)
	assert_eq(get_viewport().canvas_cull_mask, 0xFFFFFFFF)
	assert_almost_eq(get_viewport().scaling_3d_scale, 0.6, 0.001)
	assert_eq(Controls.device, Controls.Device.TOUCH)
	assert_eq(Controls.xr_move, Vector2.ZERO)
	assert_false(Controls.jump_queued)
	assert_eq(get_viewport().get_camera_3d(), player.get_node("Camera"))
	get_viewport().scaling_3d_scale = 1.0


func test_pose_preserves_entry_facing_and_tracks_head_and_teleport() -> void:
	player.yaw = 0.7
	_start()
	var rig := feature.rig
	rig.update_pose(Transform3D(Basis(Vector3.UP, 0.3), Vector3(2, 1.4, 3)))
	assert_almost_eq(player.yaw, 0.7, 0.001)
	rig.update_pose(Transform3D(Basis(Vector3.UP, 0.5), Vector3(2, 1.4, 3)))
	assert_almost_eq(player.yaw, 0.9, 0.001)
	player.yaw = 2.0  # Same owner-side result as server_teleport's optional facing.
	player.position = Vector3(100, 20, -70)
	rig.update_pose(Transform3D(Basis(Vector3.UP, 0.5), Vector3(2, 1.4, 3)))
	rig.camera.position = Vector3(2, 1.4, 3)
	player.reset_physics_interpolation()
	rig._process(0.0)
	assert_almost_eq(player.yaw, 2.0, 0.001)
	var expected := player.global_position
	expected.y += player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5
	assert_almost_eq(rig.camera.global_position, expected, Vector3.ONE * 0.001)
	assert_eq((player.get_node("Camera") as Camera3D).global_transform, rig.camera.global_transform)


func test_snap_turn_requires_stick_release_and_turns_right() -> void:
	_start()
	var rig := feature.rig
	rig.update_turn(1.0)
	assert_almost_eq(player.yaw, -deg_to_rad(30), 0.001)
	rig.update_turn(1.0)
	assert_almost_eq(player.yaw, -deg_to_rad(30), 0.001)
	rig.update_turn(0.0)
	rig.update_turn(-1.0)
	assert_almost_eq(player.yaw, 0.0, 0.001)


func test_modal_exits_without_stealing_its_camera() -> void:
	_start()
	var modal := Camera3D.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	modal.make_current()
	feature._process(0.0)
	assert_false(feature.active)
	assert_eq(get_viewport().get_camera_3d(), modal)


func test_player_removal_exits_without_touching_remote_player() -> void:
	_start()
	var remote := PLAYER.instantiate() as Player
	remote.set_multiplayer_authority(42)
	add_child_autofree(remote)
	remote.net_position = Vector3(9, 9, 9)
	player.free()
	feature._process(0.0)
	assert_false(feature.active)
	assert_eq(remote.net_position, Vector3(9, 9, 9))


func test_xr_motion_uses_shared_controls_and_ignores_emulated_devices() -> void:
	feature.panel.hide_panel()
	Controls.xr_move = Vector2(0, -1)
	assert_eq(Controls.movement(), Vector2(0, -1))
	var event := InputEventJoypadMotion.new()
	event.axis_value = 1.0
	Controls._input(event)
	assert_eq(Controls.device, Controls.Device.XR)
	Controls._joy_connection_changed(10, true)
	assert_eq(Controls.device, Controls.Device.XR)
	Controls.look_delta = Vector2.ONE
	assert_eq(Controls.consume_look(1.0), Vector2.ZERO)
	Controls.pause()
	assert_eq(Controls.movement(), Vector2.ZERO)
	assert_eq(Controls.xr_move, Vector2.ZERO)


func test_jump_button_respects_modal_and_left_button_does_not_jump() -> void:
	_start()
	feature.rig._button(&"ax_button", false)
	assert_false(Controls.consume_jump())
	feature.rig._button(&"ax_button", true)
	assert_true(Controls.consume_jump())
	assert_false(Controls.consume_jump())
	feature.panel.show_panel("Paused", true)
	feature.rig._button(&"ax_button", true)
	assert_false(Controls.consume_jump())
