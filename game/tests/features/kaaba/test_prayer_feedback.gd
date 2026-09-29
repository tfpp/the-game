extends GutTest

const KAABA := preload("res://features/kaaba/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const INTERACTION := preload("res://features/interaction/interaction.gd")

var _prayer: KaabaPrayer
var _player: Player
var _interaction: CanvasLayer
var _device: Controls.Device
var _playing: bool


func before_each() -> void:
	_device = Controls.device
	_playing = Controls.playing
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	var root := add_child_autofree(KAABA.instantiate()) as Node3D
	_prayer = root.get_node("Prayer") as KaabaPrayer
	_prayer.set_process(false)
	_player = add_child_autofree(PLAYER.instantiate()) as Player
	_player.set_physics_process(false)
	_player.position = root.position + Vector3(2.7, 0.9144, 0)
	_player.net_position = _player.position
	_player.net_yaw = PI * 0.5
	_interaction = add_child_autofree(INTERACTION.new())
	await wait_physics_frames(3)


func after_each() -> void:
	Controls.select_device(_device)
	Controls.playing = _playing


func test_shared_use_keeps_countdown_and_completed_count_visible() -> void:
	assert_string_contains(_interaction.target_text(), "stay nearby for 6s")
	_interaction.use()
	assert_eq(_prayer.praying.get(1), 6)
	assert_string_contains(_interaction.target_text(), "Praying")
	_prayer._advance(1.1)
	assert_string_contains(_interaction.target_text(), "5s")
	_interaction.use()
	assert_eq(_prayer.praying.get(1), 5, "repeated Use cannot reset progress")
	_prayer._advance(4.9)
	assert_eq(_prayer.blessings_for(1), 1)
	assert_string_contains(_interaction.target_text(), "blessings 1/5")


func test_full_count_stays_visible_without_starting_another_prayer() -> void:
	_prayer.blessings = {1: 5}
	assert_string_contains(_interaction.target_text(), "full (5/5)")
	_interaction.use()
	assert_true(_prayer.praying.is_empty())
	assert_eq(_prayer.blessings_for(1), 5)


func test_keyboard_controller_and_touch_use_the_same_prayer_path() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_B
	button.pressed = true
	for event: InputEvent in [key, button]:
		_interaction._unhandled_input(event)
		assert_true(_prayer.praying.has(1))
		_prayer._advance(KaabaPrayer.PRAYER_S)
	_interaction.use()  # The touch overlay uses this public entry point.
	_prayer._advance(KaabaPrayer.PRAYER_S)
	assert_eq(_prayer.blessings_for(1), 3)


func test_prompt_and_server_agree_on_vertical_range() -> void:
	_player.net_position.y = 20.0
	assert_false(_prayer.can_use(_player))
	assert_false(_prayer.entity._validate_use(1, {}))


func test_completion_stays_outside_real_cube_on_all_four_sides() -> void:
	for yaw: float in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var outward := Basis(Vector3.UP, yaw) * Vector3.BACK
		_player.net_position = _prayer.global_position + outward * 2.7 + Vector3.UP * 0.9144
		_player.net_yaw = yaw
		var payload := _prayer._completion_effect(_player)
		var local: Vector3 = payload["position"] - _prayer.global_position
		assert_gt(local.dot(outward), 2.25, "effect is outside the solid Kaaba wall")
		assert_lt(float(payload["size"]), 1.0, "close effect retains its apparent size")
		var effect := BlessingEffect.new()
		add_child_autofree(effect)
		effect.build(false, float(payload["size"]))
		var view := effect.get_child(0) as MeshInstance3D
		var material := view.mesh.surface_get_material(0) as StandardMaterial3D
		assert_true(material.billboard_keep_scale, "billboarding must preserve the smaller size")
		var sparks := effect.get_child(1) as CPUParticles3D
		assert_true(sparks.local_coords, "sparks stay inside the scaled completion burst")
		assert_lt(
			sparks.initial_velocity_max * sparks.lifetime * float(payload["size"]),
			0.15,
			"sparks cannot travel back into the nearby camera",
		)
		assert_almost_eq(effect.scale.x, float(payload["size"]), 0.001)
		effect._process(0.1)
		assert_lt(effect.scale.x, 0.5, "animation preserves the collision-adjusted scale")
