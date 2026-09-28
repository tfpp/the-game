extends GutTest
## Pure PCM packing for voice chat (features/voice_chat/voice_chat.gd): kept free of
## scene/audio access so it's unit-testable.

const VoiceChat := preload("res://features/voice_chat/voice_chat.gd")


func test_round_trip_preserves_values_within_quantization() -> void:
	var frames := PackedVector2Array(
		[Vector2(0.5, 0.5), Vector2(-0.25, -0.25), Vector2(0.0, 0.0), Vector2(-1.0, -1.0)]
	)
	var decoded := VoiceChat.decode_pcm16(VoiceChat.encode_pcm16(frames))
	for i in frames.size():
		assert_almost_eq(decoded[i].x, frames[i].x, 1.0 / 32768.0)


func test_encode_clamps_out_of_range_samples() -> void:
	var frames := PackedVector2Array([Vector2(2.0, 2.0), Vector2(-3.0, -3.0)])
	var decoded := VoiceChat.decode_pcm16(VoiceChat.encode_pcm16(frames))
	assert_almost_eq(decoded[0].x, 1.0, 1.0 / 32768.0)
	assert_almost_eq(decoded[1].x, -1.0, 1.0 / 32768.0)


func test_encode_mixes_stereo_frame_down_to_mono() -> void:
	var frames := PackedVector2Array([Vector2(1.0, -1.0)])
	var decoded := VoiceChat.decode_pcm16(VoiceChat.encode_pcm16(frames))
	assert_almost_eq(decoded[0].x, 0.0, 1.0 / 32768.0)


func test_encode_produces_two_bytes_per_frame() -> void:
	var frames := PackedVector2Array()
	frames.resize(VoiceChat.CHUNK_FRAMES)
	assert_eq(VoiceChat.encode_pcm16(frames).size(), VoiceChat.CHUNK_FRAMES * 2)


func test_decode_of_empty_bytes_is_empty() -> void:
	assert_eq(VoiceChat.decode_pcm16(PackedByteArray()).size(), 0)
