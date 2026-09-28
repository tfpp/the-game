extends GutTest

const Feature := preload("res://features/flashlight/flashlight.gd")
const SCENE := preload("res://features/flashlight/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const Bindings := preload("res://features/control_scheme/input_bindings.gd")

var _feature: Feature
var _player: Player
var _device: int
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
	_feature = SCENE.instantiate() as Feature
	add_child_autofree(_feature)


func after_each() -> void:
	Controls.device = _device
	Controls.playing = _playing


func _press(echo: bool = false, pressed: bool = true, code: Key = KEY_H) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = pressed
	key.echo = echo
	_feature._unhandled_input(key)


func test_h_toggles_and_creates_a_shadow_casting_beam() -> void:
	assert_true(_feature.enabled_peers.is_empty())
	_press()
	_feature._process(0.0)
	assert_true(_feature.enabled_peers.has(1))
	assert_eq(_feature._lights.size(), 1)
	assert_true(_feature._lights[1].shadow_enabled)
	assert_eq(_feature._lights[1].spot_range, 24.0)
	_press()
	_feature._process(0.0)
	assert_true(_feature.enabled_peers.is_empty())
	assert_true(_feature._lights.is_empty())


func test_echo_release_pause_and_modal_do_not_toggle() -> void:
	_press(true)
	_press(false, false)
	Controls.playing = false
	_press()
	Controls.playing = true
	var modal := Node.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	_press()
	assert_true(_feature.enabled_peers.is_empty())


func test_rebind_uses_shared_controls_catalog() -> void:
	var original := InputMap.action_get_events(Feature.ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	Bindings.bind(Feature.ACTION, false, key)
	_press()
	assert_true(_feature.enabled_peers.is_empty())
	_press(false, true, KEY_J)
	assert_true(_feature.enabled_peers.has(1))
	assert_eq(Bindings.label_for(Feature.ACTION), "Flashlight")
	Bindings.set_events(Feature.ACTION, original)


func test_request_requires_sender_player_and_cannot_toggle_another_peer() -> void:
	_player.name = "2"
	_player.set_multiplayer_authority(2)
	_feature.request_toggle()
	assert_true(_feature.enabled_peers.is_empty(), "peer 1 cannot toggle peer 2")
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	_feature.enabled_peers = {2: true}
	_feature.request_toggle()
	assert_eq(_feature.enabled_peers, {1: true, 2: true})


func test_beam_uses_eyes_and_aim_independent_of_third_person_camera() -> void:
	_player.yaw = 0.7
	_player.pitch = -0.4
	var camera := _player.get_node("Camera") as Camera3D
	camera.position = Vector3(100, 100, 100)
	var beam := _feature._beam_transform(_player)
	var eye_height := _player.movement.eye_height_m() - _player.movement.hull_height_m() * 0.5
	assert_almost_eq(beam.origin.y, _player.global_position.y + eye_height, 0.001)
	assert_almost_eq(beam.basis.get_euler(), Vector3(-0.4, 0.7, 0), Vector3.ONE * 0.001)
	_player.set_multiplayer_authority(2)
	_player.net_pitch = 0.2
	_player.net_yaw = -0.3
	beam = _feature._beam_transform(_player)
	assert_almost_eq(beam.basis.get_euler(), Vector3(0.2, -0.3, 0), Vector3.ONE * 0.001)


func test_snapshot_disconnect_missing_player_and_session_reset() -> void:
	var sync := _feature.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	var path := NodePath(".:enabled_peers")
	assert_true(sync.replication_config.property_get_spawn(path))
	assert_eq(sync.replication_config.property_get_replication_mode(path), 2)
	_feature.enabled_peers = {1: true, 2: true}
	_feature._process(0.0)
	assert_eq(_feature._lights.size(), 1, "snapshot waits for matching player spawn")
	_feature._remove_peer(1)
	_feature._process(0.0)
	assert_false(_feature.enabled_peers.has(1))
	assert_true(_feature._lights.is_empty())
	_feature.request_toggle()
	_feature._process(0.0)
	_player.queue_free()
	_feature._process(0.0)
	assert_true(_feature._lights.is_empty())
	_feature._reset(Network.Mode.OFFLINE)
	assert_true(_feature.enabled_peers.is_empty())
