extends GutTest
## Pure synthesis for the garage's ambience (features/parking_garage/procedural_audio.gd).

const ProceduralAudio := preload("res://features/parking_garage/procedural_audio.gd")


func test_rain_and_wind_loop_is_a_seamless_looping_mono_stream() -> void:
	var stream := ProceduralAudio.rain_and_wind_loop(1, 2.0)
	assert_eq(stream.mix_rate, ProceduralAudio.MIX_RATE)
	assert_false(stream.stereo)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.data.size(), int(2.0 * ProceduralAudio.MIX_RATE) * 2)


func test_rain_and_wind_loop_is_deterministic_for_a_given_seed() -> void:
	var a := ProceduralAudio.rain_and_wind_loop(7)
	var b := ProceduralAudio.rain_and_wind_loop(7)
	assert_eq(a.data, b.data)


func test_rain_and_wind_loop_differs_across_seeds() -> void:
	var a := ProceduralAudio.rain_and_wind_loop(1)
	var b := ProceduralAudio.rain_and_wind_loop(2)
	assert_ne(a.data, b.data)


func test_hum_loop_is_a_one_second_seamless_loop() -> void:
	var stream := ProceduralAudio.hum_loop(120.0, 3)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, ProceduralAudio.MIX_RATE)
	assert_eq(stream.data.size(), ProceduralAudio.MIX_RATE * 2)


func test_drip_blip_is_a_short_one_shot() -> void:
	var stream := ProceduralAudio.drip_blip(9)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	assert_true(stream.data.size() > 0)


func test_structural_creak_is_a_short_one_shot() -> void:
	var stream := ProceduralAudio.structural_creak(11)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	assert_true(stream.data.size() > 0)
