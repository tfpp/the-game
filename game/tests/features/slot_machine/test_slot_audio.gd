extends GutTest

const MACHINE := preload("res://features/slot_machine/machine.tscn")

var _machine: SlotMachine
var _audio: AudioStreamPlayer3D


func before_each() -> void:
	_machine = MACHINE.instantiate() as SlotMachine
	add_child_autofree(_machine)
	_machine.set_process(false)
	_audio = _machine.get_node("Audio") as AudioStreamPlayer3D


func test_loss_clip_is_short_non_looping_and_fades_at_both_ends() -> void:
	var toot := _machine._lose_sound as AudioStreamWAV
	assert_not_null(toot)
	if toot == null:
		return
	assert_eq(toot.resource_path, "res://assets/slot_machine/audio/toot.wav")
	assert_eq(toot.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	assert_false(toot.stereo)
	assert_almost_eq(toot.get_length(), 0.22, 0.001)
	assert_eq(toot.format, AudioStreamWAV.FORMAT_16_BITS)
	var data := toot.data
	var peak := 0
	for offset: int in range(0, data.size(), 2):
		peak = maxi(peak, absi(data.decode_s16(offset)))
	assert_gt(peak, 1000, "Clip is not silence")
	assert_lte(peak, 16384, "Source peak stays below half scale")
	assert_eq(data.decode_s16(0), 0)
	assert_lt(absi(data.decode_s16(data.size() - 2)), 10, "Release fades to silence")


func test_losses_vary_pitch_and_duration_at_lower_volume() -> void:
	var pitches: Dictionary = {}
	for spin: int in range(1, 25):
		_machine.play_result(spin, false)
		assert_same(_audio.stream, _machine._lose_sound)
		assert_between(_audio.pitch_scale, 0.85, 1.35)
		assert_eq(_audio.volume_db, -14.0)
		var duration := _audio.stream.get_length() / _audio.pitch_scale
		assert_between(duration, 0.16, 0.26)
		pitches[_audio.pitch_scale] = true
	assert_gt(pitches.size(), 1, "Separate losses do not all use the same pitch")
	assert_eq(_machine.get_node("Celebration").get_child_count(), 0)


func test_duplicate_and_stale_events_do_not_change_loss_profile() -> void:
	_machine.play_result(2, false)
	var pitch := _audio.pitch_scale
	var stream := _audio.stream
	_machine.play_result(2, true)
	_machine.play_result(1, false)
	assert_eq(_audio.pitch_scale, pitch)
	assert_same(_audio.stream, stream)
	assert_eq(_audio.volume_db, -14.0)


func test_win_after_loss_restores_original_sound_pitch_and_volume() -> void:
	_machine.play_result(1, false)
	_machine.play_result(2, true)
	assert_same(_audio.stream, _machine._win_sound)
	assert_eq(_audio.pitch_scale, 1.0)
	assert_eq(_audio.volume_db, 0.0)


func test_loss_only_plays_when_final_reel_stops() -> void:
	_machine._begin_spin(1, "Alice", [0, 1, 2], 0)
	_machine._advance(1.21)
	assert_null(_audio.stream)
	_machine._advance(0.9)
	assert_null(_audio.stream)
	_machine._advance(0.9)
	assert_same(_audio.stream, _machine._lose_sound)
	assert_eq(_machine._last_sound_spin, 1)


func test_late_snapshot_is_silent_and_session_change_stops_audio() -> void:
	_machine.state = {
		"spin": 9,
		"spinning": false,
		"stopped": 3,
		"reels": [0, 1, 2],
		"won": false,
		"payout": 0,
		"operator": "Alice",
		"message": ""
	}
	_machine.get_node("View")._process(0.016)
	assert_null(_audio.stream, "Replicated results do not trigger audio")
	assert_eq(_machine._last_sound_spin, 0)
	_machine.play_result(10, false)
	_machine._on_mode_changed(Network.Mode.OFFLINE)
	assert_false(_audio.playing)
	assert_eq(_machine._last_sound_spin, 0)
	_machine.play_result(1, true)
	assert_eq(_audio.pitch_scale, 1.0)
	assert_eq(_audio.volume_db, 0.0)
