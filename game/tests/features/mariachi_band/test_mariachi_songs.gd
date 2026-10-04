extends GutTest
## The repertoire's rules and timing, the synthesizer, and the baked clips.


func test_every_section_fills_its_bars_exactly() -> void:
	for song: int in MariachiSongs.count():
		var bar := MariachiSongs.bar_units(song)
		for section: Array in MariachiSongs.SONGS[song]["sections"]:
			var units := 0
			for note: Vector2i in section[0]:
				assert_gt(note.y, 0, "notes have length")
				units += note.y
			assert_eq(units, (section[1] as Array).size() * bar, MariachiSongs.song_name(song))
			for chord: String in section[1]:
				assert_true(MariachiSongs.CHORDS.has(chord), "known chord %s" % chord)


func test_songs_have_names_and_loop_lengths() -> void:
	assert_eq(MariachiSongs.count(), 5)
	assert_eq(MariachiSongs.song_name(0), "La Cucaracha")
	assert_eq(MariachiSongs.song_name(1), "Jarabe Tapatío")
	assert_eq(MariachiSongs.song_name(2), "Brass at the Crown")
	assert_eq(MariachiSongs.song_name(3), "Promenade Waltz")
	assert_eq(MariachiSongs.song_name(4), "Last Chip Polka")
	assert_eq(MariachiSongs.song_name(5), "La Cucaracha", "indices wrap")
	assert_eq(MariachiSongs.song_name(-1), "Last Chip Polka")
	assert_almost_eq(MariachiSongs.duration(0), 16 * 8 * 0.16, 0.0001)
	assert_almost_eq(MariachiSongs.duration(1), 16 * 6 * 0.155, 0.0001)


func test_harmony_sits_a_third_below_the_tune() -> void:
	assert_eq(MariachiSongs.harmony(72), 69, "C over A")
	assert_eq(MariachiSongs.harmony(76), 72, "E over C")
	assert_eq(MariachiSongs.harmony(79), 76, "G over E")
	assert_eq(MariachiSongs.harmony(74), 71, "D over B")
	assert_eq(MariachiSongs.harmony(75), 72, "chromatic D# follows D's harmony up")
	for midi: int in range(60, 84):
		var gap := midi - MariachiSongs.harmony(midi)
		assert_between(gap, 2, 4, "third below %d" % midi)


func test_accompaniment_stays_in_each_instruments_register() -> void:
	for chord: String in MariachiSongs.CHORDS:
		var strum := MariachiSongs.voicing(chord)
		assert_gte(strum.size(), 3, "a full chord for %s" % chord)
		for midi: int in strum:
			assert_between(midi, 55, 69)
			assert_true(posmod(midi, 12) in MariachiSongs.CHORDS[chord])
		for fifth: bool in [false, true]:
			assert_between(MariachiSongs.bass_note(chord, fifth), 40, 51)
	assert_eq(posmod(MariachiSongs.bass_note("G7", false), 12), 7, "root")
	assert_eq(posmod(MariachiSongs.bass_note("G7", true), 12), 2, "fifth")


func test_score_covers_the_whole_song_with_every_voice() -> void:
	for song: int in MariachiSongs.count():
		var voices: Dictionary = {}
		for note: Dictionary in MariachiSongs.score(song):
			voices[note["voice"]] = true
			assert_between(float(note["t"]), 0.0, MariachiSongs.duration(song))
			assert_gt(float(note["len"]), 0.0)
		assert_eq(voices.size(), 4, "trumpet, violin, vihuela and guitarrón all play")


func test_trumpets_and_violin_take_turns_with_the_tune() -> void:
	var half := MariachiSongs.duration(0) / 2.0
	assert_eq(MariachiSongs.lead_at(0, 1.0), MariachiSongs.Voice.TRUMPET)
	assert_eq(MariachiSongs.lead_at(0, half + 1.0), MariachiSongs.Voice.VIOLIN)
	assert_eq(
		MariachiSongs.lead_at(0, MariachiSongs.duration(0) + 1.0), MariachiSongs.Voice.TRUMPET
	)
	assert_true(MariachiMusicianModel.playing(MariachiMusicianModel.Instrument.TRUMPET, 0, 1.0))
	assert_false(MariachiMusicianModel.playing(MariachiMusicianModel.Instrument.VIOLIN, 0, 1.0))
	assert_true(MariachiMusicianModel.playing(MariachiMusicianModel.Instrument.VIHUELA, 0, 1.0))


func test_hits_and_notes_follow_the_beat() -> void:
	var unit := MariachiSongs.unit_s(0)
	assert_almost_eq(MariachiSongs.since_hit(0, 0.0, "bass"), 0.0, 0.0001)
	assert_almost_eq(MariachiSongs.since_hit(0, unit * 3.5, "bass"), unit * 3.5, 0.0001)
	assert_almost_eq(MariachiSongs.since_hit(0, unit * 2.25, "strum"), unit * 0.25, 0.0001)
	assert_almost_eq(
		MariachiSongs.since_hit(0, unit * 1.5, "strum"), unit * 2.5, 0.0001, "last bar"
	)
	assert_eq(MariachiSongs.note_at(0, 0.0), Vector2(0, 0))
	assert_eq(MariachiSongs.note_at(0, unit * 4.0), Vector2(1, 0.5), "second note, halfway")
	assert_almost_eq(MariachiMusicianModel.bow_travel(Vector2(0, 0.25)), 0.25, 0.0001)
	assert_almost_eq(MariachiMusicianModel.bow_travel(Vector2(1, 0.25)), 0.75, 0.0001)
	assert_almost_eq(MariachiMusicianModel.strum_offset(0.05), -0.07, 0.0001)
	assert_almost_eq(MariachiMusicianModel.strum_offset(1.0), 0.0, 0.0001)


func test_synth_renders_deterministic_normalized_audio() -> void:
	var first := MariachiSynth.render(1, 0.6)
	var again := MariachiSynth.render(1, 0.6)
	assert_eq(first.size(), int(round(0.6 * MariachiSynth.MIX_RATE)))
	assert_eq(first, again, "same song, same samples")
	var peak := 0.0
	for sample: float in first:
		peak = maxf(peak, absf(sample))
	assert_almost_eq(peak, MariachiSynth.PEAK, 0.001)
	var stream := MariachiSynth.to_stream(first)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, first.size())
	assert_eq(stream.data.size(), first.size() * 2)
	assert_almost_eq(MariachiSynth.frequency(69), 440.0, 0.001)
	assert_almost_eq(MariachiSynth.frequency(81), 880.0, 0.001)


func test_new_compositions_have_distinct_melodies_and_audible_renders() -> void:
	for song: int in range(2, MariachiSongs.count()):
		var melody: Array = MariachiSongs.SONGS[song]["sections"][0][0]
		for other: int in song:
			assert_ne(melody, MariachiSongs.SONGS[other]["sections"][0][0], "a new tune")
		var half := MariachiSongs.duration(song) / 2.0
		assert_eq(MariachiSongs.lead_at(song, half - 0.001), MariachiSongs.Voice.TRUMPET)
		assert_eq(MariachiSongs.lead_at(song, half), MariachiSongs.Voice.VIOLIN)
		assert_eq(
			MariachiSongs.lead_at(song, MariachiSongs.duration(song)), MariachiSongs.Voice.TRUMPET
		)
		assert_true(
			MariachiMusicianModel.playing(
				MariachiMusicianModel.Instrument.VIOLIN, song, half + 0.01
			)
		)
		assert_almost_eq(MariachiSongs.since_hit(song, 0.0, "bass"), 0.0, 0.0001)
		var samples := MariachiSynth.render(song, 0.6)
		var peak := 0.0
		for sample: float in samples:
			peak = maxf(peak, absf(sample))
		assert_almost_eq(peak, MariachiSynth.PEAK, 0.001, "not silent or clipping")
		assert_eq(samples, MariachiSynth.render(song, 0.6), "deterministic")


func test_baked_clips_loop_for_exactly_one_pass_of_each_song() -> void:
	assert_eq(MariachiBand.STREAMS.size(), MariachiSongs.count())
	for song: int in MariachiSongs.count():
		var clip := MariachiBand.STREAMS[song] as AudioStreamWAV
		assert_not_null(clip)
		assert_eq(clip.loop_mode, AudioStreamWAV.LOOP_FORWARD, "the clip loops")
		assert_eq(clip.mix_rate, MariachiSynth.MIX_RATE)
		assert_false(clip.stereo)
		assert_almost_eq(clip.get_length(), MariachiSongs.duration(song), 0.01)
