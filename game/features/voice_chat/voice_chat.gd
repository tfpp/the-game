extends Node
## Push-to-talk voice chat: hold V to transmit microphone audio to everyone else.
##
## Server-authoritative relay: a client only asks to relay a chunk it captured
## (`request_voice_chunk`); the server re-stamps it with the real sender's peer id and
## relays it to everyone (`receive_voice_chunk`), including the sender, who ignores its
## own echo. Playback is positional (`AudioStreamPlayer3D`), tracking the speaking
## player's position every frame. The microphone itself is only opened the first time
## the local player talks, so headless runs (servers, tests, smoke runs) never touch it.

const TALK_ACTION := &"voice_talk"
const CAPTURE_BUS_NAME := "VoiceCapture"
const SAMPLE_RATE := 16000
const CHUNK_DURATION_S := 0.1
const CHUNK_FRAMES := int(SAMPLE_RATE * CHUNK_DURATION_S)
const GENERATOR_BUFFER_S := 0.3
const SILENCE_TIMEOUT_S := 0.6


## One remote speaker's positional playback.
class _VoicePeer:
	var player: AudioStreamPlayer3D
	var playback: AudioStreamGeneratorPlayback
	var last_chunk_at := 0.0


var _emitters: Node3D
var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _talking := false
var _relay_times: Dictionary = {}
var _voices: Dictionary = {}  ## peer_id (int) -> _VoicePeer


func _ready() -> void:
	Controls.ensure_action(TALK_ACTION, [_key_event(KEY_V)])
	_emitters = Node3D.new()
	_emitters.name = "Emitters"
	add_child(_emitters)
	add_to_group(&"voice_chat")
	multiplayer.peer_disconnected.connect(_forget_peer)
	Network.mode_changed.connect(_reset_session)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TALK_ACTION) and Controls.gameplay_active():
		_start_talking()
	elif event.is_action_released(TALK_ACTION):
		_stop_talking()


func _process(_delta: float) -> void:
	if _talking and not Controls.gameplay_active():
		_stop_talking()
	if _talking:
		_pump_capture()
	_update_positions()
	_cleanup_stale_voices()


## Mono float [-1, 1] stereo-frame pairs, packed as little-endian 16-bit PCM. Pure and
## unit-tested; kept free of scene/audio access.
static func encode_pcm16(frames: PackedVector2Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		var sample := (frames[i].x + frames[i].y) * 0.5
		var quantized := clampi(int(round(sample * 32767.0)), -32768, 32767)
		bytes.encode_s16(i * 2, quantized)
	return bytes


## Inverse of `encode_pcm16`, expanded back to (identical) stereo frames for playback.
static func decode_pcm16(bytes: PackedByteArray) -> PackedVector2Array:
	var frame_count := bytes.size() / 2
	var frames := PackedVector2Array()
	frames.resize(frame_count)
	for i in frame_count:
		var sample := bytes.decode_s16(i * 2) / 32768.0
		frames[i] = Vector2(sample, sample)
	return frames


## Client -> server: relay an already-captured chunk. The server doesn't trust the
## sender's claimed identity, only `get_remote_sender_id()`.
@rpc("any_peer", "call_local", "unreliable_ordered")
func request_voice_chunk(chunk: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var peer_id := sender_id if sender_id != 0 else multiplayer.get_unique_id()
	if not _accept_chunk(peer_id, chunk, Time.get_ticks_msec()):
		return
	for recipient: int in multiplayer.get_peers():
		if recipient != peer_id:
			receive_voice_chunk.rpc_id(recipient, peer_id, chunk)
	if DisplayServer.get_name() != "headless":
		receive_voice_chunk(peer_id, chunk)


## Server -> listeners: play back a chunk from `sender_peer_id` without echoing it
## over the network to its sender or allocating audio on the dedicated server.
@rpc("authority", "call_local", "unreliable_ordered")
func receive_voice_chunk(sender_peer_id: int, chunk: PackedByteArray) -> void:
	if sender_peer_id == multiplayer.get_unique_id() or chunk.size() != CHUNK_FRAMES * 2:
		return
	_play_chunk(sender_peer_id, chunk)


## Client -> server: the local player released the talk key.
@rpc("any_peer", "call_local", "reliable")
func request_voice_stop() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var peer_id := sender_id if sender_id != 0 else multiplayer.get_unique_id()
	receive_voice_stop.rpc(peer_id)


## Server -> everyone: `sender_peer_id` stopped talking.
@rpc("authority", "call_local", "reliable")
func receive_voice_stop(sender_peer_id: int) -> void:
	if sender_peer_id != multiplayer.get_unique_id():
		_remove_voice(sender_peer_id)


func _start_talking() -> void:
	if _talking or Network.mode == Network.Mode.SERVER:
		return
	_ensure_capture_ready()
	_capture.clear_buffer()
	_talking = true


func _stop_talking() -> void:
	if not _talking:
		return
	_talking = false
	request_voice_stop.rpc_id(1)


func _pump_capture() -> void:
	var rate := float(AudioServer.get_mix_rate())
	var source_count := int(round(rate * CHUNK_DURATION_S))
	var available := _capture.get_frames_available()
	if available < source_count:
		return
	# Drop stale audio rather than sending a catch-up burst after a slow frame.
	if available >= source_count * 2:
		_capture.get_buffer(available - source_count)
	var frames := resample_chunk(_capture.get_buffer(source_count), rate)
	request_voice_chunk.rpc_id(1, encode_pcm16(frames))


static func resample_chunk(source: PackedVector2Array, rate: float) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(CHUNK_FRAMES)
	for i: int in CHUNK_FRAMES:
		var position := i * rate / SAMPLE_RATE
		var left := mini(int(position), source.size() - 1)
		var right := mini(left + 1, source.size() - 1)
		frames[i] = source[left].lerp(source[right], position - int(position))
	return frames


func _accept_chunk(peer_id: int, chunk: PackedByteArray, now: int) -> bool:
	if chunk.size() != CHUNK_FRAMES * 2:
		return false
	# Ten chunks/second with room for two adjacent deliveries due to network jitter.
	var next := int(_relay_times.get(peer_id, now))
	if now < next - 100:
		return false
	_relay_times[peer_id] = maxi(now, next) + 100
	return true


func _ensure_capture_ready() -> void:
	if _capture:
		return
	AudioServer.add_bus()
	var bus_idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_idx, CAPTURE_BUS_NAME)
	# Silent output, not a disabled bus: muting could skip effect processing, and the
	# capture effect below still needs to run.
	AudioServer.set_bus_volume_db(bus_idx, -80.0)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = GENERATOR_BUFFER_S
	AudioServer.add_bus_effect(bus_idx, _capture)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = CAPTURE_BUS_NAME
	add_child(_mic_player)
	_mic_player.play()


func _play_chunk(peer_id: int, chunk: PackedByteArray) -> void:
	var voice := _voice_for(peer_id)
	voice.last_chunk_at = Time.get_ticks_msec() / 1000.0
	var frames := decode_pcm16(chunk)
	if voice.playback.get_frames_available() >= frames.size():
		voice.playback.push_buffer(frames)


func _voice_for(peer_id: int) -> _VoicePeer:
	if _voices.has(peer_id):
		return _voices[peer_id] as _VoicePeer
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = GENERATOR_BUFFER_S
	var player3d := AudioStreamPlayer3D.new()
	player3d.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player3d.name = "Voice%d" % peer_id
	player3d.stream = generator
	_emitters.add_child(player3d)
	player3d.play()
	var voice := _VoicePeer.new()
	voice.player = player3d
	voice.playback = player3d.get_stream_playback() as AudioStreamGeneratorPlayback
	voice.last_chunk_at = Time.get_ticks_msec() / 1000.0
	_voices[peer_id] = voice
	return voice


func _remove_voice(peer_id: int) -> void:
	var voice: Variant = _voices.get(peer_id)
	if voice == null:
		return
	(voice as _VoicePeer).player.queue_free()
	_voices.erase(peer_id)


func _forget_peer(peer_id: int) -> void:
	_relay_times.erase(peer_id)
	_remove_voice(peer_id)


func _reset_session(_mode: Network.Mode) -> void:
	_talking = false
	_relay_times.clear()
	for peer_id: int in _voices.keys():
		_remove_voice(peer_id)


func _update_positions() -> void:
	for peer_id: int in _voices.keys():
		var player := _player_for_peer(peer_id)
		if player:
			(_voices[peer_id] as _VoicePeer).player.global_position = player.global_position


func _cleanup_stale_voices() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for peer_id: int in (_voices.keys() as Array).duplicate():
		if now - (_voices[peer_id] as _VoicePeer).last_chunk_at > SILENCE_TIMEOUT_S:
			_remove_voice(peer_id)


func _player_for_peer(peer_id: int) -> Player:
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.get_multiplayer_authority() == peer_id:
			return player
	return null


## Who is talking right now ("You" first), shown by the HUD's top-right VOICE line
## (ui/hud.gd), which finds this node through the `voice_chat` group.
func speaker_names() -> PackedStringArray:
	var names := PackedStringArray()
	if _talking:
		names.append("You")
	for peer_id: int in _voices.keys():
		names.append(_speaker_label(peer_id))
	return names


func _speaker_label(peer_id: int) -> String:
	var player := _player_for_peer(peer_id)
	if player and not player.display_name.is_empty():
		return player.display_name
	return "Player %d" % peer_id


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
