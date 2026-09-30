class_name ProceduralLiftAudio
extends Node3D
## Cosmetic playback follows replicated lift phases; loops travel with the cab.

const SYNTH := preload("res://features/parking_garage/procedural_audio.gd")
static var _motor_stream: AudioStreamWAV
static var _door_stream: AudioStreamWAV
var motor: AudioStreamPlayer3D
var doors: AudioStreamPlayer3D
var _phase := -1
var _motor_gain := 0.0


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	if _motor_stream == null:
		_motor_stream = SYNTH.hum_loop(48, 1974)
		_door_stream = SYNTH.hum_loop(120, 1964)
	motor = _voice(_motor_stream, -18)
	doors = _voice(_door_stream, -25)


func _voice(stream: AudioStream, volume: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.bus = GameAudio.BUS
	voice.volume_db = volume
	voice.unit_size = 3
	voice.max_distance = 18
	add_child(voice)
	return voice


func initialize(phase: int) -> void:
	_phase = phase
	_motor_gain = 0
	if motor != null:
		motor.stop()
		doors.stop()


func update(phase: int, delta: float) -> void:
	if motor == null:
		return
	var moving := phase == ProceduralMovingLift.Phase.MOVING
	var sliding := phase in [ProceduralMovingLift.Phase.CLOSING, ProceduralMovingLift.Phase.OPENING]
	if _phase != -1 and phase != _phase:
		if phase == ProceduralMovingLift.Phase.CLOSING:
			GameAudio.play_at(self, &"door_unlock", global_position)
		elif phase == ProceduralMovingLift.Phase.OPENING:
			if _phase == ProceduralMovingLift.Phase.MOVING:
				GameAudio.play_at(self, &"elevator_ding", global_position)
		elif phase == ProceduralMovingLift.Phase.DOCKED:
			GameAudio.play_at(self, &"door_locked", global_position)
	_phase = phase
	_motor_gain = move_toward(_motor_gain, 1.0 if moving else 0.0, delta / .25)
	motor.volume_db = -18 + linear_to_db(maxf(_motor_gain, .001))
	if _motor_gain > 0 and not motor.playing:
		motor.play()
	elif _motor_gain == 0:
		motor.stop()
	if sliding and not doors.playing:
		doors.play()
	elif not sliding:
		doors.stop()
