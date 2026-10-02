extends Node3D
## Local, bounded presentation. Snapshots drive machinery; reliable results drive wins.

const MOTOR := preload("res://assets/slot_machine/audio/motor.wav")
const STOP := preload("res://assets/slot_machine/audio/stop.wav")
const LEVER := preload("res://assets/slot_machine/audio/lever.wav")
const PAYOUT := preload("res://assets/slot_machine/audio/payout.wav")
const AMBER := Color("ffd28a")
const GREEN := Color("7febba")
var motor: AudioStreamPlayer3D
var mechanism: AudioStreamPlayer3D
var payout: AudioStreamPlayer3D
var _candle: MeshInstance3D
var _button: MeshInstance3D
var _wash: OmniLight3D
var _win_left := 0.0
var _last_spin := -1
var _stopped := 3
var _finished_spin := 0
var _loop: AudioStreamWAV
var _enabled := true


func _ready() -> void:
	_enabled = Network.mode != Network.Mode.SERVER and not Network.has_flag("server")
	if not _enabled:
		return
	_loop = MOTOR.duplicate() as AudioStreamWAV
	_loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_loop.loop_begin = 0
	_loop.loop_end = _loop.data.size() / 2
	motor = _voice(_loop, -17)
	mechanism = _voice(STOP, -9)
	mechanism.max_polyphony = 3
	payout = _voice(PAYOUT, -12)
	_build_lights()
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: reset())


func update(snapshot: Dictionary, delta: float) -> void:
	if not _enabled:
		return
	var spin := int(snapshot["spin"])
	var stopped := int(snapshot["stopped"])
	var spinning := bool(snapshot["spinning"])
	var camera := get_viewport().get_camera_3d()
	var nearby := (
		camera == null or camera.global_position.distance_squared_to(global_position) < 625
	)
	# First snapshot establishes a baseline. Never replay historical stops or starts.
	if _last_spin >= 0 and nearby:
		if spin > _last_spin and spinning:
			mechanism.stream = LEVER
			mechanism.pitch_scale = 1
			mechanism.play()
			_win_left = 0
		elif spin == _last_spin and stopped > _stopped:
			mechanism.stream = STOP
			mechanism.pitch_scale = 0.92 + stopped * .06
			mechanism.play()
	_last_spin = spin
	_stopped = stopped
	if spinning and nearby and spin > _finished_spin:
		motor.volume_db = -17 - stopped * 2
		motor.pitch_scale = 1 - stopped * .07
		if not motor.playing:
			motor.play()
	else:
		motor.stop()
	_win_left = maxf(0, _win_left - delta)
	if not nearby:
		_wash.hide()
		return
	var winning := _win_left > 0
	_candle.material_override.albedo_color = (
		GREEN if winning else AMBER if spinning else Color("ddcfad")
	)
	_button.material_override.albedo_color = AMBER if spinning else GREEN
	_wash.visible = (
		camera != null and camera.global_position.distance_squared_to(global_position) < 100
	)
	_wash.light_color = GREEN if winning else AMBER
	_wash.light_energy = .4 if winning else .2 if spinning else .08


func result(won: bool, spin: int) -> void:
	if not _enabled:
		return
	_finished_spin = spin
	motor.stop()
	if won:
		_win_left = 3.0
		var camera := get_viewport().get_camera_3d()
		if camera == null or camera.global_position.distance_squared_to(global_position) < 625:
			payout.play()


func reset() -> void:
	_last_spin = -1
	_finished_spin = 0
	_stopped = 3
	_win_left = 0
	if motor != null:
		motor.stop()
		mechanism.stop()
		payout.stop()
		_candle.material_override.albedo_color = Color("60432c")
		_wash.hide()


func _voice(stream: AudioStream, gain: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.bus = GameAudio.BUS
	voice.position = Vector3(0, 1.65, .5)
	voice.volume_db = gain
	voice.unit_size = 2
	voice.max_distance = 18
	add_child(voice)
	return voice


func _build_lights() -> void:
	_candle = MeshInstance3D.new()
	var lens := CylinderMesh.new()
	lens.top_radius = .067
	lens.bottom_radius = .067
	lens.height = .094
	lens.radial_segments = 12
	_candle.mesh = lens
	_candle.position = Vector3(0, 2.935, -.10)
	_candle.material_override = _glow(Color("efddb1"))
	add_child(_candle)
	var lower := _candle.duplicate() as MeshInstance3D
	lower.position.y = 2.831
	lower.material_override = _glow(Color("881d18"))
	add_child(lower)
	for i: int in 5:
		var button := MeshInstance3D.new()
		var face := BoxMesh.new()
		face.size = Vector3(.122, .081, .018)
		button.mesh = face
		button.transform = Transform3D(Basis(Vector3.RIGHT, -.58), Vector3(0, 1.345, .615))
		button.position += button.basis * Vector3(-.48 + i * .23, 0, .111)
		button.material_override = _glow(GREEN if i == 4 else Color("e8ba80"))
		add_child(button)
		if i == 4:
			_button = button
	_wash = OmniLight3D.new()
	_wash.position = Vector3(0, 2.32, .62)
	_wash.omni_range = 2.6
	_wash.shadow_enabled = false
	add_child(_wash)


func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
