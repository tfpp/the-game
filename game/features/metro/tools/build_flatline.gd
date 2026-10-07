extends SceneTree
## Original heart-monitor "beep, then flatline" for players struck by a metro train.
## A synthesized homage to the shooter-classic death cue: no sampled game audio.
## Rebuild with `godot --headless --path game -s res://features/metro/tools/build_flatline.gd`.

const RATE := 11025
const PITCH := 1046.5
const BEEP := Vector2(0.0, 0.09)
const FLAT := Vector2(0.30, 2.15)
const RELEASE := 0.45


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/metro/audio")
	# RIFF chunks are word-aligned; an odd 8-bit data chunk trips the importer.
	var count := int((FLAT.y + 0.05) * RATE)
	count -= count % 2
	var pcm := PackedByteArray()
	pcm.resize(count)
	for sample: int in count:
		var t := float(sample) / RATE
		var phase := TAU * PITCH * t
		# Soft-edged square: the bright, slightly buzzy tone of an old suit monitor.
		var wave := 0.78 * sin(phase) + 0.17 * sin(phase * 3.0) + 0.05 * sin(phase * 5.0)
		var level := _envelope(t, BEEP, 0.012) + _envelope(t, FLAT, RELEASE)
		# AudioStreamWAV keeps 8-bit samples signed; save_to_wav writes unsigned PCM.
		pcm.encode_s8(sample, clampi(int(wave * level * 92.0), -128, 127))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_8_BITS
	audio.mix_rate = RATE
	audio.data = pcm
	audio.save_to_wav("res://assets/metro/audio/flatline.wav")
	quit()


## Short attack, held tone, then a fade over `release` seconds before `span.y`.
static func _envelope(t: float, span: Vector2, release: float) -> float:
	if t < span.x or t > span.y:
		return 0.0
	var attack := clampf((t - span.x) / 0.006, 0.0, 1.0)
	return attack * clampf((span.y - t) / release, 0.0, 1.0)
