extends GutTest

const Feature := preload("res://features/third_person/third_person.gd")
const PLAYER := preload("res://core/player/player.tscn")
const TICK := 1.0 / 64.0

var _feature: Feature
var _player: Player
var _saved_device: int
var _saved_playing: bool
var _saved_joypad: int
var _saved_touch: bool


func before_each() -> void:
	_saved_device = Controls.device
	_saved_playing = Controls.playing
	_saved_joypad = Controls.joypad
	_saved_touch = Controls.touch_available
	Controls.touch_available = true
	Controls.device = Controls.Device.TOUCH
	Controls.joypad = -1
	Controls.start()
	_player = PLAYER.instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_feature = Feature.new()
	add_child_autofree(_feature)
	_feature.toggle_camera()


func after_each() -> void:
	Controls.clear_input()
	Controls.device = _saved_device
	Controls.playing = _saved_playing
	Controls.joypad = _saved_joypad
	Controls.touch_available = _saved_touch
	get_viewport().use_xr = false
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)


func _move(input: Vector2) -> Vector3:
	Controls.touch_move = input
	_player.velocity = Vector3.ZERO
	_player._physics_process(TICK)
	return Vector3(_player.velocity.x, 0, _player.velocity.z)


func test_front_facing_camera_forward_moves_away_from_camera() -> void:
	_feature.orbit_look(Vector2(PI, 0))
	_player._process(0.0)
	_feature._process(0.0)
	var camera := _player.get_node("Camera") as Camera3D
	var toward_camera := camera.global_position - _player.global_position
	toward_camera.y = 0
	var velocity := _move(Vector2.UP)
	assert_lt(velocity.dot(toward_camera), 0.0)
	assert_gt(velocity.z, 0.0, "Forward reverses world direction, not camera-relative direction")
	assert_eq(_player.yaw, 0.0, "Moving must not turn weapon aim")
	assert_eq(_player.net_yaw, 0.0)
	assert_eq(
		_player.net_velocity, _player.velocity, "Existing replication publishes this movement"
	)
	assert_eq(_player.net_position, _player.global_position)


func test_all_directions_match_camera_with_nonzero_player_yaw() -> void:
	_player.yaw = 0.7
	_feature.orbit_look(Vector2(PI / 2, 0.4))
	_player._process(0.0)
	_feature._process(0.0)
	var camera := _player.get_node("Camera") as Camera3D
	var forward := -camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := camera.global_basis.x
	for input: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(1, -1)]:
		var expected := (right * input.x - forward * input.y).normalized()
		assert_almost_eq(_move(input).normalized(), expected, Vector3.ONE * 0.0001)


func test_pitch_extremes_do_not_change_horizontal_speed_or_direction() -> void:
	_feature.orbit_look(Vector2(0.9, 0))
	var baseline := _move(Vector2.UP)
	for pitch: float in [-Feature.PITCH_LIMIT, Feature.PITCH_LIMIT]:
		_player.pitch = pitch
		assert_almost_eq(_move(Vector2.UP), baseline, Vector3.ONE * 0.0001)


func test_analog_strength_uses_original_source_movement_step() -> void:
	_feature.orbit_look(Vector2(0.5, 0))
	var input := Vector2(0.2, -0.3)
	var expected := SourceMovement.step(
		Vector3.ZERO,
		SourceMovement.wish_direction(-0.5, input),
		false,
		false,
		_player.movement,
		TICK,
		input.length()
	)
	var velocity := _move(input)
	assert_almost_eq(velocity.x, expected.velocity.x, 0.0001)
	assert_almost_eq(velocity.z, expected.velocity.z, 0.0001)


func test_current_look_and_orbit_apply_before_any_render_frame() -> void:
	_feature.orbit_look(Vector2(0.6, 0))
	Controls.look_delta = Vector2(0.4, 0)
	var velocity := _move(Vector2.UP)
	assert_almost_eq(
		velocity.normalized(), SourceMovement.wish_direction(-1.0, Vector2.UP), Vector3.ONE * 0.0001
	)
	assert_almost_eq(_player.net_yaw, -0.4, 0.0001)


func test_first_person_and_missing_feature_keep_original_heading() -> void:
	_player.yaw = 0.3
	_feature.orbit_look(Vector2(PI, 0))
	_feature.toggle_camera()
	var expected := SourceMovement.wish_direction(_player.yaw, Vector2.UP)
	assert_almost_eq(_move(Vector2.UP).normalized(), expected, Vector3.ONE * 0.0001)
	_feature.free()
	assert_almost_eq(_move(Vector2.UP).normalized(), expected, Vector3.ONE * 0.0001)


func test_xr_ignores_orbit_and_resumes_it_on_exit() -> void:
	_feature.orbit_look(Vector2(PI, 0))
	get_viewport().use_xr = true
	Controls.device = Controls.Device.XR
	Controls.xr_move = Vector2.UP
	assert_lt(_move(Vector2.UP).z, 0.0)
	get_viewport().use_xr = false
	Controls.device = Controls.Device.TOUCH
	assert_gt(_move(Vector2.UP).z, 0.0)


func test_pause_and_modal_still_block_movement() -> void:
	_feature.orbit_look(Vector2(PI, 0))
	Controls.pause()
	assert_eq(_move(Vector2.UP), Vector3.ZERO)
	Controls.start()
	var modal := Node.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	assert_eq(_move(Vector2.UP), Vector3.ZERO)
	modal.remove_from_group(&"modal_ui")
	assert_gt(_move(Vector2.UP).z, 0.0)


func test_action_bindings_share_camera_heading_with_controller_and_touch() -> void:
	_feature.orbit_look(Vector2(PI, 0))
	# Headless cannot capture a keyboard pointer. Action input takes the same
	# Controls.movement path; GAMEPAD with no physical pad tests the bound actions.
	Controls.device = Controls.Device.GAMEPAD
	Input.action_press(&"move_forward")
	assert_gt(_move(Vector2.ZERO).z, 0.0)
	Input.action_release(&"move_forward")
	Input.action_press(&"move_right")
	assert_lt(_move(Vector2.ZERO).x, 0.0)


func test_remote_and_replacement_players_do_not_inherit_local_orbit() -> void:
	_feature.orbit_look(Vector2(PI, 0))
	var remote := PLAYER.instantiate() as Player
	remote.set_multiplayer_authority(2)
	remote.yaw = 0.8
	add_child_autofree(remote)
	assert_eq(_feature.movement_yaw(remote), 0.8)
	assert_false(remote.is_physics_processing(), "Remote remains a replicated puppet")
	_player.free()
	_player = PLAYER.instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	assert_lt(_move(Vector2.UP).z, 0.0, "Replacement resets orbit even before rendering")
	assert_true(_feature.enabled, "Camera preference survives respawn")
