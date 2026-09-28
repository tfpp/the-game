class_name FrogRibbit
extends RefCounted
## Synthesizes the frogs feature's "ribbit" cue in code instead of shipping a new
## binary asset (see assets/kenney in game/AGENTS.md): two short, buzzy,
## downward-sweeping pulses in the classic "rib-bit" cadence.

const MIX_RATE := 22050
## (start_hz, end_hz, duration_s) per syllable, "rib" then "bit".
const SYLLABLES: Array[Vector3] = [Vector3(260.0, 150.0, 0.08), Vector3(210.0, 90.0, 0.13)]
const GAP_S := 0.03

static var _cached: AudioStreamWAV


## Built once; every frog interaction shares the same generated clip.
static func stream() -> AudioStreamWAV:
	if _cached == null:
		_cached = _build()
	return _cached


static func _build() -> AudioStreamWAV:
	var samples := PackedByteArray()
	for index: int in SYLLABLES.size():
		var syllable := SYLLABLES[index]
		_append_croak(samples, syllable.x, syllable.y, syllable.z)
		if index < SYLLABLES.size() - 1:
			_append_silence(samples, GAP_S)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = samples
	return wav


## A buzzy pulse: a square wave (for the croak's rasp) sweeping from `start_hz` to
## `end_hz`, shaped by a sine envelope so it fades in and out without clicking.
static func _append_croak(
	samples: PackedByteArray, start_hz: float, end_hz: float, duration_s: float
) -> void:
	var count := int(duration_s * MIX_RATE)
	var phase := 0.0
	for i: int in count:
		var t := float(i) / count
		phase += lerpf(start_hz, end_hz, t) / MIX_RATE
		var tone := signf(sin(phase * TAU))
		var envelope := sin(t * PI)
		_append_sample(samples, tone * envelope)


static func _append_silence(samples: PackedByteArray, duration_s: float) -> void:
	for _i: int in int(duration_s * MIX_RATE):
		_append_sample(samples, 0.0)


static func _append_sample(samples: PackedByteArray, value: float) -> void:
	var sample := int(clampf(value, -1.0, 1.0) * 32767.0)
	samples.append(sample & 0xFF)
	samples.append((sample >> 8) & 0xFF)
