extends SceneTree
## Bake only the passage and fade duration to mono 11 kHz / 8-bit PCM.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var stream := (
		AudioStreamWAV
		. load_from_file(
			args[0],
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
	var samples := mini(stream.data.size(), ceili(37.0 * stream.mix_rate))
	var data := stream.data.slice(0, samples)
	if data.size() % 2 != 0:
		data.append(0)
	stream.data = data
	var result := stream.save_to_wav("res://assets/pawn_shop/audio/doll_passage.wav")
	print("Passage audio: ", stream.get_length(), " s, ", stream.data.size(), " bytes")
	quit(result)
