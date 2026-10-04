extends SceneTree
## Bake one shot per weapon and shared reload cues to mono 11 kHz / 8-bit PCM.

const CLIPS := {
	"pistol_shot": "Pistol Shot.wav",
	"mp5_shot": "Machine Gun Shot.wav",
	"m4a4_shot": "Assault Rifle Shot.wav",
	"ak47_shot": "Assault Rifle Shot 2.wav",
	"shotgun_shot": "Shotgun Shot.wav",
	"awp_shot": "Sniper Shot.wav",
	"reload_mag_out": "Mag Out.wav",
	"reload_mag_in": "Mag In.wav",
	"reload_charge": "Reload.wav",
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	for id: String in CLIPS:
		var result := _bake(args[0].path_join(CLIPS[id]), id)
		if result != OK:
			quit(result)
			return
	quit()


func _bake(source: String, id: String) -> Error:
	var stream := AudioStreamWAV.load_from_file(
		source,
		{
			"force/mono": true,
			"force/8_bit": true,
			"force/max_rate": true,
			"force/max_rate_hz": 11025,
			"edit/trim": true,
			"edit/normalize": true,
			"compress/mode": 0
		}
	)
	if stream == null:
		return ERR_CANT_OPEN
	var data := stream.data.slice(0, mini(stream.data.size(), int(11025 * .8)))
	var fade := mini(data.size(), 220)
	for index: int in fade:
		var offset := data.size() - fade + index
		var value := int(data[offset])
		if value > 127:
			value -= 256
		data[offset] = int(round(value * float(fade - 1 - index) / maxf(1, fade - 1))) & 255
	# RIFF chunks require even byte lengths; pad signed PCM with silence.
	if data.size() % 2 != 0:
		data.append(0)
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var result := stream.save_to_wav("res://assets/game_audio/audio/" + id + ".wav")
	print(id, ": ", stream.get_length(), " seconds, ", data.size(), " bytes, mono 11025 Hz / 8-bit")
	return result
