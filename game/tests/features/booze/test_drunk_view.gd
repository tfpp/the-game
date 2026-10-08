extends GutTest
## Local drunk presentation: eased-in sway, honest aim drift, weaving steps, the
## double-vision screen and holding a blacked-out player still until teleported.

const BOOZE := preload("res://features/booze/feature.tscn")
const BAR := preload("res://features/bar_companion/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _booze: Booze
var _view: DrunkView
var _bar: BarCompanion
var _player: Player
var _device: Controls.Device
var _playing: bool


func before_each() -> void:
	_device = Controls.device
	_playing = Controls.playing
	Controls.device = Controls.Device.GAMEPAD
	Controls.playing = true
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_bar = BAR.instantiate() as BarCompanion
	add_child_autofree(_bar)
	_bar.set_process(false)
	_booze = BOOZE.instantiate() as Booze
	add_child_autofree(_booze)
	_booze.set_process(false)
	_view = _booze.get_node("DrunkView") as DrunkView
	_view.set_process(false)
	_view.set_physics_process(false)


func after_each() -> void:
	Controls.device = _device
	Controls.playing = _playing
	await get_tree().process_frame


func _camera() -> Camera3D:
	return _player.get_node("Camera") as Camera3D


func _frame(delta: float) -> void:
	_player._update_camera()
	_view._process(delta)


func test_sober_players_see_and_move_normally() -> void:
	_frame(0.1)
	assert_eq(_view.level, 0.0)
	assert_false(_view._effect.visible, "no full-screen pass while sober")
	assert_false(_view._black.visible)
	assert_true(_camera().global_basis.is_equal_approx(Basis.from_euler(Vector3(0, 0, 0))))
	_player.velocity = Vector3(0, 0, -5)
	_view._stagger(_player, 0.1)
	assert_eq(_player.velocity, Vector3(0, 0, -5))


func test_drinks_ease_into_sway_double_vision_and_drifting_aim() -> void:
	for _i: int in 6:
		_bar.add_drink(1)
	_frame(0.5)
	assert_almost_eq(_view.level, DrunkView.EASE_PER_S * 0.5, 0.001, "eases in, never snaps")
	for _i: int in 60:
		_frame(0.1)
	assert_almost_eq(_view.level, BoozeRules.intensity(6), 0.001)
	assert_true(_view._effect.visible)
	assert_gt(float(_view._material.get_shader_parameter("strength")), 0.5)
	var rolled := false
	var start_yaw := _player.yaw
	var yaw_moved := false
	for _i: int in 40:
		_frame(0.1)
		var up := _camera().global_basis.y
		rolled = rolled or absf(up.x) > 0.02 or absf(up.z) > 0.02
		yaw_moved = yaw_moved or not is_equal_approx(_player.yaw, start_yaw)
	assert_true(rolled, "camera rolls")
	assert_true(yaw_moved, "aim drifts with the view, so shots follow what is seen")
	# Sway is applied as changes, so it never accumulates into a spin.
	assert_lt(absf(_player.yaw - start_yaw), deg_to_rad(6.0))
	Controls.playing = false
	var paused_yaw := _player.yaw
	_frame(0.5)
	assert_eq(_player.yaw, paused_yaw, "menus stop the aim drift")


func test_sobering_up_fades_effects_out_and_releases_the_screen() -> void:
	_view.level = 0.5
	_frame(0.1)
	assert_true(_view._effect.visible)
	for _i: int in 40:
		_frame(0.1)
	assert_eq(_view.level, 0.0)
	assert_false(_view._effect.visible)


func test_walking_weaves_and_hammered_players_stumble_sideways() -> void:
	_view.level = 1.0
	_view._time = 0.6
	assert_ne(BoozeRules.veer_rate(_view._time, 1.0), 0.0)
	# Off the ground nothing changes (no mid-air steering).
	_player.velocity = Vector3(0, 0, -5)
	_view._stagger(_player, 0.1)
	assert_eq(_player.velocity, Vector3(0, 0, -5))
	_view._stumble_in = 10.0
	var walked := _view.stagger(Vector3(0, -1, -5), 0.0, 0.1)
	assert_almost_eq(Vector2(walked.x, walked.z).length(), 5.0, 0.001, "turns, never speeds up")
	assert_gt(absf(walked.x), 0.01, "weaves off a straight line")
	assert_eq(walked.y, -1.0)
	assert_eq(_view.stagger(Vector3(0.1, 0, 0), 0.0, 0.1), Vector3(0.1, 0, 0), "standing still")
	_view._stumble_in = 0.0
	var stumble := _view.stagger(Vector3.ZERO, 0.0, 0.1)
	assert_almost_eq(
		Vector2(stumble.x, stumble.z).length(),
		BoozeRules.stumble_speed(1.0),
		0.001,
		"sideways stumble"
	)
	assert_almost_eq(stumble.z, 0.0, 0.001, "stumbles go sideways for yaw 0")
	assert_gt(_view._stumble_in, 0.0)
	_view.level = 0.3
	_view._stumble_in = 0.0
	assert_eq(_view.stagger(Vector3.ZERO, 0.0, 0.1), Vector3.ZERO, "tipsy players do not stumble")


func test_blackout_holds_the_player_and_accepts_the_metro_teleport() -> void:
	_player.global_position = Vector3(2, 1, 3)
	_booze._set_phase(1, BoozeRules.Phase.OUT)
	_view._physics_process(0.016)
	_player.global_position += Vector3(0.2, 0.1, 0)
	_player.velocity = Vector3(3, 2, 0)
	_view._physics_process(0.016)
	assert_eq(_player.global_position, Vector3(2, 1, 3), "cannot walk or jump away")
	assert_eq(_player.velocity, Vector3.ZERO)
	assert_eq(_player.net_position, Vector3(2, 1, 3))
	var platform := Vector3(1803.3, 2.14, -7990)
	_player.server_teleport.rpc_id(1, platform, PI)
	_view._physics_process(0.016)
	assert_eq(_player.global_position, platform, "teleport is accepted")
	_booze._set_phase(1, BoozeRules.Phase.COLLAPSE)
	_player.global_position = platform + Vector3(0, -0.2, 0)
	_view._physics_process(0.016)
	assert_almost_eq(_player.global_position.y, platform.y - 0.2, 0.001, "collapsing can fall")
	_booze._clear(1)
	_view._physics_process(0.016)
	assert_null(_view._pinned, "released after waking")


func test_blackout_darkens_the_screen_and_lays_the_first_person_camera_down() -> void:
	_booze._set_phase(1, BoozeRules.Phase.OUT)
	_booze.present(0.1)
	_frame(0.1)
	assert_true(_view._black.visible)
	assert_eq(_view._black.color.a, 1.0)
	assert_eq(_view._caption.text, "You blacked out.")
	for _i: int in 20:
		_booze.present(0.1)
	_frame(0.1)
	var feet_y := _player.global_position.y - _player.movement.hull_height_m() * 0.5
	assert_between(_camera().global_position.y - feet_y, 0.1, 0.4, "eyes on the floor")
	assert_gt((-_camera().global_basis.z).y, 0.8, "staring at the ceiling")
	_booze._set_phase(1, BoozeRules.Phase.WAKE)
	_booze.present(0.1)
	_frame(0.1)
	assert_string_contains(_view._caption.text, "clothes")
	for _i: int in 70:
		_booze.present(0.1)
		_frame(0.1)
	assert_false(_view._black.visible, "eyes open")
	var eye_y := feet_y + _player.movement.eye_height_m()
	assert_almost_eq(_camera().global_position.y, eye_y, 0.01, "back on their feet")
