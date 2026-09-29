class_name KaabaChant
## Synthesizes a short, melismatic "Allahu akbar" style takbir phrase in the Hijaz
## maqam, sung by a vibrato voice with a vowel-like harmonic mix. It is generated at
## runtime so the feature ships no audio asset. Pure: same call, same bytes.

const MIX_RATE := 22050
## D4 Hijaz: D, Eb, F#, G, A. Each note is [frequency Hz, seconds].
const PHRASE: Array[Vector2] = [
	Vector2(293.66, 0.55),
	Vector2(311.13, 0.3),
	Vector2(369.99, 0.9),
	Vector2(392.0, 0.35),
	Vector2(369.99, 0.35),
	Vector2(311.13, 0.4),
	Vector2(293.66, 1.1),
	Vector2(0.0, 0.3),
	Vector2(369.99, 0.45),
	Vector2(392.0, 0.3),
	Vector2(440.0, 1.0),
	Vector2(392.0, 0.35),
	Vector2(369.99, 0.35),
	Vector2(311.13, 0.35),
	Vector2(293.66, 1.4),
]
## Relative strength of harmonics 1..6, loosely an open "ah" vowel.
const HARMONICS: Array[float] = [1.0, 0.7, 0.55, 0.3, 0.18, 0.1]


static func duration_s() -> float:
	var total := 0.0
	for note: Vector2 in PHRASE:
		total += note.y
	return total


static func takbir() -> AudioStreamWAV:
	var sample_count := int(duration_s() * MIX_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	var freq := PHRASE[0].x
	var index := 0
	var note_start := 0.0
	var norm := 0.0
	for weight: float in HARMONICS:
		norm += weight
	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		while index < PHRASE.size() - 1 and t >= note_start + PHRASE[index].y:
			note_start += PHRASE[index].y
			index += 1
		var target := PHRASE[index].x
		var local := t - note_start
		var sample := 0.0
		if target > 0.0:
			# Glide into each note, as a voice slides between them.
			freq = target if freq <= 0.0 else lerpf(freq, target, 0.004)
			var vibrato := 1.0 + 0.012 * sin(TAU * 5.5 * t) * clampf(local * 3.0, 0.0, 1.0)
			phase += TAU * freq * vibrato / float(MIX_RATE)
			for h: int in HARMONICS.size():
				sample += sin(phase * float(h + 1)) * HARMONICS[h]
			var attack := clampf(local / 0.05, 0.0, 1.0)
			var release := clampf((PHRASE[index].y - local) / 0.08, 0.0, 1.0)
			sample *= 0.5 * attack * release / norm
		else:
			freq = 0.0
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
