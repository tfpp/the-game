extends SceneTree
## Original eight-second lounge loop: soft seventh/ninth chords and walking bass.
## Native synthesis avoids external audio dependencies or third-party music.

const RATE := 22050
const LENGTH_S := 8


func _initialize() -> void:
	var mix := PackedFloat32Array()
	mix.resize(RATE * LENGTH_S)
	var chords: Array[Array] = [
		[60, 63, 67, 70, 74], [65, 69, 72, 75, 79], [61, 65, 68, 72], [59, 62, 65, 69]
	]
	var bass: Array[int] = [48, 53, 49, 43]
	for bar: int in 4:
		for pitch: int in chords[bar]:
			_note(mix, bar * 2.0 + 0.1, 1.8, pitch, 0.06)
		for beat: int in 4:
			_note(mix, bar * 2.0 + beat * 0.5, 0.4, bass[bar] + (7 if beat % 2 == 1 else 0), 0.12)
	var data := PackedByteArray()
	data.resize(mix.size() * 2)
	for i: int in mix.size():
		data.encode_s16(i * 2, int(clampf(mix[i], -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.mix_rate = RATE
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = mix.size()
	DirAccess.make_dir_recursive_absolute("res://assets/vip_lounge")
	var result := stream.save_to_wav("res://assets/vip_lounge/mirror_club.wav")
	print("VIP music saved: ", result)
	quit(0 if result == OK else 1)


func _note(mix: PackedFloat32Array, start: float, duration: float, pitch: int, gain: float) -> void:
	var frequency := 440.0 * pow(2.0, (pitch - 69) / 12.0)
	var first := int(start * RATE)
	var count := int(duration * RATE)
	for sample: int in count:
		var t := float(sample) / RATE
		var envelope := minf(t / 0.015, 1.0) * exp(-3.0 * t) * minf((duration - t) / 0.1, 1.0)
		var phase := TAU * frequency * t
		var value := sin(phase) + 0.3 * sin(phase * 2.0) + 0.12 * sin(phase * 3.0)
		mix[(first + sample) % mix.size()] += value * gain * envelope
