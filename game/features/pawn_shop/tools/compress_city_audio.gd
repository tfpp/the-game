extends SceneTree
## Bake the user-provided WAVs to small mono 11 kHz / 8-bit PCM sources.
## Run with -- <source-folder>; the game imports these with QOA compression.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var files := DirAccess.get_files_at(args[0])
	var index := 0
	for filename: String in files:
		if filename.get_extension().to_lower() != "wav":
			continue
		var stream := (
			AudioStreamWAV
			. load_from_file(
				args[0].path_join(filename),
				{
					"force/mono": true,
					"force/8_bit": true,
					"force/max_rate": true,
					"force/max_rate_hz": 11025,
					"compress/mode": 0,
				}
			)
		)
		if stream == null:
			quit(1)
			return
		var result := stream.save_to_wav(
			"res://assets/pawn_shop/audio/road_ambience_%d.wav" % index
		)
		if result != OK:
			quit(result)
			return
		print("%s: %.1f s, %d bytes" % [filename, stream.get_length(), stream.data.size()])
		index += 1
	quit()
