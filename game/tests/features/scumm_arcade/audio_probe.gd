extends Node3D
## Capture the actual cabinet generator after spatial mixing, using demo PCM.

var _cabinet: ScummArcadeCabinet
var _camera: Camera3D
var _capture := AudioEffectCapture.new()
var _pcm: PackedByteArray
var _pixels := PackedByteArray()
var _elapsed := 0.0


func _ready() -> void:
	_pcm = FileAccess.get_file_as_bytes(str(Network.args["arcade-pcm"]))
	assert(_pcm.size() == 441 * 4)
	_pixels.resize(320 * 200 * 4)
	_cabinet = preload("res://features/scumm_arcade/cabinet.tscn").instantiate()
	add_child(_cabinet)
	_cabinet.set_process(false)
	_cabinet.state["tick"] = 1
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, &"ArcadeTest")
	AudioServer.add_bus_effect(bus, _capture)
	_cabinet._audio.bus = &"ArcadeTest"
	_run()


func _process(delta: float) -> void:
	_elapsed += delta
	while _elapsed >= 0.02:
		_elapsed -= 0.02
		_cabinet._frame_ready(1, 0, _pixels, _pcm)


func _measure(offset: Vector3) -> Vector2:
	_camera.global_position = _cabinet._audio.global_position + offset
	await get_tree().create_timer(0.4).timeout
	_capture.clear_buffer()
	await get_tree().create_timer(0.3).timeout
	var samples := _capture.get_buffer(_capture.get_frames_available())
	assert(not samples.is_empty(), "Run with a real audio driver, not Dummy")
	var power := Vector2.ZERO
	for sample: Vector2 in samples:
		power += sample * sample
	power /= samples.size()
	return Vector2(sqrt(power.x), sqrt(power.y))


func _run() -> void:
	var levels: Array[float] = []
	for distance: float in [1.0, 2.5, 4.5, 5.0, 6.0, 1.0]:
		var stereo: Vector2 = await _measure(Vector3(0, 0, distance))
		levels.append(stereo.length())
		print("AUDIO_DISTANCE ", distance, " RMS ", stereo.length())
	assert(levels[0] > 0.0001, "Real demo audio must reach the mixer")
	assert(levels[1] < levels[0] and levels[2] < levels[1], "Volume must fall with distance")
	assert(levels[3] < 0.000001 and levels[4] < 0.000001, "Silent at and beyond 5 m")
	assert(levels[5] > levels[0] * 0.8, "Playback resumes when walking back")
	var left: Vector2 = await _measure(Vector3(2, 0, 0))
	var right: Vector2 = await _measure(Vector3(-2, 0, 0))
	assert(left.x > left.y * 1.2 and right.y > right.x * 1.2, "Sound must pan spatially")
	print("PASS: audible demo PCM, distance fade, silence at 5m, return and stereo panning")
	set_process(false)
	_cabinet._audio.stop()
	_cabinet._playback = null
	AudioServer.remove_bus(AudioServer.get_bus_index(&"ArcadeTest"))
	_cabinet.queue_free()
	await get_tree().process_frame
	get_tree().quit()
