extends GutTest

const MACHINE := preload("res://features/slot_machine/machine.tscn")
var _machine: SlotMachine
var _view: Node3D
var _feedback: Node3D


func before_each() -> void:
	add_child_autofree(GameAudio.new())
	_machine = MACHINE.instantiate()
	add_child_autofree(_machine)
	_machine.set_process(false)
	_view = _machine.get_node("View")
	_view.set_process(false)
	_feedback = _view.feedback
	_view._process(.016)


func test_mechanical_audio_tracks_spin_stops_and_spring_return() -> void:
	_machine._begin_spin(1, "Test", [0, 0, 0], 3000)
	_view._process(.2)
	assert_true(_feedback.motor.playing)
	assert_same(_feedback.mechanism.stream, _feedback.LEVER)
	assert_gt(_view._lever.rotation.x, .7)
	_view._process(.5)
	assert_almost_eq(_view._lever.rotation.x, 0.0, .001, "Spring returns while reels still spin")
	_machine._advance(1.21)
	_view._process(.2)
	assert_same(_feedback.mechanism.stream, _feedback.STOP)
	assert_true(_feedback.motor.playing)
	_machine._advance(2)
	_view._process(.016)
	assert_false(_feedback.motor.playing)
	assert_true(_feedback.payout.playing)
	assert_gt(_feedback._win_left, 0.0)
	assert_eq(_view._positions, [0.0, 0.0, 0.0], "Final symbols show before payout effects")


func test_late_snapshot_does_not_replay_lever_stops_or_payout() -> void:
	_feedback.reset()
	_machine._begin_spin(1, "Test", [4, 4, 4], 2500)
	_machine.state["stopped"] = 2
	_feedback.update(_machine.state, .016)
	assert_true(_feedback.motor.playing, "Join ongoing machinery ambience")
	assert_false(_feedback.mechanism.playing)
	_feedback.reset()
	_machine.state["spinning"] = false
	_machine.state["stopped"] = 3
	_machine.state["won"] = true
	_feedback.update(_machine.state, .016)
	assert_false(_feedback.motor.playing)
	assert_false(_feedback.mechanism.playing)
	assert_false(_feedback.payout.playing)
	assert_eq(_feedback._win_left, 0.0)


func test_result_event_deduplication_loss_and_session_cleanup() -> void:
	_machine.play_result(1, true, 3000)
	_feedback.update(_machine.state, .4)
	var remaining: float = _feedback._win_left
	_machine.play_result(1, true, 3000)
	assert_eq(_feedback._win_left, remaining)
	_feedback.reset()
	_machine.play_result(2, false, 0)
	assert_eq(_feedback._win_left, 0.0)
	assert_false(_feedback.payout.playing)
	_machine._begin_spin(1, "Test", [0, 1, 2], 0)
	_view._process(.1)
	_feedback.reset()
	for voice: AudioStreamPlayer3D in [_feedback.motor, _feedback.mechanism, _feedback.payout]:
		assert_false(voice.playing)
		assert_eq(voice.bus, GameAudio.BUS)
		assert_lte(voice.max_distance, 18.0)


func test_distant_machine_stops_loop_and_disables_dynamic_light() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(100, 0, 0)
	add_child_autofree(camera)
	camera.make_current()
	_machine._begin_spin(1, "Test", [0, 1, 2], 0)
	_view._process(.1)
	assert_false(_feedback.motor.playing)
	assert_false(_feedback.mechanism.playing)
	assert_false(_feedback._wash.visible)


func test_sound_assets_are_bounded_and_motor_is_the_only_loop() -> void:
	for stream: AudioStreamWAV in [
		_feedback.MOTOR,
		_feedback.STOP,
		_feedback.LEVER,
		_feedback.PAYOUT,
		preload("res://assets/slot_machine/audio/bell.wav"),
		preload("res://assets/slot_machine/audio/loss.wav")
	]:
		assert_lte(stream.get_length(), 1.81)
		assert_gt(stream.get_length(), .1)
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
		assert_eq(stream.mix_rate, 22050)
	assert_eq(_feedback.motor.stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_not_null(_feedback._candle)
	assert_not_null(_feedback._button)
	assert_false(_feedback._wash.shadow_enabled)
