extends SceneTree
## Deterministic original mechanical sound design; no runtime synthesis.

const RATE := 22050
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 1964
	for cue: String in ["motor", "stop", "lever", "payout", "bell", "loss"]:
		var seconds := 1.0 if cue == "motor" else 1.8 if cue in ["payout", "bell"] else .35
		var samples := roundi(RATE * seconds)
		var data := PackedByteArray()
		data.resize(samples * 2)
		for i: int in samples:
			var t := float(i) / RATE
			var noise := _rng.randf_range(-1, 1)
			var value := 0.0
			match cue:
				"motor":
					var tooth := fposmod(t, 1.0 / 28.0)
					value = .08 * sin(TAU * 84 * t) + .04 * sin(TAU * 168 * t)
					value += .19 * exp(-tooth * 650) * (noise + sin(TAU * 1450 * tooth))
				"stop":
					value = exp(-t * 40) * (.45 * sin(TAU * 175 * t) + .26 * noise)
					value += .12 * sin(TAU * 1250 * t) * exp(-t * 65)
				"lever":
					value = .22 * noise * exp(-t * 65)
					var click := maxf(0, t - .16)
					if t >= .16:
						value += exp(-click * 40) * (.35 * sin(TAU * 240 * click) + .15 * noise)
				"payout":
					var coin := fposmod(t, .105)
					value = (
						exp(-coin * 65)
						* (
							.18 * sin(TAU * 2300 * coin)
							+ .12 * sin(TAU * 3710 * coin)
							+ .12 * noise
						)
					)
					value *= minf(1, (seconds - t) * 4)
				"bell":
					for strike: float in [0.0, .22, .44]:
						var age := t - strike
						if age >= 0:
							value += (
								.18
								* exp(-age * 4)
								* (
									sin(TAU * 880 * age)
									+ .45 * sin(TAU * 2319 * age)
									+ .2 * sin(TAU * 4101 * age)
								)
							)
				"loss":
					value = .16 * exp(-t * 25) * (sin(TAU * 120 * t) + noise * .45)
			# Tiny edge fades prevent clicks at playback/loop boundaries.
			value *= minf(1, minf(t, seconds - t) * 500)
			data.encode_s16(i * 2, roundi(clampf(value, -.95, .95) * 32767))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = RATE
		stream.data = data
		stream.save_to_wav("res://assets/slot_machine/audio/" + cue + ".wav")
	quit()
