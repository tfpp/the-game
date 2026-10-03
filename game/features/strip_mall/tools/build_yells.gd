extends SceneTree
## Original wordless arcade yells. No sampled TV dialogue or impersonated voices.
const RATE := 22050


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/strip_mall/audio")
	for character: int in 2:
		var pcm := PackedByteArray()
		pcm.resize(RATE * 2)
		var phase := 0.0
		for sample: int in RATE:
			var t := float(sample) / RATE
			var envelope := sin(PI * t) * minf(t * 30.0, 1.0)
			var pitch := (155.0 if character == 0 else 205.0) + 35.0 * sin(t * 9.0)
			phase += TAU * pitch / RATE
			# Vowel-like harmonic stacks with three syllabic pulses.
			var syllable := .35 + .65 * absf(sin(t * PI * 3.0))
			var wave := .55 * sin(phase) + .25 * sin(phase * 3) + .12 * sin(phase * 5)
			var value := int(wave * envelope * syllable * 21000.0)
			pcm.encode_s16(sample * 2, value)
		var audio := AudioStreamWAV.new()
		audio.format = AudioStreamWAV.FORMAT_16_BITS
		audio.mix_rate = RATE
		audio.data = pcm
		audio.save_to_wav(
			(
				"res://assets/strip_mall/audio/%s.wav"
				% ("wok_yell" if character == 0 else "sushi_yell")
			)
		)
	quit()
