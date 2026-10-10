class_name DiscoBeat
extends RefCounted
## Builds the party's one-bar four-on-the-floor loop at runtime: kick on every
## beat, clap on two and four, open hi-hats on the off-beats and an octave bass.
## No audio file ships; the bar is synthesized once, the first time it plays.

const MIX_RATE := 22050
const BPM := 120.0
const BEATS := 4
## A1 / A2 octave bass, the disco staple.
const BASS_HZ := 55.0


static func bar_frames() -> int:
	return int(round(MIX_RATE * 60.0 / BPM * BEATS))


static func build() -> AudioStreamWAV:
	var frames := bar_frames()
	var beat := frames / BEATS
	var eighth := beat / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var data := PackedByteArray()
	data.resize(frames * 2)
	var bass_phase := 0.0
	for i: int in frames:
		var in_beat := i % beat
		var t_beat := float(in_beat) / MIX_RATE
		var beat_index := i / beat
		var sample := 0.0
		# Kick: a falling sine sweep with a fast decay.
		var kick_hz := 50.0 + 90.0 * exp(-t_beat * 30.0)
		sample += sin(TAU * kick_hz * t_beat) * exp(-t_beat * 9.0) * 0.55
		# Clap on beats two and four.
		if beat_index % 2 == 1:
			sample += rng.randf_range(-1.0, 1.0) * exp(-t_beat * 28.0) * 0.22
		# Open hi-hat on every off-beat.
		var off := in_beat - eighth
		if off >= 0:
			sample += rng.randf_range(-1.0, 1.0) * exp(-float(off) / MIX_RATE * 22.0) * 0.12
		# Octave bass, jumping up an octave on each off-beat eighth.
		var hz := BASS_HZ * (2.0 if (i / eighth) % 2 == 1 else 1.0)
		bass_phase = fmod(bass_phase + hz / MIX_RATE, 1.0)
		var t_note := float(i % eighth) / MIX_RATE
		sample += (bass_phase * 2.0 - 1.0) * exp(-t_note * 6.0) * 0.18
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream
