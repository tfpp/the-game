class_name ProceduralAudio
## Synthesizes every ambient clip the parking garage needs at runtime (rain/wind
## bed, fluorescent hum, drips, structural creaks), so the feature ships with no
## new audio assets. Every function is a pure function of its seed: same seed,
## same bytes, which keeps it easy to unit test.

const MIX_RATE := 22050


## A loop-friendly bed of filtered noise (rain hiss) under a slow wind swell.
static func rain_and_wind_loop(seed_value: int, duration_s: float = 4.0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sample_count := int(duration_s * MIX_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var lowpassed := 0.0
	var cycles := 3.0
	for i in sample_count:
		var t := float(i) / float(sample_count)
		var noise := rng.randf_range(-1.0, 1.0)
		lowpassed += (noise - lowpassed) * 0.15
		var wind := 0.55 + 0.35 * sin(t * TAU * cycles)
		var sample := clampf(lowpassed * wind * 0.55, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 32767.0))
	return _to_stream(data, sample_count, true)


## A seamless single-cycle-aligned hum for a working or struggling fluorescent tube.
static func hum_loop(base_freq: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var duration_s := 1.0
	var sample_count := int(duration_s * MIX_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		var wave := sin(TAU * base_freq * t) * 0.55
		wave += sin(TAU * base_freq * 3.0 * t) * 0.2
		wave += rng.randf_range(-1.0, 1.0) * 0.04
		data.encode_s16(i * 2, int(clampf(wave, -1.0, 1.0) * 32767.0))
	return _to_stream(data, sample_count, true)


## A short decaying droplet "plink" for leaks and puddles.
static func drip_blip(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var duration_s := 0.3
	var sample_count := int(duration_s * MIX_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var freq := rng.randf_range(900.0, 1700.0)
	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		var envelope := exp(-t * 20.0)
		var wave := sin(TAU * freq * t * exp(-t * 5.0))
		data.encode_s16(i * 2, int(clampf(wave * envelope, -1.0, 1.0) * 32767.0))
	return _to_stream(data, sample_count, false)


## A low rumbling structural groan, for the occasional creak in the dark.
static func structural_creak(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var duration_s := 1.4
	var sample_count := int(duration_s * MIX_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var freq := rng.randf_range(45.0, 85.0)
	var lowpassed := 0.0
	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		var envelope := sin(PI * minf(t / duration_s, 1.0))
		var noise := rng.randf_range(-1.0, 1.0)
		lowpassed += (noise - lowpassed) * 0.05
		var wave := sin(TAU * freq * t) * 0.6 + lowpassed * 0.4
		data.encode_s16(i * 2, int(clampf(wave * envelope, -1.0, 1.0) * 32767.0))
	return _to_stream(data, sample_count, false)


static func _to_stream(data: PackedByteArray, sample_count: int, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample_count
	return stream
