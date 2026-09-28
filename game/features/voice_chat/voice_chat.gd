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


var _indicator: Control
var _indicator_label: Label
var _emitters: Node3D
var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _talking := false
var _voices: Dictionary = {}  ## peer_id (int) -> _VoicePeer


func _ready() -> void:
	Controls.ensure_action(TALK_ACTION, [_key_event(KEY_V)])
	_emitters = Node3D.new()
	_emitters.name = "Emitters"
	add_child(_emitters)
	_build_indicator()


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
	_refresh_indicator()


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
	receive_voice_chunk.rpc(peer_id, chunk)


## Server -> everyone: play back a chunk from `sender_peer_id`. The sender gets its own
## chunk too (call_local) and just ignores it to avoid hearing itself.
@rpc("authority", "call_local", "unreliable_ordered")
func receive_voice_chunk(sender_peer_id: int, chunk: PackedByteArray) -> void:
	if sender_peer_id == multiplayer.get_unique_id():
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
	while _capture.get_frames_available() >= CHUNK_FRAMES:
		var frames := _capture.get_buffer(CHUNK_FRAMES)
		request_voice_chunk.rpc_id(1, encode_pcm16(frames))


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
	AudioServer.add_bus_effect(bus_idx, _capture)
	_mic_player = AudioStreamPlayer.new()
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


func _refresh_indicator() -> void:
	var names: Array[String] = []
	if _talking:
		names.append("You")
	for peer_id: int in _voices.keys():
		names.append(_speaker_label(peer_id))
	_indicator.visible = not names.is_empty()
	if not names.is_empty():
		_indicator_label.text = "Talking: " + ", ".join(names)


func _speaker_label(peer_id: int) -> String:
	var player := _player_for_peer(peer_id)
	if player and not player.display_name.is_empty():
		return player.display_name
	return "Player %d" % peer_id


func _build_indicator() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Indicator"
	add_child(layer)
	var panel := Control.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.position = Vector2(-268.0, -32.0)
	panel.custom_minimum_size = Vector2(256.0, 20.0)
	layer.add_child(panel)
	_indicator_label = Label.new()
	_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_indicator_label.custom_minimum_size = Vector2(256.0, 20.0)
	panel.add_child(_indicator_label)
	_indicator = panel
	_indicator.visible = false


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
