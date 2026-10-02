class_name MariachiSynth
## Renders a `MariachiSongs.score()` into a seamless looping mono clip: wavetable
## trumpets and violin with tonguing, scoops and vibrato, decaying plucked vihuela
## and guitarrón strings, and a small room reverb. Notes and reverb tails that run
## past the end wrap round to the start, so the clip loops without a seam.
## Pure and deterministic: the same song always renders the same samples. Used
## offline by `tools/bake_songs.gd`; the game only plays the baked clips.

const MIX_RATE := 22050
const TABLE_SIZE := 1024
const PEAK := 0.89

## Relative harmonic strengths (1st, 2nd, ...) for each timbre's wavetables.
const BRASS_BRIGHT: Array[float] = [1.0, 0.9, 0.78, 0.64, 0.52, 0.4, 0.3, 0.22, 0.15, 0.1, 0.07]
const BRASS_MELLOW: Array[float] = [1.0, 0.55, 0.3, 0.16, 0.08, 0.04]
const STRINGS_BOWED: Array[float] = [1.0, 0.6, 0.48, 0.42, 0.3, 0.22, 0.17, 0.13, 0.1, 0.08, 0.06]
const PLUCK_BRIGHT: Array[float] = [1.0, 0.75, 0.55, 0.45, 0.32, 0.25, 0.16, 0.12, 0.08]
const PLUCK_DARK: Array[float] = [1.0, 0.35, 0.12, 0.05]
const BASS_BRIGHT: Array[float] = [1.0, 0.85, 0.55, 0.32, 0.2, 0.1]
const BASS_DARK: Array[float] = [1.0, 0.3, 0.08]

## Per-voice level before normalization.
const LEVELS: Dictionary[int, float] = {
	MariachiSongs.Voice.TRUMPET: 0.36,
	MariachiSongs.Voice.VIOLIN: 0.3,
	MariachiSongs.Voice.VIHUELA: 0.11,
	MariachiSongs.Voice.GUITARRON: 0.3,
}
## Comb delays (seconds) and feedback for the room reverb, and its wet level.
const REVERB_DELAYS: Array[float] = [0.0297, 0.0371, 0.0411, 0.0437]
const REVERB_FEEDBACK := 0.62
const REVERB_WET := 0.16


## The whole song as a looping 16-bit clip.
static func render_stream(song: int) -> AudioStreamWAV:
	return to_stream(render(song))


## Float samples for one pass through `song`. `max_seconds` truncates the render
## (tails are then cut rather than wrapped), for quick checks.
static func render(song: int, max_seconds: float = INF) -> PackedFloat32Array:
	var truncated := minf(MariachiSongs.duration(song), max_seconds) < MariachiSongs.duration(song)
	var total := int(round(minf(MariachiSongs.duration(song), max_seconds) * MIX_RATE))
	var mix := PackedFloat32Array()
	mix.resize(total)
	var tables := {
		"brass_bright": _table(BRASS_BRIGHT),
		"brass_mellow": _table(BRASS_MELLOW),
		"bowed": _table(STRINGS_BOWED),
		"pluck_bright": _table(PLUCK_BRIGHT),
		"pluck_dark": _table(PLUCK_DARK),
		"bass_bright": _table(BASS_BRIGHT),
		"bass_dark": _table(BASS_DARK),
	}
	for note: Dictionary in MariachiSongs.score(song):
		if float(note["t"]) * MIX_RATE < total:
			_add_note(mix, note, tables, not truncated)
	_reverb(mix, not truncated)
	_normalize(mix)
	return mix


static func to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	return stream


static func frequency(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


static func _add_note(
	mix: PackedFloat32Array, note: Dictionary, tables: Dictionary, wrap: bool
) -> void:
	var voice: int = note["voice"]
	var gate := float(note["len"])
	var gain := float(note["gain"]) * LEVELS[voice]
	var base := frequency(int(note["midi"]))
	var release := 0.05
	var bright: PackedFloat32Array
	var dark: PackedFloat32Array
	match voice:
		MariachiSongs.Voice.TRUMPET:
			gate *= 0.86
			bright = tables["brass_bright"]
			dark = tables["brass_mellow"]
			# The second trumpet sits a few cents sharp so the pair beats a little.
			if float(note["gain"]) < 1.0:
				base *= 1.003
		MariachiSongs.Voice.VIOLIN:
			gate *= 0.96
			release = 0.09
			bright = tables["bowed"]
			dark = tables["bowed"]
		MariachiSongs.Voice.VIHUELA:
			release = 0.03
			bright = tables["pluck_bright"]
			dark = tables["pluck_dark"]
		_:
			release = 0.06
			bright = tables["bass_bright"]
			dark = tables["bass_dark"]
	var start := int(round(float(note["t"]) * MIX_RATE))
	var count := int((gate + release) * MIX_RATE)
	var phase := 0.0
	var size := mix.size()
	for i: int in count:
		var index := start + i
		if index >= size:
			if not wrap:
				break
			index -= size
		var local := float(i) / MIX_RATE
		var shape := _shape(voice, local, gate, release)
		var freq := base * _pitch(voice, local)
		phase = fposmod(phase + freq / MIX_RATE, 1.0)
		var position := phase * TABLE_SIZE
		var at := int(position)
		var frac := position - at
		var next := (at + 1) % TABLE_SIZE
		var b := lerpf(bright[at], bright[next], frac)
		var d := lerpf(dark[at], dark[next], frac)
		mix[index] += lerpf(d, b, shape.y) * shape.x * gain


## [amplitude, brightness] envelope for a voice `local` seconds into a note.
static func _shape(voice: int, local: float, gate: float, release: float) -> Vector2:
	var fade := clampf((gate + release - local) / release, 0.0, 1.0)
	match voice:
		MariachiSongs.Voice.TRUMPET:
			var attack := clampf(local / 0.022, 0.0, 1.0)
			var body := 0.82 + 0.18 * exp(-local * 9.0)
			return Vector2(attack * body * fade, clampf(0.55 + 0.45 * exp(-local * 7.0), 0.0, 1.0))
		MariachiSongs.Voice.VIOLIN:
			var attack := clampf(local / 0.06, 0.0, 1.0)
			return Vector2(attack * fade, 1.0)
		MariachiSongs.Voice.VIHUELA:
			return Vector2(exp(-local * 6.0) * fade, exp(-local * 9.0))
	return Vector2(exp(-local * 3.2) * clampf(local / 0.004, 0.0, 1.0) * fade, exp(-local * 6.0))


## Pitch multiplier: trumpets scoop up into each note and both melody voices sing
## with vibrato on held notes.
static func _pitch(voice: int, local: float) -> float:
	match voice:
		MariachiSongs.Voice.TRUMPET:
			var vibrato := 0.0045 * sin(TAU * 5.6 * local) * clampf((local - 0.2) * 4.0, 0.0, 1.0)
			return 1.0 - 0.018 * exp(-local * 45.0) + vibrato
		MariachiSongs.Voice.VIOLIN:
			return 1.0 + 0.004 * sin(TAU * 6.1 * local) * clampf(local * 6.0, 0.0, 1.0)
	return 1.0


## A single-cycle wavetable from harmonic strengths, peak-normalized.
static func _table(harmonics: Array[float]) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(TABLE_SIZE)
	var peak := 0.0
	for i: int in TABLE_SIZE:
		var x := TAU * i / TABLE_SIZE
		var value := 0.0
		for h: int in harmonics.size():
			value += harmonics[h] * sin(x * (h + 1))
		table[i] = value
		peak = maxf(peak, absf(value))
	for i: int in TABLE_SIZE:
		table[i] /= peak
	return table


## Parallel feedback combs. The buffer is run twice when looping so the room's
## tail from the end of the song carries into its start.
static func _reverb(mix: PackedFloat32Array, wrap: bool) -> void:
	var size := mix.size()
	if size == 0:
		return
	var dry := mix.duplicate()
	var wet := PackedFloat32Array()
	wet.resize(size)
	for delay_s: float in REVERB_DELAYS:
		var delay := int(delay_s * MIX_RATE)
		var line := PackedFloat32Array()
		line.resize(delay)
		var cursor := 0
		var low := 0.0
		for lap: int in 2 if wrap else 1:
			for i: int in size:
				var out := line[cursor]
				low += (out - low) * 0.45
				line[cursor] = dry[i] + low * REVERB_FEEDBACK
				cursor = (cursor + 1) % delay
				if lap == (1 if wrap else 0):
					wet[i] += out
	for i: int in size:
		mix[i] = dry[i] + wet[i] * REVERB_WET / REVERB_DELAYS.size()


static func _normalize(mix: PackedFloat32Array) -> void:
	var peak := 0.0
	for sample: float in mix:
		peak = maxf(peak, absf(sample))
	if peak <= 0.0:
		return
	var scale := PEAK / peak
	for i: int in mix.size():
		mix[i] *= scale
