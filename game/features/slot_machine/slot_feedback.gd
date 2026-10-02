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
var _bulbs: MultiMeshInstance3D
var _candle: MeshInstance3D
var _button: MeshInstance3D
var _wash: OmniLight3D
var _phase := 0.0
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
	_phase += delta
	_win_left = maxf(0, _win_left - delta)
	if not nearby:
		_wash.hide()
		return
	var winning := _win_left > 0
	for i: int in _bulbs.multimesh.instance_count:
		var chase := (i + int(_phase * (9 if spinning else 2))) % 4 == 0
		var gain := 1.0 if chase else .55
		if winning:
			gain = .7 + .3 * sin(_phase * 6 + i * .45)
		_bulbs.multimesh.set_instance_color(i, (GREEN if winning else AMBER) * gain)
	_candle.material_override.albedo_color = (
		GREEN if winning else AMBER if spinning else Color("60432c")
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
	var bulb := SphereMesh.new()
	bulb.radius = .025
	bulb.height = .05
	bulb.radial_segments = 8
	bulb.rings = 3
	var material := _glow(AMBER)
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	bulb.material = material
	_bulbs = MultiMeshInstance3D.new()
	_bulbs.name = "MarqueeBulbs"
	_bulbs.multimesh = MultiMesh.new()
	_bulbs.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_bulbs.multimesh.use_colors = true
	_bulbs.multimesh.mesh = bulb
	_bulbs.multimesh.instance_count = 24
	_bulbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i: int in 24:
		var at := Vector3(-.88 + (i % 10) * .1955, 2.685 if i < 10 else 2.29, .585)
		if i >= 20:
			at = Vector3(-.987 if i < 22 else .987, 2.36 + (i % 2) * .16, .585)
		_bulbs.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		_bulbs.multimesh.set_instance_color(i, AMBER * .5)
	add_child(_bulbs)
	_candle = MeshInstance3D.new()
	var lens := CylinderMesh.new()
	lens.top_radius = .095
	lens.bottom_radius = .095
	lens.height = .145
	lens.radial_segments = 12
	_candle.mesh = lens
	_candle.position = Vector3(0, 2.905, 0)
	_candle.material_override = _glow(AMBER)
	add_child(_candle)
	_candle.material_override.albedo_color = Color("60432c")
	_button = MeshInstance3D.new()
	var button := CylinderMesh.new()
	button.top_radius = .047
	button.bottom_radius = .047
	button.height = .017
	button.radial_segments = 12
	_button.mesh = button
	_button.rotation.x = PI * .5
	_button.position = Vector3(.72, 1.11, .835)
	_button.material_override = _glow(GREEN)
	add_child(_button)
	var red := _button.duplicate() as MeshInstance3D
	red.position.x = -.73
	red.material_override = _glow(Color("a84932"))
	add_child(red)
	_wash = OmniLight3D.new()
	_wash.position = Vector3(0, 1.9, .9)
	_wash.omni_range = 2.6
	_wash.shadow_enabled = false
	add_child(_wash)


func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
