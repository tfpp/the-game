extends GutTest

const AUDIO := preload("res://features/procedural_rooms/lift_audio.gd")
var cues: Array[StringName] = []


func test_audio_follows_cab_phases_stops_and_does_not_replay_arrival() -> void:
	var service := GameAudio.new()
	add_child_autofree(service)
	service.sound_started.connect(
		func(cue: StringName, positional: bool, _at: Vector3) -> void:
			assert_true(positional)
			cues.append(cue)
	)
	var cab := Node3D.new()
	add_child_autofree(cab)
	var audio := AUDIO.new()
	cab.add_child(audio)
	audio.initialize(ProceduralMovingLift.Phase.DOCKED)
	audio.update(ProceduralMovingLift.Phase.CLOSING, .1)
	assert_true(audio.doors.playing)
	assert_eq(cues, [&"door_unlock"])
	audio.update(ProceduralMovingLift.Phase.MOVING, .3)
	assert_true(audio.motor.playing)
	assert_false(audio.doors.playing)
	assert_eq(audio.motor.bus, GameAudio.BUS)
	cab.position = Vector3(0, 12, 0)
	assert_eq(audio.motor.global_position.y, 12.0)
	audio.update(ProceduralMovingLift.Phase.OPENING, .3)
	assert_false(audio.motor.playing)
	assert_true(audio.doors.playing)
	assert_eq(cues.count(&"elevator_ding"), 1)
	audio.update(ProceduralMovingLift.Phase.OPENING, .1)
	assert_eq(cues.count(&"elevator_ding"), 1)
	audio.update(ProceduralMovingLift.Phase.DOCKED, .1)
	assert_false(audio.doors.playing)
	var count := cues.size()
	audio.initialize(ProceduralMovingLift.Phase.OPENING)
	audio.update(ProceduralMovingLift.Phase.OPENING, .1)
	assert_eq(cues.size(), count, "Late join restores motion without replaying arrival")
	audio.initialize(ProceduralMovingLift.Phase.MOVING)
	audio.update(ProceduralMovingLift.Phase.MOVING, .3)
	assert_true(audio.motor.playing)
	audio.initialize(ProceduralMovingLift.Phase.DOCKED)
	assert_false(audio.motor.playing)
	assert_false(audio.doors.playing)


func test_dedicated_server_creates_no_audio_voices() -> void:
	var original := Network.mode
	Network.mode = Network.Mode.SERVER
	var audio := AUDIO.new()
	add_child_autofree(audio)
	Network.mode = original
	audio.update(ProceduralMovingLift.Phase.MOVING, .3)
	assert_null(audio.motor)
	assert_null(audio.doors)
	assert_eq(audio.get_child_count(), 0)
