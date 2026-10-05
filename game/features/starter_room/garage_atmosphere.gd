extends Node3D
## Quiet scoped workshop sound, localized light dips and shutter motor audio.

const HUM := preload("res://assets/starter_room/workshop_hum.res")
const RADIO := preload("res://assets/starter_room/workshop_radio.res")
const MOTOR := preload("res://assets/starter_room/roller_motor.res")
var _hum: AudioStreamPlayer3D
var _radio: AudioStreamPlayer3D
var _motor: AudioStreamPlayer3D
var _active := false
var _clock := 0.0
var _next_dip := 19.0
var _dip := 0.0
@onready var _door: GarageRollerDoor = get_parent().get_node("RollerDoor")


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER:
		set_process(false)
		return
	_hum = _voice("FluorescentHum", HUM, Vector3(3, 4.2, -3), -29.0)
	_radio = _voice("WorkshopRadio", RADIO, Vector3(-4, 1.1, -8.1), -14.0)
	_motor = _voice("ShutterMotor", MOTOR, Vector3(3, 3.4, -8.7), -8.0)


func _voice(title: String, stream: AudioStream, at: Vector3, volume: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = title
	voice.stream = stream
	voice.position = at
	voice.bus = GameAudio.BUS
	voice.volume_db = volume
	voice.unit_size = 3.0
	voice.max_distance = 22.0
	add_child(voice)
	return voice


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var room := get_parent() as StreamedRoom
	var inside := (
		is_instance_valid(camera) and room.bounds.has_point(room.to_local(camera.global_position))
	)
	if inside != _active:
		_active = inside
		if inside:
			_hum.play()
			_radio.play()
		else:
			_hum.stop()
			_radio.stop()
			_motor.stop()
			$BayLight.light_energy = 2.0
	if not _active:
		return
	if _door.moving() and not _motor.playing:
		_motor.play()
	elif not _door.moving():
		_motor.stop()
	_clock += delta
	if _clock > _next_dip:
		_dip = .18
		_next_dip = _clock + randf_range(16.0, 31.0)
	_dip = maxf(0, _dip - delta)
	$BayLight.light_energy = 1.5 if _dip > 0 else 2.0
	# Opening the shutter admits more of the existing outdoor storm recording.
	var storm := $AlleyView.get_node_or_null("AlleyStormAmbience") as AudioStreamPlayer3D
	if storm != null:
		storm.volume_db = lerpf(-18.0, -11.0, _door.net_height / GarageRollerDoor.HEIGHT)
