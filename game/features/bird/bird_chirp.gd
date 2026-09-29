class_name BirdChirp
extends RefCounted
## Synthesizes a bright, multi-tone bird chirp in code.

const MIX_RATE := 22050
const CHIRPS: Array[Vector3] = [
	Vector3(2200.0, 3100.0, 0.06),
	Vector3(3300.0, 2600.0, 0.08),
]
const GAP_S := 0.02

static var _cached: AudioStreamWAV


static func stream() -> AudioStreamWAV:
	if _cached == null:
		_cached = _build()
	return _cached


static func _build() -> AudioStreamWAV:
	var samples := PackedByteArray()
	for index: int in CHIRPS.size():
		var chirp := CHIRPS[index]
		_append_chirp(samples, chirp.x, chirp.y, chirp.z)
		if index < CHIRPS.size() - 1:
			_append_silence(samples, GAP_S)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = samples
	return wav


static func _append_chirp(
	samples: PackedByteArray, start_hz: float, end_hz: float, duration_s: float
) -> void:
	var count := int(duration_s * MIX_RATE)
	var phase := 0.0
	for i: int in count:
		var t := float(i) / float(count)
		phase += lerpf(start_hz, end_hz, t) / MIX_RATE
		var tone := sin(phase * TAU)
		var envelope := sin(t * PI)
		_append_sample(samples, tone * envelope * 0.4)


static func _append_silence(samples: PackedByteArray, duration_s: float) -> void:
	for _i: int in int(duration_s * MIX_RATE):
		_append_sample(samples, 0.0)


static func _append_sample(samples: PackedByteArray, value: float) -> void:
	var sample := int(clampf(value, -1.0, 1.0) * 32767.0)
	samples.append(sample & 0xFF)
	samples.append((sample >> 8) & 0xFF)
