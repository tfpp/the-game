class_name MariachiSongs
## The band's repertoire as pure data: traditional tunes and original compositions in C,
## arranged for trumpets, violin, vihuela and guitarrón. Every peer derives the
## same timings from here: the server rotates songs by `duration()`, the baking
## tool (`tools/bake_songs.gd`) renders the audio from `score()`, and the
## musicians time their strums, bowing and breaths with `lead_at()` and friends.
## Melodies are [midi, units] pairs (midi 0 is a rest); one unit is an eighth note.

enum Voice { TRUMPET, VIOLIN, VIHUELA, GUITARRON }

const NAMES: Array[String] = [
	"La Cucaracha",
	"Jarabe Tapatío",
	"Brass at the Crown",
	"Promenade Waltz",
	"Last Chip Polka",
]

## Chord pitch classes, root first.
const CHORDS: Dictionary[String, Array] = {
	"C": [0, 4, 7],
	"F": [5, 9, 0],
	"Am": [9, 0, 4],
	"G7": [7, 11, 2, 5],
	"D7": [2, 6, 9, 0],
}
## Units within a bar for each accompaniment hit. "down"/"up" are vihuela strums.
const POLKA := {"bar": 8, "bass": [0, 4], "down": [2, 6], "up": [3, 7]}
const JIG := {"bar": 6, "bass": [0, 3], "down": [1, 4], "up": [2, 5]}
const WALTZ := {"bar": 6, "bass": [0], "down": [2, 4], "up": [3, 5]}

# La Cucaracha (4/4). The verse; the closing "G G G" is the pickup into the repeat.
const CUCARACHA_A: Array[Vector2i] = [
	Vector2i(72, 3),
	Vector2i(76, 2),
	Vector2i(67, 1),
	Vector2i(67, 1),
	Vector2i(67, 1),
	Vector2i(72, 3),
	Vector2i(76, 1),
	Vector2i(0, 4),
	Vector2i(0, 1),
	Vector2i(72, 2),
	Vector2i(72, 1),
	Vector2i(71, 1),
	Vector2i(71, 1),
	Vector2i(69, 1),
	Vector2i(69, 1),
	Vector2i(67, 5),
	Vector2i(67, 1),
	Vector2i(67, 1),
	Vector2i(67, 1),
	Vector2i(71, 3),
	Vector2i(74, 2),
	Vector2i(67, 1),
	Vector2i(67, 1),
	Vector2i(67, 1),
	Vector2i(71, 3),
	Vector2i(74, 1),
	Vector2i(0, 4),
	Vector2i(0, 1),
	Vector2i(79, 2),
	Vector2i(81, 1),
	Vector2i(79, 1),
	Vector2i(77, 1),
	Vector2i(76, 1),
	Vector2i(74, 1),
	Vector2i(72, 4),
	Vector2i(0, 1),
	Vector2i(67, 1),
	Vector2i(67, 1),
	Vector2i(67, 1),
]
const CUCARACHA_CHORDS: Array[String] = ["C", "C", "C", "G7", "G7", "G7", "G7", "C"]

# Jarabe Tapatío, the Mexican Hat Dance (6/8). Section A ends with the pickup into B.
const JARABE_A: Array[Vector2i] = [
	Vector2i(79, 1),
	Vector2i(76, 1),
	Vector2i(75, 1),
	Vector2i(76, 1),
	Vector2i(72, 1),
	Vector2i(71, 1),
	Vector2i(72, 1),
	Vector2i(67, 2),
	Vector2i(0, 1),
	Vector2i(64, 1),
	Vector2i(65, 1),
	Vector2i(67, 1),
	Vector2i(69, 1),
	Vector2i(71, 1),
	Vector2i(72, 1),
	Vector2i(74, 1),
	Vector2i(76, 1),
	Vector2i(77, 1),
	Vector2i(74, 2),
	Vector2i(0, 1),
	Vector2i(77, 1),
	Vector2i(76, 1),
	Vector2i(77, 1),
	Vector2i(74, 1),
	Vector2i(73, 1),
	Vector2i(74, 1),
	Vector2i(71, 1),
	Vector2i(70, 1),
	Vector2i(71, 1),
	Vector2i(67, 2),
	Vector2i(0, 1),
	Vector2i(79, 1),
	Vector2i(77, 1),
	Vector2i(79, 1),
	Vector2i(81, 1),
	Vector2i(79, 1),
	Vector2i(77, 1),
	Vector2i(76, 1),
	Vector2i(74, 1),
	Vector2i(72, 2),
	Vector2i(0, 2),
	Vector2i(74, 1),
	Vector2i(74, 1),
]
const JARABE_A_CHORDS: Array[String] = ["C", "C", "C", "G7", "G7", "G7", "G7", "C"]
# Section B: the bouncing second strain, ending with the pickup back into A.
const JARABE_B: Array[Vector2i] = [
	Vector2i(74, 1),
	Vector2i(69, 1),
	Vector2i(69, 1),
	Vector2i(69, 1),
	Vector2i(71, 1),
	Vector2i(72, 1),
	Vector2i(72, 1),
	Vector2i(71, 2),
	Vector2i(0, 1),
	Vector2i(74, 1),
	Vector2i(74, 1),
	Vector2i(74, 1),
	Vector2i(69, 1),
	Vector2i(69, 1),
	Vector2i(69, 1),
	Vector2i(71, 1),
	Vector2i(72, 1),
	Vector2i(72, 1),
	Vector2i(71, 2),
	Vector2i(0, 1),
	Vector2i(74, 1),
	Vector2i(74, 1),
	Vector2i(74, 1),
	Vector2i(69, 1),
	Vector2i(69, 1),
	Vector2i(69, 1),
	Vector2i(71, 1),
	Vector2i(72, 1),
	Vector2i(72, 1),
	Vector2i(71, 2),
	Vector2i(0, 1),
	Vector2i(74, 1),
	Vector2i(74, 1),
	Vector2i(74, 1),
	Vector2i(76, 1),
	Vector2i(74, 1),
	Vector2i(72, 1),
	Vector2i(71, 1),
	Vector2i(69, 1),
	Vector2i(67, 2),
	Vector2i(0, 2),
	Vector2i(79, 1),
	Vector2i(78, 1),
]
const JARABE_B_CHORDS: Array[String] = ["D7", "G7", "D7", "G7", "D7", "G7", "G7", "G7"]

# Original compositions for Corona de Oro; each strain fills eight complete bars.
const CROWN_A: Array[Vector2i] = [
	Vector2i(72, 2),
	Vector2i(76, 1),
	Vector2i(79, 2),
	Vector2i(76, 1),
	Vector2i(74, 1),
	Vector2i(76, 1),
	Vector2i(79, 1),
	Vector2i(84, 2),
	Vector2i(0, 1),
	Vector2i(81, 2),
	Vector2i(77, 1),
	Vector2i(76, 2),
	Vector2i(77, 1),
	Vector2i(79, 3),
	Vector2i(76, 2),
	Vector2i(72, 1),
	Vector2i(76, 1),
	Vector2i(81, 1),
	Vector2i(79, 1),
	Vector2i(76, 2),
	Vector2i(72, 1),
	Vector2i(74, 2),
	Vector2i(78, 1),
	Vector2i(81, 2),
	Vector2i(78, 1),
	Vector2i(79, 1),
	Vector2i(77, 1),
	Vector2i(74, 1),
	Vector2i(71, 2),
	Vector2i(74, 1),
	Vector2i(72, 4),
	Vector2i(0, 2),
]
const CROWN_B: Array[Vector2i] = [
	Vector2i(76, 1),
	Vector2i(79, 1),
	Vector2i(76, 1),
	Vector2i(72, 2),
	Vector2i(67, 1),
	Vector2i(72, 2),
	Vector2i(74, 1),
	Vector2i(76, 2),
	Vector2i(79, 1),
	Vector2i(77, 1),
	Vector2i(81, 1),
	Vector2i(84, 1),
	Vector2i(81, 2),
	Vector2i(77, 1),
	Vector2i(76, 3),
	Vector2i(72, 2),
	Vector2i(0, 1),
	Vector2i(69, 2),
	Vector2i(72, 1),
	Vector2i(76, 2),
	Vector2i(81, 1),
	Vector2i(78, 1),
	Vector2i(81, 1),
	Vector2i(78, 1),
	Vector2i(74, 2),
	Vector2i(72, 1),
	Vector2i(71, 2),
	Vector2i(74, 1),
	Vector2i(77, 2),
	Vector2i(71, 1),
	Vector2i(72, 3),
	Vector2i(67, 1),
	Vector2i(72, 2),
]
const CROWN_CHORDS: Array[String] = ["C", "C", "F", "C", "Am", "D7", "G7", "C"]

const WALTZ_A: Array[Vector2i] = [
	Vector2i(76, 4),
	Vector2i(79, 2),
	Vector2i(81, 3),
	Vector2i(79, 1),
	Vector2i(76, 2),
	Vector2i(77, 2),
	Vector2i(81, 2),
	Vector2i(79, 2),
	Vector2i(76, 4),
	Vector2i(72, 2),
	Vector2i(77, 3),
	Vector2i(76, 1),
	Vector2i(74, 2),
	Vector2i(74, 2),
	Vector2i(78, 2),
	Vector2i(81, 2),
	Vector2i(79, 3),
	Vector2i(77, 1),
	Vector2i(74, 2),
	Vector2i(72, 5),
	Vector2i(0, 1),
]
const WALTZ_B: Array[Vector2i] = [
	Vector2i(79, 2),
	Vector2i(84, 3),
	Vector2i(83, 1),
	Vector2i(81, 4),
	Vector2i(76, 2),
	Vector2i(81, 3),
	Vector2i(79, 1),
	Vector2i(77, 2),
	Vector2i(79, 2),
	Vector2i(76, 2),
	Vector2i(72, 2),
	Vector2i(69, 2),
	Vector2i(72, 2),
	Vector2i(77, 2),
	Vector2i(78, 3),
	Vector2i(76, 1),
	Vector2i(74, 2),
	Vector2i(71, 2),
	Vector2i(74, 2),
	Vector2i(79, 2),
	Vector2i(76, 2),
	Vector2i(72, 4),
]
const WALTZ_CHORDS: Array[String] = ["C", "Am", "F", "C", "F", "D7", "G7", "C"]

const CHIP_A: Array[Vector2i] = [
	Vector2i(72, 1),
	Vector2i(76, 1),
	Vector2i(79, 2),
	Vector2i(76, 1),
	Vector2i(72, 1),
	Vector2i(67, 2),
	Vector2i(71, 2),
	Vector2i(74, 1),
	Vector2i(77, 1),
	Vector2i(79, 2),
	Vector2i(0, 2),
	Vector2i(76, 1),
	Vector2i(79, 1),
	Vector2i(84, 2),
	Vector2i(83, 1),
	Vector2i(81, 1),
	Vector2i(79, 2),
	Vector2i(81, 2),
	Vector2i(77, 2),
	Vector2i(72, 3),
	Vector2i(0, 1),
	Vector2i(76, 1),
	Vector2i(81, 1),
	Vector2i(79, 2),
	Vector2i(76, 2),
	Vector2i(72, 2),
	Vector2i(74, 1),
	Vector2i(78, 1),
	Vector2i(81, 2),
	Vector2i(78, 1),
	Vector2i(74, 1),
	Vector2i(72, 2),
	Vector2i(71, 2),
	Vector2i(74, 2),
	Vector2i(77, 1),
	Vector2i(74, 1),
	Vector2i(71, 2),
	Vector2i(72, 6),
	Vector2i(0, 2),
]
const CHIP_B: Array[Vector2i] = [
	Vector2i(79, 2),
	Vector2i(76, 1),
	Vector2i(72, 1),
	Vector2i(76, 2),
	Vector2i(79, 2),
	Vector2i(77, 1),
	Vector2i(74, 1),
	Vector2i(71, 2),
	Vector2i(67, 2),
	Vector2i(0, 2),
	Vector2i(72, 2),
	Vector2i(76, 2),
	Vector2i(79, 1),
	Vector2i(81, 1),
	Vector2i(84, 2),
	Vector2i(81, 1),
	Vector2i(79, 1),
	Vector2i(77, 2),
	Vector2i(76, 1),
	Vector2i(74, 1),
	Vector2i(72, 2),
	Vector2i(69, 2),
	Vector2i(72, 1),
	Vector2i(76, 1),
	Vector2i(81, 2),
	Vector2i(79, 2),
	Vector2i(78, 2),
	Vector2i(74, 1),
	Vector2i(72, 1),
	Vector2i(74, 2),
	Vector2i(78, 2),
	Vector2i(79, 1),
	Vector2i(77, 1),
	Vector2i(74, 2),
	Vector2i(71, 2),
	Vector2i(67, 2),
	Vector2i(72, 4),
	Vector2i(79, 2),
	Vector2i(72, 2),
]
const CHIP_CHORDS: Array[String] = ["C", "G7", "C", "F", "Am", "D7", "G7", "C"]

## unit_s: seconds per eighth note; sections: [melody, chords, lead voice].
const SONGS: Array[Dictionary] = [
	{
		"unit_s": 0.16,
		"pattern": POLKA,
		"sections":
		[
			[CUCARACHA_A, CUCARACHA_CHORDS, Voice.TRUMPET],
			[CUCARACHA_A, CUCARACHA_CHORDS, Voice.VIOLIN],
		],
	},
	{
		"unit_s": 0.155,
		"pattern": JIG,
		"sections":
		[
			[JARABE_A, JARABE_A_CHORDS, Voice.TRUMPET],
			[JARABE_B, JARABE_B_CHORDS, Voice.VIOLIN],
		],
	},
	{
		"unit_s": 0.145,
		"pattern": JIG,
		"sections":
		[
			[CROWN_A, CROWN_CHORDS, Voice.TRUMPET],
			[CROWN_B, CROWN_CHORDS, Voice.VIOLIN],
		],
	},
	{
		"unit_s": 0.235,
		"pattern": WALTZ,
		"sections":
		[
			[WALTZ_A, WALTZ_CHORDS, Voice.TRUMPET],
			[WALTZ_B, WALTZ_CHORDS, Voice.VIOLIN],
		],
	},
	{
		"unit_s": 0.135,
		"pattern": POLKA,
		"sections":
		[
			[CHIP_A, CHIP_CHORDS, Voice.TRUMPET],
			[CHIP_B, CHIP_CHORDS, Voice.VIOLIN],
		],
	},
]

## The C major scale's pitch classes, for the harmony a third below the tune.
const SCALE: Array[int] = [0, 2, 4, 5, 7, 9, 11]


static func count() -> int:
	return SONGS.size()


static func song_name(song: int) -> String:
	return NAMES[posmod(song, count())]


static func unit_s(song: int) -> float:
	return float(SONGS[posmod(song, count())]["unit_s"])


static func bar_units(song: int) -> int:
	return int((SONGS[posmod(song, count())]["pattern"] as Dictionary)["bar"])


static func bars(song: int) -> int:
	var total := 0
	for section: Array in SONGS[posmod(song, count())]["sections"]:
		total += (section[1] as Array).size()
	return total


## Seconds for one pass through the song (the baked clip's loop length).
static func duration(song: int) -> float:
	return bars(song) * bar_units(song) * unit_s(song)


## Which voice carries the tune `time` seconds into the song (looping).
static func lead_at(song: int, time: float) -> Voice:
	var sections: Array = SONGS[posmod(song, count())]["sections"]
	var section_s := duration(song) / sections.size()
	var index := clampi(int(fposmod(time, duration(song)) / section_s), 0, sections.size() - 1)
	return sections[index][2]


## Seconds since the last accompaniment hit of `kind` ("bass", "down" or "up";
## "strum" for either strum direction) at `time` into the song.
static func since_hit(song: int, time: float, kind: String) -> float:
	var pattern: Dictionary = SONGS[posmod(song, count())]["pattern"]
	var hits: Array = []
	if kind == "strum":
		hits = (pattern["down"] as Array) + (pattern["up"] as Array)
	else:
		hits = pattern[kind]
	var unit := unit_s(song)
	var bar := bar_units(song) * unit
	var in_bar := fposmod(time, bar)
	var best := INF
	for hit: int in hits:
		var at := hit * unit
		var since := in_bar - at if in_bar >= at else in_bar - at + bar
		best = minf(best, since)
	return best


## [index, fraction] of the melody note sounding at `time` (looping). Rests count
## as notes, so bowing and breathing can follow the phrase.
static func note_at(song: int, time: float) -> Vector2:
	var unit := unit_s(song)
	var local := fposmod(time, duration(song)) / unit
	var index := 0
	for section: Array in SONGS[posmod(song, count())]["sections"]:
		for note: Vector2i in section[0]:
			if local < note.y:
				return Vector2(index, local / note.y)
			local -= note.y
			index += 1
	return Vector2(index, 0.0)


## A diatonic third below `midi` in C; chromatic notes follow their lower neighbour.
static func harmony(midi: int) -> int:
	var pc := posmod(midi, 12)
	if pc not in SCALE:
		return harmony(midi - 1) + 1
	var degree := SCALE.find(pc)
	var below := SCALE[posmod(degree - 2, SCALE.size())]
	return midi - posmod(pc - below, 12)


## Chord tones for the vihuela strum, low to high, in its middle register.
static func voicing(chord: String) -> Array[int]:
	var notes: Array[int] = []
	for midi: int in range(55, 70):
		if posmod(midi, 12) in CHORDS[chord]:
			notes.append(midi)
	return notes


## Guitarrón note: the chord root, or its fifth, in the instrument's low octave.
static func bass_note(chord: String, fifth: bool) -> int:
	var pc: int = CHORDS[chord][0]
	if fifth:
		pc = posmod(pc + 7, 12)
	return 40 + posmod(pc - 4, 12)


## Every note of one pass through the song: {t, len, midi, voice, gain}, with times
## in seconds. Melody notes are doubled a third below (second trumpet, or the
## violin's double stop); the accompaniment follows each bar's chord.
static func score(song: int) -> Array[Dictionary]:
	var data: Dictionary = SONGS[posmod(song, count())]
	var unit := float(data["unit_s"])
	var pattern: Dictionary = data["pattern"]
	var bar_s := int(pattern["bar"]) * unit
	var notes: Array[Dictionary] = []
	var start := 0.0
	for section: Array in data["sections"]:
		var lead: Voice = section[2]
		var t := start
		for note: Vector2i in section[0]:
			if note.x > 0:
				var length := note.y * unit
				notes.append(_note(t, length, note.x, lead, 1.0))
				notes.append(_note(t, length, harmony(note.x), lead, 0.62))
			t += note.y * unit
		var chords: Array = section[1]
		for bar: int in chords.size():
			var chord: String = chords[bar]
			var bar_start := start + bar * bar_s
			var bass: Array = pattern["bass"]
			for i: int in bass.size():
				var at := bar_start + int(bass[i]) * unit
				var length := (bar_s / bass.size()) * 0.95
				notes.append(_note(at, length, bass_note(chord, i % 2 == 1), Voice.GUITARRON, 1.0))
			for kind: String in ["down", "up"]:
				for hit: int in pattern[kind]:
					_strum(notes, bar_start + hit * unit, unit, voicing(chord), kind == "down")
		start += chords.size() * bar_s
	return notes


static func _strum(
	notes: Array[Dictionary], at: float, unit: float, chord: Array[int], down: bool
) -> void:
	var strings := chord.duplicate()
	if not down:
		strings.reverse()
	for i: int in strings.size():
		var offset := i * 0.011
		notes.append(
			_note(at + offset, unit - offset, strings[i], Voice.VIHUELA, 1.0 if down else 0.6)
		)


static func _note(t: float, length: float, midi: int, voice: Voice, gain: float) -> Dictionary:
	return {"t": t, "len": length, "midi": midi, "voice": voice, "gain": gain}
