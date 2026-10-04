extends SceneTree
## Bakes the band's songs (`MariachiSongs`, rendered by `MariachiSynth`) into the
## looping clips the game plays. Run from game/ after changing either script:
## godot --headless -s features/mariachi_band/tools/bake_songs.gd
## then `godot --headless --import` so the clips pick up their import settings.

const FILES: Array[String] = [
	"res://assets/mariachi_band/audio/la_cucaracha.wav",
	"res://assets/mariachi_band/audio/jarabe_tapatio.wav",
	"res://assets/mariachi_band/audio/brass_at_the_crown.wav",
	"res://assets/mariachi_band/audio/promenade_waltz.wav",
	"res://assets/mariachi_band/audio/last_chip_polka.wav",
]


func _init() -> void:
	for song: int in MariachiSongs.count():
		var started := Time.get_ticks_msec()
		var stream := MariachiSynth.render_stream(song)
		var error := stream.save_to_wav(FILES[song])
		print(
			(
				"%s: %.2f s in %d ms -> %s (%s)"
				% [
					MariachiSongs.song_name(song),
					stream.get_length(),
					Time.get_ticks_msec() - started,
					FILES[song],
					error_string(error),
				]
			)
		)
	quit()
